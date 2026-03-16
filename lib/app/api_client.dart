// lib/app/api_client.dart
//
// RETRY STRATEGY
// ──────────────
// Not all HTTP operations are safe to retry. This file enforces the rule:
//
//   GET                → _retryGet()    — always idempotent, up to 3 retries
//   DELETE (all)       → _retryDelete() — treats 404 as success (idempotent),
//                                         up to 3 retries
//   POST (mutations)   → NO retry       — importWorkspace, createSection,
//                                         importStudents are not idempotent.
//                                         Surface errors immediately; let UI
//                                         show a "Try again" button.
//   PATCH              → NO retry       — field updates are user-driven;
//                                         retrying a stale value would
//                                         silently overwrite a newer edit.
//   POST /ask          → _retryAsk()    — read-only in effect, up to 2 retries.
//
// Retryable conditions : timeout, socket/network error, HTTP 5xx.
// Never retried        : HTTP 4xx (client error — retrying would be wrong).
//
// Backoff: 500 ms → 1 s → 2 s  (exponential, capped at _maxRetries attempts).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../app/workspace_models.dart';

// ── ApiException ──────────────────────────────────────────────────────────────
// Typed exception that carries enough context for retry helpers to decide
// whether another attempt makes sense, and for the UI to surface a useful
// message without any additional parsing.

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.isTimeout = false,
    this.isNetworkError = false,
  });

  /// Human-readable description — safe to show directly in the UI.
  final String message;

  /// HTTP status code, or null for network / timeout errors.
  final int? statusCode;

  /// True when the request timed out (no response received).
  final bool isTimeout;

  /// True for socket errors, connection refused, no internet, etc.
  final bool isNetworkError;

  /// True when retrying this error could plausibly succeed.
  bool get isRetryable =>
      isTimeout || isNetworkError || (statusCode != null && statusCode! >= 500);

  @override
  String toString() => message;
}

// ── Result types ──────────────────────────────────────────────────────────────

class ImportResult {
  final int imported;
  final String sectionId;
  final String fileHash;

  const ImportResult({
    required this.imported,
    required this.sectionId,
    this.fileHash = '',
  });
}

class ImportWorkspaceResult {
  final Workspace workspace;
  final bool alreadyUploaded;
  const ImportWorkspaceResult({
    required this.workspace,
    required this.alreadyUploaded,
  });
}

// ── ApiClient ─────────────────────────────────────────────────────────────────

class ApiClient {
  ApiClient({required String baseUrl}) : baseUri = _normalizeBaseUri(baseUrl);

  final Uri baseUri;

  // ── Retry configuration ───────────────────────────────────────────────────
  static const int _maxRetries = 3;
  static const int _maxAskRetries = 2;
  static const Duration _baseDelay = Duration(milliseconds: 500);

  // ── URI helpers ───────────────────────────────────────────────────────────

  static Uri _normalizeBaseUri(String raw) {
    var s = raw.trim();
    if (s.isEmpty) throw Exception('BASE_URL is empty.');
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    while (s.endsWith('/')) s = s.substring(0, s.length - 1);
    final u = Uri.parse(s);
    if (u.host.isEmpty) throw Exception('Invalid BASE_URL (no host): $s');
    return u;
  }

  Uri _u(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return baseUri.resolve(p);
  }

  // ── Retry helpers ─────────────────────────────────────────────────────────

