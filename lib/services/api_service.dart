import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

// --- Teammate's Models & Config ---
import '../config/app_config.dart';
import '../app/workspace_models.dart';

// --- Your Models ---
import '../models/course_model.dart';
import '../models/question_model.dart';
import '../models/config_model.dart';

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

class ApiService {
  // Your static URL approach
  static final String _baseUrl = "https://instructormate.onrender.com";

  // Helper to cleanly build URLs
  Uri _u(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$p');
  }

  // =========================================================================
  // ── YOUR ORIGINAL METHODS ────────────────────────────────────────────────
  // =========================================================================

  Future<List<Course>> fetchCourses() async {
    var response = await http.get(_u('/courses/')).timeout(AppConfig.shortTimeout);
    if (response.statusCode == 200) {
      List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.map((j) => Course.fromJson(j)).toList();
    } else {
      throw Exception("Failed to load courses");
    }
  }

  Future<void> uploadMaterial(int courseId, File file, String type) async {
    var req = http.MultipartRequest('POST', _u('/courses/$courseId/materials/'));
    req.fields['material_type'] = type;
    req.files.add(await http.MultipartFile.fromPath('file', file.path));
    
    var streamed = await req.send().timeout(AppConfig.uploadTimeout);
    var response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception("Upload failed: ${response.body}");
    }
  }

  Future<List<QuizQuestion>> generateDirectlyFromFile(File file, List<QuestionTypeConfig> configs) async {
    var request = http.MultipartRequest('POST', _u('/generate-direct'));
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    List<Map<String, dynamic>> configList = configs.map((c) => {
      'type': c.name,
      'count': c.count,
      'difficulty': c.difficulty,
      'topic': c.topicController.text,
    }).toList();
    
    request.fields['configs'] = jsonEncode(configList);

    var streamed = await request.send().timeout(AppConfig.uploadTimeout); 
    var responseData = await http.Response.fromStream(streamed);

    if (responseData.statusCode == 200) {
      final decodedData = jsonDecode(responseData.body);
      List<dynamic> questionsList = decodedData['questions'] ?? decodedData;
      return questionsList.map((q) => QuizQuestion.fromJson(q)).toList();
    } else {
      final errorData = jsonDecode(responseData.body);
      throw Exception(errorData['detail']?.toString() ?? 'Generation failed');
    }
  }

  Future<List<QuizQuestion>> generateQuiz(int courseId, List<int> selectedMaterialIds, List<QuestionTypeConfig> configs) async {
    // 1. Package the configurations into JSON
    List<Map<String, dynamic>> configList = configs.map((c) => {
      'type': c.name,
      'count': c.count,
      'difficulty': c.difficulty,
      'topic': c.topicController.text,
    }).toList();

    // 2. Build the request body matching the backend schema
    Map<String, dynamic> requestBody = {
      'selected_material_ids': selectedMaterialIds,
      'configs': configList,
    };

    // 3. Send the POST request to the cloud route
    // Notice we use your _u() helper to prevent the double-slash bug!
    final response = await http.post(
      _u('/courses/$courseId/generate-quiz/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    ).timeout(AppConfig.uploadTimeout); // Using a longer timeout since AI generation takes time

    // 4. Parse the results
    if (response.statusCode == 200) {
      final decodedData = jsonDecode(response.body);
      List<dynamic> questionsList = decodedData['questions'] ?? decodedData;
      return questionsList.map((q) => QuizQuestion.fromJson(q)).toList();
    } else {
      throw Exception(_extractDetail(response));
    }
  }

  // =========================================================================
  // ── TEAMMATE'S METHODS (Adapted for ApiService) ──────────────────────────
  // =========================================================================

  Future<ImportWorkspaceResult> importWorkspace({
    required Uint8List bytes,
    required String filename,
    String preferredId = '',
  }) async {
    final req = http.MultipartRequest('POST', _u('/workspaces/upload'))
      ..fields['preferred_id'] = preferredId
      ..files.add(
        http.MultipartFile.fromBytes(
          'file', bytes, filename: filename, contentType: _contentTypeFor(filename),
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
    final resp = await http.get(_u('/workspaces')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['workspaces'] as List)
        .map((e) => WorkspaceSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Workspace> getWorkspace(String id) async {
    final resp = await http.get(_u('/workspaces/$id')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  Future<Workspace> updateWorkspaceFields(String id, Map<String, String> fields) async {
    final resp = await http.patch(
      _u('/workspaces/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fields': fields}),
    ).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  Future<Workspace> createSection(String wid, SectionDraft d) async {
    final resp = await http.post(
      _u('/workspaces/$wid/sections'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(d.toJson()),
    ).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception(_extractDetail(resp));
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['workspace'] != null) return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
    return getWorkspace(wid);
  }

  Future<Workspace> updateSection(String wid, String sectionId, SectionDraft d) async {
    final resp = await http.patch(
      _u('/workspaces/$wid/sections/$sectionId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(d.toJson()),
    ).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['workspace'] != null) return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
    return getWorkspace(wid);
  }

  Future<Workspace> deleteSection(String workspaceId, String sectionId) async {
    final resp = await http.delete(_u('/workspaces/$workspaceId/sections/$sectionId')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
  }

  Future<void> deleteWorkspace(String workspaceId) async {
    final resp = await http.delete(_u('/workspaces/$workspaceId')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
  }

  Future<ImportResult> importStudents({
    required String workspaceId, required Uint8List bytes, required String filename, String sectionId = '',
  }) async {
    final req = http.MultipartRequest('POST', _u('/workspaces/$workspaceId/students/import'))
      ..fields['section_id'] = sectionId
      ..files.add(
        http.MultipartFile.fromBytes(
          'file', bytes, filename: filename,
          contentType: filename.toLowerCase().endsWith('.xlsx')
              ? MediaType('application', 'vnd.openxmlformats-officedocument.spreadsheetml.sheet')
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

  Future<List<Student>> listSectionStudents(String workspaceId, String sectionId) async {
    final resp = await http.get(_u('/workspaces/$workspaceId/sections/$sectionId/students')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((map['students'] as List?) ?? []).map((e) => Student.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<int> addStudent({
    required String workspaceId, required String sectionId, required String name, required String email, required String studentNo,
  }) async {
    final resp = await http.post(
      _u('/workspaces/$workspaceId/sections/$sectionId/students'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name.trim(), 'email': email.trim(), 'student_no': studentNo.trim()}),
    ).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return int.tryParse((map['count'] ?? 0).toString()) ?? 0;
  }

  Future<void> clearSectionStudents(String workspaceId, String sectionId) async {
    final resp = await http.delete(_u('/workspaces/$workspaceId/sections/$sectionId/students')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
  }

  Future<void> deleteStudent(String workspaceId, String sectionId, String studentId) async {
    final resp = await http.delete(_u('/workspaces/$workspaceId/sections/$sectionId/students/$studentId')).timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
  }

  Future<String> ask(String wid, String question, {List<Map<String, String>> history = const []}) async {
    final trimmedHistory = history.length > 20 ? history.sublist(history.length - 20) : history;
    final resp = await http.post(
      _u('/workspaces/$wid/ask'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'question': question, 'history': trimmedHistory}),
    ).timeout(AppConfig.standardTimeout);
    if (resp.statusCode == 504) throw Exception('Ask timed out. Try again.');
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['answer'] ?? '').toString();
  }

  // -----------------------------
  // Import Student_List
  // -----------------------------
  Future<Map<String, dynamic>> uploadStudentList({required File file}) async {
    try {
      final req = http.MultipartRequest('POST', _u('/students/upload'));

      final filePart = await http.MultipartFile.fromPath('file', file.path);

      req.files.add(filePart);

      final streamed = await req.send().timeout(AppConfig.uploadTimeout); // Added your standard timeout here!
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      return {
        "ok": false,
        "status": response.statusCode,
        "error": response.body,
      };
    } catch (e) {
      return {"ok": false, "error": e.toString()};
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  MediaType _contentTypeFor(String filename) {
    final f = filename.toLowerCase();
    if (f.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (f.endsWith('.docx')) return MediaType('application', 'vnd.openxmlformats-officedocument.wordprocessingml.document');
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