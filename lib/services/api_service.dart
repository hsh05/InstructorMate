// lib/services/api_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config/app_config.dart';
import '../models/workspace_model.dart';
import '../models/question_model.dart';
import '../models/config_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  static const String _baseUrl = "https://instructormate.onrender.com";

  // Helper to cleanly build URLs
  Uri _u(String path) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl$p');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  MediaType _contentTypeFor(String filename) {
    final f = filename.toLowerCase();
    if (f.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (f.endsWith('.docx'))
      return MediaType('application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document');
    return MediaType('text', 'plain');
  }

  String _extractDetail(http.Response resp) {
    try {
      final m = jsonDecode(resp.body);
      if (m is Map && m['detail'] != null) return m['detail'].toString();
    } catch (_) {}
    return 'Request failed (${resp.statusCode}).';
  }

  // ===========================================================================
  // ── Original Workspace & AI Methods ────────────────────────────────────────
  // ===========================================================================

  Future<List<Workspace>> fetchWorkspaces() async {
    const storage = FlutterSecureStorage();
    final userId = await storage.read(key: 'user_id') ?? '';
    var response = await http
        .get(_u('/workspaces/?user_id=$userId'))
        .timeout(AppConfig.shortTimeout);

    if (response.statusCode == 200) {
      var decoded = jsonDecode(response.body);
      List<dynamic> jsonList = decoded is Map ? decoded['workspaces'] : decoded;
      return jsonList.map((j) => Workspace.fromJson(j)).toList();
    } else {
      throw Exception("Failed to load workspaces");
    }
  }

  Future<List<QuizQuestion>> generateDirectlyFromFile(
      File file, List<QuestionTypeConfig> configs) async {
    var request = http.MultipartRequest('POST', _u('/generate-direct'));
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    List<Map<String, dynamic>> configList = configs
        .map((c) => {
              'type': c.name,
              'count': c.count,
              'difficulty': c.difficulty,
              'topic': c.topicController.text,
            })
        .toList();

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

  Future<List<QuizQuestion>> generateQuiz(int workspaceId,
      List<int> selectedMaterialIds, List<QuestionTypeConfig> configs) async {
    List<Map<String, dynamic>> configList = configs
        .map((c) => {
              'type': c.name,
              'count': c.count,
              'difficulty': c.difficulty,
              'topic': c.topicController.text,
            })
        .toList();

    Map<String, dynamic> requestBody = {
      'selected_material_ids': selectedMaterialIds,
      'configs': configList,
    };

    final response = await http
        .post(
          _u('/workspaces/$workspaceId/generate-quiz/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(AppConfig.uploadTimeout);

    if (response.statusCode == 200) {
      final decodedData = jsonDecode(response.body);
      List<dynamic> questionsList = decodedData['questions'] ?? decodedData;
      return questionsList.map((q) => QuizQuestion.fromJson(q)).toList();
    } else {
      throw Exception(_extractDetail(response));
    }
  }

  Future<List<dynamic>> generateQuizFromMaterials({
    required String workspaceId,
    required List<int> selectedMaterialIds,
    required List<Map<String, dynamic>> configs,
  }) async {
    final response = await http.post(
      _u('/workspaces/$workspaceId/generate-quiz/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'selected_material_ids': selectedMaterialIds,
        'configs': configs,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['questions'] as List<dynamic>;
    } else {
      throw Exception('Failed to generate quiz: ${response.body}');
    }
  }

  Future<void> uploadMaterial(
      String workspaceId, Uint8List bytes, String filename) async {
    final request = http.MultipartRequest(
        'POST', _u('/workspaces/$workspaceId/materials/'));
    request.files
        .add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamedResponse =
        await request.send().timeout(AppConfig.uploadTimeout);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200)
      throw Exception('Failed to upload material: ${response.body}');
  }

  Future<void> deleteMaterial(String materialId) async {
    final response = await http.delete(_u('/materials/$materialId'));
    if (response.statusCode != 200)
      throw Exception('Failed to delete material: ${response.body}');
  }

  Future<ImportWorkspaceResult> importWorkspace({
    required Uint8List bytes,
    required String filename,
    String preferredId = '',
    String? startDate,
    String? endDate,
  }) async {
    const storage = FlutterSecureStorage();
    final userId = await storage.read(key: 'user_id') ?? '';

    final req = http.MultipartRequest('POST', _u('/workspaces/upload'))
      ..fields['preferred_id'] = preferredId
      ..fields['instructor_id'] = userId
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: _contentTypeFor(filename),
        ),
      );

    if (startDate != null && startDate.isNotEmpty)
      req.fields['start_date'] = startDate;
    if (endDate != null && endDate.isNotEmpty) req.fields['end_date'] = endDate;

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
    const storage = FlutterSecureStorage();
    final userId = await storage.read(key: 'user_id') ?? '';
    final resp = await http
        .get(_u('/workspaces?instructor_id=$userId'))
        .timeout(AppConfig.shortTimeout);

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
      String id, Map<String, String> fields) async {
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
    if (resp.statusCode != 200 && resp.statusCode != 201)
      throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['workspace'] != null)
      return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
    return getWorkspace(wid);
  }

  Future<Workspace> updateSection(
      String wid, String sectionId, SectionDraft d) async {
    final resp = await http
        .patch(
          _u('/workspaces/$wid/sections/$sectionId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(d.toJson()),
        )
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    if (map['workspace'] != null)
      return Workspace.fromJson(map['workspace'] as Map<String, dynamic>);
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
        'POST', _u('/workspaces/$workspaceId/students/import'))
      ..fields['section_id'] = sectionId
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: filename.toLowerCase().endsWith('.xlsx')
              ? MediaType('application',
                  'vnd.openxmlformats-officedocument.spreadsheetml.sheet')
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
      String workspaceId, String sectionId) async {
    final resp = await http
        .get(_u('/workspaces/$workspaceId/sections/$sectionId/students'))
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return ((map['students'] as List?) ?? [])
        .map((e) => Student.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> addStudent({
    required String workspaceId,
    required String sectionId,
    required String name,
    required String email,
    required String studentNo,
  }) async {
    final resp = await http
        .post(
          _u('/workspaces/$workspaceId/sections/$sectionId/students'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'name': name.trim(),
            'email': email.trim(),
            'student_no': studentNo.trim()
          }),
        )
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return int.tryParse((map['count'] ?? 0).toString()) ?? 0;
  }

  Future<void> clearSectionStudents(
      String workspaceId, String sectionId) async {
    final resp = await http
        .delete(_u('/workspaces/$workspaceId/sections/$sectionId/students'))
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
  }

  Future<void> deleteStudent(
      String workspaceId, String sectionId, String studentId) async {
    final resp = await http
        .delete(_u(
            '/workspaces/$workspaceId/sections/$sectionId/students/$studentId'))
        .timeout(AppConfig.shortTimeout);
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
  }

  Future<String> ask(String wid, String question,
      {List<Map<String, String>> history = const []}) async {
    final trimmedHistory =
        history.length > 20 ? history.sublist(history.length - 20) : history;
    final resp = await http
        .post(
          _u('/workspaces/$wid/ask'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'question': question, 'history': trimmedHistory}),
        )
        .timeout(AppConfig.standardTimeout);
    if (resp.statusCode == 504) throw Exception('Ask timed out. Try again.');
    if (resp.statusCode != 200) throw Exception(_extractDetail(resp));
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['answer'] ?? '').toString();
  }

  Future<Map<String, dynamic>> uploadStudentList({required File file}) async {
    try {
      final req = http.MultipartRequest('POST', _u('/students/upload'));
      final filePart = await http.MultipartFile.fromPath('file', file.path);
      req.files.add(filePart);
      final streamed = await req.send().timeout(AppConfig.uploadTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200)
        return Map<String, dynamic>.from(jsonDecode(response.body));
      return {
        "ok": false,
        "status": response.statusCode,
        "error": response.body
      };
    } catch (e) {
      return {"ok": false, "error": e.toString()};
    }
  }

  Future<QuizQuestion> editQuestionWithAI(
      QuizQuestion oldQuestion, String instruction) async {
    var response = await http.post(
      _u('/edit-question/'),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(
          {"question_data": oldQuestion.toJson(), "instruction": instruction}),
    );
    if (response.statusCode == 200) {
      var data = jsonDecode(response.body);
      return QuizQuestion.fromJson(data['updated_question']);
    }
    throw Exception("Failed to edit question");
  }

  // ===========================================================================
  // ── NEW Attendance & Facial Recognition Methods ────────────────────────────
  // ===========================================================================

  Future<Map<String, dynamic>> uploadCheck({
    required File videoFile,
    required int lectureNumber,
    required int workspaceId,
    required String sectionId,
  }) async {
    try {
      final req =
          http.MultipartRequest('POST', _u('/attendance/process-video'));

      req.fields['lecture_number'] = lectureNumber.toString();
      req.fields['workspace_id'] = workspaceId.toString();
      req.fields['section_id'] = sectionId;

      final videoPart =
          await http.MultipartFile.fromPath('video', videoFile.path);
      req.files.add(videoPart);

      final streamed = await req.send().timeout(
          const Duration(minutes: 5)); // Allow longer for video processing
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      }

      return {
        "ok": false,
        "status": response.statusCode,
        "error": response.body
      };
    } catch (e) {
      return {"ok": false, "error": e.toString()};
    }
  }

  Future<Map<String, dynamic>> previewAttendance({
    required int lectureNumber,
    required String videoId,
    required int workspaceId,
    required String sectionId,
  }) async {
    try {
      final res = await http.post(
        _u('/attendance/preview'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "lecture_number": lectureNumber,
          "video_id": videoId,
          "workspace_id": workspaceId,
          "section_id": sectionId,
        }),
      );

      if (res.statusCode == 200)
        return Map<String, dynamic>.from(jsonDecode(res.body));
      return {"ok": false, "status": res.statusCode, "error": res.body};
    } catch (e) {
      return {"ok": false, "error": e.toString()};
    }
  }

  Future<Map<String, dynamic>> confirmAttendance({
    required int lectureNumber,
    required int workspaceId,
    required String sectionId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final body = jsonEncode({
      "lecture_number": lectureNumber,
      "workspace_id": workspaceId,
      "section_id": sectionId,
      "rows": rows
          .map((r) => {
                "student_id": r["student_id"].toString(),
                "status": r["status"].toString(),
                "confidence": (r["confidence"] ?? "Unknown").toString(),
              })
          .toList(),
    });

    final response = await http.post(
      _u('/attendance/confirm'),
      headers: {"Content-Type": "application/json"},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
          "Confirm failed: ${response.statusCode} ${response.body}");
    }
    return jsonDecode(response.body);
  }

  Future<List<int>> exportAttendanceCsvFromDb({
    required int workspaceId,
    required String sectionId,
    int? lectureNumber,
  }) async {
    final queryParams = {
      'workspace_id': workspaceId.toString(),
      'section_id': sectionId,
    };
    if (lectureNumber != null)
      queryParams['lecture_number'] = lectureNumber.toString();

    final uri = Uri.parse('$_baseUrl/export-attendance')
        .replace(queryParameters: queryParams);
    final res = await http.get(uri);

    if (res.statusCode != 200)
      throw Exception("Export failed: ${res.statusCode}");
    return res.bodyBytes;
  }

  Future<Map<String, dynamic>> uploadEncoding({
    required String studentId,
    required List<File> images,
    bool override = false,
  }) async {
    final req = http.MultipartRequest('POST', _u('/encoding/upload'));
    req.fields['student_id'] = studentId;
    req.fields['override'] = override.toString();

    for (var img in images) {
      req.files.add(await http.MultipartFile.fromPath('files', img.path));
    }

    final streamed = await req.send().timeout(AppConfig.uploadTimeout);
    final res = await http.Response.fromStream(streamed);
    final data = jsonDecode(res.body);

    if (res.statusCode != 200)
      return {"ok": false, "message": data["detail"] ?? "Unknown error"};
    return data;
  }

  Future<List<dynamic>> getEncodingStudents() async {
    final res = await http.get(_u('/encoding/students'));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception("Failed to load encoding students");
  }

  Future<int?> getLastLecture(
      {required int workspaceId, required String sectionId}) async {
    final uri = Uri.parse(
        '$_baseUrl/attendance/last-lecture?workspace_id=$workspaceId&section_id=$sectionId');
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception("Failed to fetch last lecture");
    final data = jsonDecode(res.body);
    if (data['ok'] == true) return data['last_lecture'];
    return null;
  }

  Future<List<int>> getAvailableLectures(
      {required int workspaceId, required String sectionId}) async {
    final uri = Uri.parse(
        '$_baseUrl/attendance/available-lectures?workspace_id=$workspaceId&section_id=$sectionId');
    final res = await http.get(uri);
    if (res.statusCode != 200) return []; // Graceful failure if none exist
    final data = jsonDecode(res.body);
    return List<int>.from(data['lectures'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getStudentsForSection(
      {required int workspaceId, required String sectionId}) async {
    final uri = Uri.parse(
        '$_baseUrl/workspaces/$workspaceId/sections/$sectionId/students');
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception("Failed to load students");

    final data = jsonDecode(res.body);
    List<dynamic> rawStudents = data['students'] ?? [];

    return rawStudents
        .map((s) => {
              "student_id": s["student_no"]?.toString() ??
                  s["student_id"]?.toString() ??
                  "",
              "name": s["name"] ?? "Unknown",
              "email": s["email"] ?? ""
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAttendanceForLecture({
    required int workspaceId,
    required String sectionId,
    required int lectureNumber,
  }) async {
    final uri = Uri.parse(
        '$_baseUrl/attendance/lecture?workspace_id=$workspaceId&section_id=$sectionId&lecture_number=$lectureNumber');
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception("Failed to load attendance");
    final data = jsonDecode(res.body);
    return List<Map<String, dynamic>>.from(data['rows'] ?? []);
  }

  // ==========================================
  // Generate Warning Report (.docx)
  // ==========================================
  Future<List<int>> downloadWarningReport({
    required int workspaceId,
    required String sectionId,
    required String studentId,
    required int absences,
  }) async {
    final url = Uri.parse('$_baseUrl/attendance/generate-warning-report');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "workspace_id": workspaceId,
        "section_id": sectionId,
        "student_id": studentId,
        "absences": absences,
      }),
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to generate report: ${response.body}');
    }
  }
}