  /// Retry wrapper for GET requests.
  /// Fails immediately on 4xx — client errors are not transient.
  /// Retries on timeout, SocketException, or 5xx up to [_maxRetries] times.
  /// Delay doubles each attempt: 500 ms, 1 s, 2 s.
  Future<http.Response> _retryGet(Uri uri, {Duration? timeout}) async {
    final t = timeout ?? AppConfig.shortTimeout;
    int attempt = 0;

    while (true) {
      try {
        final resp = await http.get(uri).timeout(t);

        if (resp.statusCode >= 400 && resp.statusCode < 500) {
          throw ApiException(
            _extractDetail(resp),
            statusCode: resp.statusCode,
          );
        }
        if (resp.statusCode >= 500) {
          throw ApiException(
            _extractDetail(resp),
            statusCode: resp.statusCode,
          );
        }
        return resp;
      } on ApiException catch (e) {
        attempt++;
        if (!e.isRetryable || attempt >= _maxRetries) rethrow;
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } on TimeoutException {
        attempt++;
        if (attempt >= _maxRetries) {
          throw const ApiException(
            'Request timed out. Check your connection and try again.',
            isTimeout: true,
          );
        }
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } on SocketException catch (e) {
        attempt++;
        if (attempt >= _maxRetries) {
          throw ApiException(
            'Network error: ${e.message}',
            isNetworkError: true,
          );
        }
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } catch (e) {
        throw ApiException(e.toString());
      }
    }
  }

  /// Retry wrapper for DELETE requests.
  ///
  /// When [treat404AsSuccess] is true (the default), HTTP 404 is treated as
  /// a successful outcome — the resource is already gone, which is exactly
  /// what a DELETE achieves. This prevents the classic retry bug:
  ///   1. DELETE succeeds on the server
  ///   2. Network drops before the response arrives
  ///   3. Client retries, gets 404, shows an error
  ///   4. User is confused — the operation actually worked
  ///
  /// Set [treat404AsSuccess] to false only when the backend returns a resource
  /// in the response body that the caller needs (e.g. deleteSection returns
  /// the updated workspace JSON).
  Future<http.Response?> _retryDelete(
    Uri uri, {
    Duration? timeout,
    bool treat404AsSuccess = true,
  }) async {
    final t = timeout ?? AppConfig.shortTimeout;
    int attempt = 0;

    while (true) {
      try {
        final resp = await http.delete(uri).timeout(t);

        if (resp.statusCode == 404 && treat404AsSuccess) return null;

        if (resp.statusCode >= 400 && resp.statusCode < 500) {
          throw ApiException(
            _extractDetail(resp),
            statusCode: resp.statusCode,
          );
        }
        if (resp.statusCode >= 500) {
          throw ApiException(
            _extractDetail(resp),
            statusCode: resp.statusCode,
          );
        }
        return resp;
      } on ApiException catch (e) {
        attempt++;
        if (!e.isRetryable || attempt >= _maxRetries) rethrow;
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } on TimeoutException {
        attempt++;
        if (attempt >= _maxRetries) {
          throw const ApiException(
            'Request timed out. Check your connection and try again.',
            isTimeout: true,
          );
        }
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } on SocketException catch (e) {
        attempt++;
        if (attempt >= _maxRetries) {
          throw ApiException(
            'Network error: ${e.message}',
            isNetworkError: true,
          );
        }
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } catch (e) {
        throw ApiException(e.toString());
      }
    }
  }

  /// Retry wrapper for POST /ask only.
  /// The ask endpoint is read-only in effect (LLM query), so retrying is safe,
  /// but capped at [_maxAskRetries] = 2 to avoid hammering the LLM backend.
  Future<http.Response> _retryAsk(
    Uri uri,
    String body, {
    Duration? timeout,
  }) async {
    final t = timeout ?? AppConfig.standardTimeout;
    int attempt = 0;

    while (true) {
      try {
        final resp = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(t);

        if (resp.statusCode >= 400 && resp.statusCode < 500) {
          throw ApiException(
            _extractDetail(resp),
            statusCode: resp.statusCode,
          );
        }
        if (resp.statusCode >= 500) {
          throw ApiException(
            _extractDetail(resp),
            statusCode: resp.statusCode,
          );
        }
        return resp;
      } on ApiException catch (e) {
        attempt++;
        if (!e.isRetryable || attempt >= _maxAskRetries) rethrow;
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } on TimeoutException {
        attempt++;
        if (attempt >= _maxAskRetries) {
          throw const ApiException(
            'Ask timed out. Try again.',
            isTimeout: true,
          );
        }
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } on SocketException catch (e) {
        attempt++;
        if (attempt >= _maxAskRetries) {
          throw ApiException(
            'Network error: ${e.message}',
            isNetworkError: true,
          );
        }
        await Future.delayed(_baseDelay * (1 << (attempt - 1)));
      } catch (e) {
        throw ApiException(e.toString());
      }
    }
  }

