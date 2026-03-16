// lib/app/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../app/workspace_models.dart';

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

class ApiClient {
  ApiClient({required String baseUrl}) : baseUri = _normalizeBaseUri(baseUrl);

  final Uri baseUri;

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

  // ── Workspaces ─────────────────────────────────────────────────────────────

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
      throw Exception('Upload timed out — try again on Wi-Fi.');
    } catch (e) {
      throw Exception('Network/CORS error while uploading. ($e)');
    }

    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ImportWorkspaceResult(
      workspace: Workspace.fromJson(map['workspace'] as Map<String, dynamic>),
      alreadyUploaded: (map['already_uploaded'] as bool?) ?? false,
    );
  }

  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final resp =
        await http.get(_u('/workspaces')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['workspaces'] as List)
        .map((e) => WorkspaceSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Workspace> getWorkspace(String id) async {
    final resp =
        await http.get(_u('/workspaces/$id')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  Future<Workspace> updateWorkspaceFields(
    String id,
    Map<String, String> fields,
  ) async {
    final resp = await http
        .patch(
          _u('/workspaces/$id'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fields': fields}),
        )
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  Future<Workspace> createSection(String wid, SectionDraft d) async {
    final resp = await http
        .post(
          _u('/workspaces/$wid/sections'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(d.toJson()),
        )
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception(_extractDetail(resp));
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['workspace'] != null) {
      return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
    }
    return getWorkspace(wid);
  }

  Future<Workspace> updateSection(
    String wid,
    String sectionId,
    SectionDraft d,
  ) async {
    final resp = await http
        .patch(
          _u('/workspaces/$wid/sections/$sectionId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(d.toJson()),
        )
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['workspace'] != null) {
      return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
    }
    return getWorkspace(wid);
  }

  Future<Workspace> deleteSection(String workspaceId, String sectionId) async {
    final resp = await http
        .delete(_u('/workspaces/$workspaceId/sections/$sectionId'))
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final resp = await http
        .delete(_u('/workspaces/$workspaceId'))
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
  }

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
    final streamed = await req.send().timeout(AppConfig.standardTimeout);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ImportResult(
      imported: int.tryParse((map['imported'] ?? 0).toString()) ?? 0,
      sectionId: (map['section_id'] ?? sectionId).toString(),
      fileHash: (map['file_hash'] ?? '').toString(),
    );
  }

  Future<List<Student>> listSectionStudents(
    String workspaceId,
    String sectionId,
  ) async {
    final resp = await http
        .get(_u('/workspaces/$workspaceId/sections/$sectionId/students'))
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((map['students'] as List?) ?? [])
        .map((e) => Student.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Remove ALL students from a section in one call.
  Future<void> clearSectionStudents(
    String workspaceId,
    String sectionId,
  ) async {
    final resp = await http
        .delete(
          _u('/workspaces/$workspaceId/sections/$sectionId/students'),
        )
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
  }

  /// Remove a single student from a section.
  /// Optimistic UI: Flutter removes from list immediately; this call
  /// confirms deletion on the backend.
  Future<void> deleteStudent(
    String workspaceId,
    String sectionId,
    String studentId,
  ) async {
    final resp = await http
        .delete(
          _u('/workspaces/$workspaceId/sections/$sectionId/students/$studentId'),
        )
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
  }

  /// Sends the current question plus trimmed conversation history so the
  /// backend LLM can resolve follow-up questions like "what about that?".
  /// [history] is the full chat list from the UI (oldest first), each entry
  /// a map with "role" ("user"|"assistant") and "content" keys.
  Future<String> ask(
    String wid,
    String question, {
    List<Map<String, String>> history = const [],
  }) async {
    // Cap at 20 entries client-side (10 turns); backend trims to 6 turns.
    final trimmedHistory =
        history.length > 20 ? history.sublist(history.length - 20) : history;

    final resp = await http
        .post(
          _u('/workspaces/$wid/ask'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'question': question,
            'history': trimmedHistory,
          }),
        )
        .timeout(AppConfig.standardTimeout);
    if (resp.statusCode == 504) throw Exception('Ask timed out. Try again.');
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['answer'] ?? '').toString();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  MediaType _contentTypeFor(String filename) {
    final f = filename.toLowerCase();
    if (f.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (f.endsWith('.docx'))
      return MediaType(
        'application',
        'vnd.openxmlformats-officedocument.wordprocessingml.document',
      );
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
