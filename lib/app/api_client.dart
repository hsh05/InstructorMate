// lib/app/api_client.dart
import 'dart:async';                    //(all HTTP calls to backend)
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../app/workspace_models.dart';

class ApiClient {
  ApiClient({required String baseUrl}) : baseUri = _normalizeBaseUri(baseUrl);

  final Uri baseUri;

  static Uri _normalizeBaseUri(String raw) {  
    var s = raw.trim();
    if (s.isEmpty) throw Exception("BASE_URL is empty. Example: http://127.0.0.1:8000");
    if (!s.startsWith("http://") && !s.startsWith("https://")) s = "http://$s";
    while (s.endsWith("/")) s = s.substring(0, s.length - 1);
    final u = Uri.parse(s);
    if (u.host.isEmpty) throw Exception("Invalid BASE_URL (no host): $s");
    return u;
  }

  Uri _u(String path) {
    final p = path.startsWith("/") ? path : "/$path";
    return baseUri.resolve(p);
  }

  // ---------------------------
  // Workspaces
  // ---------------------------
  Future<Workspace> importWorkspace({ //(endpoint methods )These are the backend calls my UI/viewmodel relies on:
    required Uint8List bytes,
    required String filename,
    String preferredId = "",
  }) async {
    // FIX: backend endpoint is /workspaces/upload
    final req = http.MultipartRequest("POST", _u("/workspaces/upload"))
      ..fields["preferred_id"] = preferredId
      ..files.add(
        http.MultipartFile.fromBytes(
          "file",
          bytes,
          filename: filename,
          contentType: _contentTypeFor(filename),
        ),
      );

    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw Exception("Import timed out. Try again.");
    } catch (e) {
      throw Exception("Network/CORS error while uploading. Check backend CORS + port. ($e)");
    }

    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) {
      throw Exception(_extractDetail(resp));
    }

    final map = jsonDecode(resp.body) as Map<String, dynamic>;

    // backend returns { workspace: {...}, ... }
    final wsMap = map["workspace"] as Map<String, dynamic>;
    return Workspace.fromJson(wsMap);
  }

  Future<List<WorkspaceSummary>> listWorkspaces() async {
    final resp = await http.get(_u("/workspaces")).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));

    final arr = jsonDecode(resp.body) as List<dynamic>;
    return arr
        .map((e) => WorkspaceSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Workspace> getWorkspace(String id) async {
    final resp = await http.get(_u("/workspaces/$id")).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    return Workspace.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<Workspace> updateWorkspaceFields(String id, Map<String, String> fields) async {
    final resp = await http
        .patch(
          _u("/workspaces/$id"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"fields": fields}),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    return Workspace.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<Workspace> createSection(String wid, SectionDraft d) async {
    final resp = await http
        .post(
          _u("/workspaces/$wid/sections"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode(d.toJson()),
        )
        .timeout(const Duration(seconds: 20));

    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    return Workspace.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<Workspace> importStudents({
    required String workspaceId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final req = http.MultipartRequest(
      "POST",
      _u("/workspaces/$workspaceId/students/import"),
    )..files.add(
        http.MultipartFile.fromBytes(
          "file",
          bytes,
          filename: filename,
          contentType: MediaType("text", "csv"),
        ),
      );

    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);

    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    return Workspace.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<String> ask(String wid, String question) async {
    final resp = await http
        .post(
          _u("/workspaces/$wid/ask"),
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"question": question}),
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode == 504) throw Exception("Ask timed out. Try again.");
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));

    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map["answer"] ?? "").toString();
  }

  // ---------------------------
  // Helpers
  // ---------------------------
  MediaType _contentTypeFor(String filename) {
    final f = filename.toLowerCase();
    if (f.endsWith(".pdf")) return MediaType("application", "pdf");
    if (f.endsWith(".docx")) {
      return MediaType("application", "vnd.openxmlformats-officedocument.wordprocessingml.document");
    }
    return MediaType("text", "plain");
  }

  String _extractDetail(http.Response resp) {
    try {
      final m = jsonDecode(resp.body);
      if (m is Map && m["detail"] != null) return m["detail"].toString();
    } catch (_) {}
    return "Request failed (${resp.statusCode}).";
  }
}