  // ── Workspaces ────────────────────────────────────────────────────────────

  /// POST — NOT retried.
  /// Uploading the same file twice would create a duplicate workspace.
  /// Backend hash-dedup is a safety net, not a licence to retry blindly.
  Future<ImportWorkspaceResult> importWorkspace({
    required Uint8List bytes,
    required String filename,
    String preferredId = '',
  }) async {
    final req = http.MultipartRequest('POST', _u('/workspaces/upload'))
      ..fields['preferred_id'] = preferredId
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: _contentTypeFor(filename),
        ),
      );

    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(AppConfig.uploadTimeout);
    } on TimeoutException {
      throw const ApiException(
        'Upload timed out — try again on Wi-Fi.',
        isTimeout: true,
      );
    } on SocketException catch (e) {
      throw ApiException(
        'Network error while uploading: ${e.message}',
        isNetworkError: true,
      );
    } catch (e) {
      throw ApiException('Upload failed: $e');
    }

    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw ApiException(_extractDetail(resp), statusCode: resp.statusCode);
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ImportWorkspaceResult(
      workspace: Workspace.fromJson(map['workspace'] as Map<String, dynamic>),
      alreadyUploaded: (map['already_uploaded'] as bool?) ?? false,
    );
  }

  /// GET — retried up to 3 times with exponential backoff.
  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final resp = await _retryGet(_u('/workspaces'));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['workspaces'] as List)
        .map((e) => WorkspaceSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET — retried up to 3 times.
  Future<Workspace> getWorkspace(String id) async {
    final resp = await _retryGet(_u('/workspaces/$id'));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  /// PATCH — NOT retried.
  /// Retrying a stale PATCH could silently overwrite a newer edit.
  Future<Workspace> updateWorkspaceFields(
    String id,
    Map<String, String> fields,
  ) async {
    final http.Response resp;
    try {
      resp = await http
          .patch(
            _u('/workspaces/$id'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'fields': fields}),
          )
          .timeout(AppConfig.shortTimeout);
    } on TimeoutException {
      throw const ApiException(
        'Save timed out. Check your connection and try again.',
        isTimeout: true,
      );
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}', isNetworkError: true);
    }
    if (resp.statusCode != 200) {
      throw ApiException(_extractDetail(resp), statusCode: resp.statusCode);
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  /// POST — NOT retried. Creating a section twice produces duplicates.
  Future<Workspace> createSection(String wid, SectionDraft d) async {
    final http.Response resp;
    try {
      resp = await http
          .post(
            _u('/workspaces/$wid/sections'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(d.toJson()),
          )
          .timeout(AppConfig.shortTimeout);
    } on TimeoutException {
      throw const ApiException(
        'Request timed out. Try again.',
        isTimeout: true,
      );
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}', isNetworkError: true);
    }
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw ApiException(_extractDetail(resp), statusCode: resp.statusCode);
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['workspace'] != null) {
      return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
    }
    return getWorkspace(wid);
  }

  /// PATCH — NOT retried. Same reasoning as updateWorkspaceFields.
  Future<Workspace> updateSection(
    String wid,
    String sectionId,
    SectionDraft d,
  ) async {
    final http.Response resp;
    try {
      resp = await http
          .patch(
            _u('/workspaces/$wid/sections/$sectionId'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(d.toJson()),
          )
          .timeout(AppConfig.shortTimeout);
    } on TimeoutException {
      throw const ApiException('Save timed out. Try again.', isTimeout: true);
    } on SocketException catch (e) {
      throw ApiException('Network error: ${e.message}', isNetworkError: true);
    }
    if (resp.statusCode != 200) {
      throw ApiException(_extractDetail(resp), statusCode: resp.statusCode);
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['workspace'] != null) {
      return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
    }
    return getWorkspace(wid);
  }

  /// DELETE — retried.
  /// [treat404AsSuccess] is false because the backend returns the updated
  /// workspace JSON — the caller needs that data.
  Future<Workspace> deleteSection(String workspaceId, String sectionId) async {
    final resp = await _retryDelete(
      _u('/workspaces/$workspaceId/sections/$sectionId'),
      treat404AsSuccess: false,
    );
    final map = jsonDecode(resp!.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  /// DELETE — retried. 404 treated as success.
  Future<void> deleteWorkspace(String workspaceId) async {
    await _retryDelete(
      _u('/workspaces/$workspaceId'),
      treat404AsSuccess: true,
    );
  }

  /// POST — NOT retried.
  /// Importing the same file twice doubles the roster.
  Future<ImportResult> importStudents({
    required String workspaceId,
    required Uint8List bytes,
    required String filename,
    String sectionId = '',
  }) async {
    final req = http.MultipartRequest(
      'POST',
      _u('/workspaces/$workspaceId/students/import'),
    )
      ..fields['section_id'] = sectionId
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: filename.toLowerCase().endsWith('.xlsx')
              ? MediaType(
                  'application',
                  'vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                )
              : MediaType('text', 'csv'),
        ),
      );

    final http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(AppConfig.standardTimeout);
    } on TimeoutException {
      throw const ApiException(
        'Import timed out. Try again on Wi-Fi.',
        isTimeout: true,
      );
    } on SocketException catch (e) {
      throw ApiException(
        'Network error during import: ${e.message}',
        isNetworkError: true,
      );
    }

    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw ApiException(_extractDetail(resp), statusCode: resp.statusCode);
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ImportResult(
      imported: int.tryParse((map['imported'] ?? 0).toString()) ?? 0,
      sectionId: (map['section_id'] ?? sectionId).toString(),
      fileHash: (map['file_hash'] ?? '').toString(),
    );
  }

  /// GET — retried up to 3 times.
  Future<List<Student>> listSectionStudents(
    String workspaceId,
    String sectionId,
  ) async {
    final resp = await _retryGet(
      _u('/workspaces/$workspaceId/sections/$sectionId/students'),
    );
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((map['students'] as List?) ?? [])
        .map((e) => Student.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// DELETE — retried. 404 treated as success.
  /// If DELETE succeeded but the network dropped before the response arrived,
  /// the retry gets 404 — silently treated as success, no false error shown.
  Future<void> clearSectionStudents(
    String workspaceId,
    String sectionId,
  ) async {
    await _retryDelete(
      _u('/workspaces/$workspaceId/sections/$sectionId/students'),
      treat404AsSuccess: true,
    );
  }

  /// DELETE — retried. 404 treated as success.
  /// Optimistic UI: Flutter removes from list immediately; this call confirms
  /// deletion on the backend.
  Future<void> deleteStudent(
    String workspaceId,
    String sectionId,
    String studentId,
  ) async {
    await _retryDelete(
      _u('/workspaces/$workspaceId/sections/$sectionId/students/$studentId'),
      treat404AsSuccess: true,
    );
  }

  /// POST /ask — retried up to 2 times.
  /// Read-only in effect (LLM query), safe to retry.
  Future<String> ask(String wid, String question) async {
    final resp = await _retryAsk(
      _u('/workspaces/$wid/ask'),
      jsonEncode({'question': question}),
    );
    if (resp.statusCode == 504) {
      throw const ApiException('Ask timed out. Try again.', isTimeout: true);
    }
    if (resp.statusCode != 200) {
      throw ApiException(_extractDetail(resp), statusCode: resp.statusCode);
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['answer'] ?? '').toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  MediaType _contentTypeFor(String filename) {
    final f = filename.toLowerCase();
    if (f.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (f.endsWith('.docx')) {
      return MediaType(
        'application',
        'vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
    }
    return MediaType('text', 'plain');
  }

  String _extractDetail(http.Response resp) {
    try {
      final m = jsonDecode(resp.body);
      if (m is Map && m['detail'] != null) return m['detail'].toString();
    } catch (_) {}
    return 'Request failed (${resp.statusCode}).';
  }
}
