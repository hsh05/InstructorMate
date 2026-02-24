// lib/app/api_client.dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../app/workspace_models.dart';

// ── Result types ──────────────────────────────────────────────────────────────

class ImportResult {
  final int imported;
  final String sectionId;
  const ImportResult({required this.imported, required this.sectionId});
}

class ImportWorkspaceResult {
  final Workspace workspace;
  final bool alreadyUploaded;
  const ImportWorkspaceResult({
    required this.workspace,
    required this.alreadyUploaded,
  });
}

class Student {
  final String studentId;
  final String name;
  final String email;
  final String studentNo;
  const Student({
    required this.studentId,
    required this.name,
    required this.email,
    required this.studentNo,
  });
  factory Student.fromJson(Map<String, dynamic> j) => Student(
    studentId: (j['student_id'] ?? j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    email: (j['email'] ?? '').toString(),
    studentNo: (j['student_no'] ?? '').toString(),
  );
}

// ── Client ────────────────────────────────────────────────────────────────────

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

  // ── Wake-up ping — Render free tier sleeps after inactivity ─────────────────
  // Call this on app start. Retries up to 6 times (≈ 60 seconds) to wait for
  // the instance to cold-start. Throws a friendly error if it never comes up.
  Future<void> pingUntilAlive({void Function(int attempt)? onRetry}) async {
    const maxAttempts = 10;
    for (var i = 1; i <= maxAttempts; i++) {
      try {
        final resp = await http
            .get(
              _u('/workspaces'),
            ) // ping /workspaces — we know this route exists
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) return; // server is awake
      } catch (_) {}
      if (i < maxAttempts) {
        onRetry?.call(i);
        await Future.delayed(const Duration(seconds: 12));
      }
    }
    throw Exception(
      'Could not reach the server after ${maxAttempts * 12} seconds.\n'
      'Check your internet connection or try again in a moment.',
    );
  }

  // ── Workspaces ──────────────────────────────────────────────────────────────

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
    final resp = await http
        .get(_u('/workspaces'))
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['workspaces'] as List)
        .map((e) => WorkspaceSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Workspace> getWorkspace(String id) async {
    final resp = await http
        .get(_u('/workspaces/$id'))
        .timeout(AppConfig.shortTimeout);
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
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    return await getWorkspace(wid);
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
    final req =
        http.MultipartRequest(
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

  Future<Workspace> reuploadSyllabus({
    required String workspaceId,
    required Uint8List bytes,
    required String filename,
  }) async {
    final req =
        http.MultipartRequest('POST', _u('/workspaces/$workspaceId/reupload'))
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              bytes,
              filename: filename,
              contentType: _contentTypeFor(filename),
            ),
          );
    final streamed = await req.send().timeout(AppConfig.reuploadTimeout);
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  Future<String> ask(String wid, String question) async {
    final resp = await http
        .post(
          _u('/workspaces/$wid/ask'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'question': question}),
        )
        .timeout(AppConfig.standardTimeout);
    if (resp.statusCode == 504) throw Exception('Ask timed out. Try again.');
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['answer'] ?? '').toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
