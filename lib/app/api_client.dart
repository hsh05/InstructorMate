// lib/app/api_client.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// SRP: backend communication only.
class ApiClient {
  ApiClient({required String baseUrl, required this.timeout})
      : baseUri = _normalizeBaseUri(baseUrl);

  final Uri baseUri;
  final Duration timeout;

  // Optional: override for endpoints that are naturally slower (e.g. PDF convert).
  static const Duration convertDefaultTimeout = Duration(seconds: 120);
  static const Duration askDefaultTimeout = Duration(seconds: 30);

  /// Normalize BASE_URL so it works on every platform.
  static Uri _normalizeBaseUri(String raw) {
    var s = (raw).trim();
    if (s.isEmpty) {
      throw Exception("BASE_URL is empty. Example: http://127.0.0.1:8000");
    }

    if (!s.startsWith("http://") && !s.startsWith("https://")) {
      s = "http://$s";
    }

    while (s.endsWith("/")) {
      s = s.substring(0, s.length - 1);
    }

    final u = Uri.parse(s);
    if (u.host.isEmpty) {
      throw Exception("Invalid BASE_URL (no host): $s");
    }
    return u;
  }

  /// Safe URL builder.
  Uri _u(String path, {Map<String, String>? q}) {
    final cleanPath = path.startsWith("/") ? path : "/$path";
    var uri = baseUri.resolve(cleanPath);
    if (q != null && q.isNotEmpty) {
      uri = uri.replace(queryParameters: q);
    }
    return uri;
  }

  // ----------------------------
  // Convert upload → doc_id
  // ----------------------------
  Future<String> convertUploadGetDocId({
    required Uint8List pdfBytes,
    required String fileName,
    Duration? requestTimeout, // allow per-call override
  }) async {
    if (pdfBytes.isEmpty) {
      throw Exception("PDF is empty.");
    }
    final safeName = fileName.trim().isEmpty ? "syllabus.pdf" : fileName.trim();

    final req = http.MultipartRequest('POST', _u("/convert-upload"))
      ..files.add(
        http.MultipartFile.fromBytes(
          'pdf',
          pdfBytes,
          filename: safeName,
          contentType: MediaType('application', 'pdf'),
        ),
      );

    final usedTimeout = requestTimeout ?? convertDefaultTimeout;
    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(usedTimeout);
    } on TimeoutException {
      throw Exception("Convert request timed out after ${usedTimeout.inSeconds}s.");
    } on SocketException catch (e) {
      throw Exception("Network error (socket): ${e.message}. Check internet / URL / DNS.");
    } on HandshakeException catch (e) {
      throw Exception("TLS/SSL handshake failed: ${e.message}. Use https:// and verify cert.");
    } catch (e) {
      throw Exception("Convert request failed: $e");
    }

    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw Exception(_extractBackendDetail(resp));
    }

    final j = _decodeJsonMap(resp.body, fallbackMessage: "Invalid JSON from backend.");
    final docId = (j["doc_id"] ?? "").toString().trim();

    if (docId.isEmpty) {
      throw Exception("Backend returned no doc_id.");
    }
    return docId;
  }

  // ----------------------------
  // CSV view as text
  // ----------------------------
  Future<String> fetchCsvTextByDocId({
    required String docId,
    String kind = "single_row",
    Duration? requestTimeout,
  }) async {
    final d = docId.trim();
    if (d.isEmpty) throw Exception("docId is empty.");

    final k = kind.trim().isEmpty ? "single_row" : kind.trim();

    final uri = _u("/csv-text", q: {"doc_id": d, "kind": k});

    final usedTimeout = requestTimeout ?? timeout;

    http.Response resp;
    try {
      resp = await http.get(uri).timeout(usedTimeout);
    } catch (_) {
      throw Exception("Request timed out while loading CSV text.");
    }

    if (resp.statusCode != 200) {
      throw Exception(_extractBackendDetail(resp));
    }
    return resp.body;
  }

  // ----------------------------
  // CSV download link
  // ----------------------------
  Uri csvDownloadByDocIdUri({
    required String docId,
    String kind = "single_row",
  }) {
    final d = docId.trim();
    final k = kind.trim().isEmpty ? "single_row" : kind.trim();
    return _u("/csv-download", q: {"doc_id": d, "kind": k});
  }

  // ----------------------------
  // Ask question
  // ----------------------------
  Future<String> ask({
    required String question,
    required String docId,
    Duration? requestTimeout,
  }) async {
    final q = question.trim();
    final d = docId.trim();

    if (d.isEmpty) throw Exception("docId is empty.");
    if (q.isEmpty) throw Exception("Question is empty.");

    final uri = _u("/ask");
    final usedTimeout = requestTimeout ?? askDefaultTimeout;

    http.Response resp;
    try {
      resp = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              // Optional: add a client request-id header for debugging (server echoes x-request-id back)
              // "x-request-id": DateTime.now().millisecondsSinceEpoch.toString(),
            },
            body: jsonEncode({"question": q, "doc_id": d}),
          )
          .timeout(usedTimeout);
    } catch (_) {
      // Client-side timeout (different from server 504)
      throw Exception("Answer took too long. Please try again.");
    }

    // Server-side timeout handling (your FastAPI returns 504 now)
    if (resp.statusCode == 504) {
      // Prefer backend detail if present
      final msg = _extractBackendDetail(resp);
      throw Exception(msg.isNotEmpty ? msg : "Server timed out while answering. Try again.");
    }

    if (resp.statusCode != 200) {
      throw Exception(_extractBackendDetail(resp));
    }

    final j = _decodeJsonMap(resp.body, fallbackMessage: "Invalid JSON from backend.");
    return (j["answer"] ?? "").toString();
  }

  // ----------------------------
  // Helpers
  // ----------------------------
  Map<String, dynamic> _decodeJsonMap(String body, {required String fallbackMessage}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception(fallbackMessage);
    } catch (_) {
      throw Exception(fallbackMessage);
    }
  }

  String _extractBackendDetail(http.Response resp) {
    // Default (always includes status)
    var msg = "Request failed (${resp.statusCode}).";

    // Try JSON detail (FastAPI style)
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded['detail'] != null) {
        final d = decoded['detail'].toString().trim();
        if (d.isNotEmpty) return d;
      }
    } catch (_) {
      // ignore
    }

    // Fallback to short body snippet (avoid dumping huge HTML into UI)
    final raw = resp.body.trim();
    if (raw.isNotEmpty) {
      final snippet = raw.length > 300 ? "${raw.substring(0, 300)}…" : raw;
      msg = "$msg $snippet";
    }
    return msg;
  }
}
