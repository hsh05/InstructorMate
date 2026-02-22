import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/course_model.dart';
import '../models/question_model.dart';
import '../models/config_model.dart';

class ApiService {
  // Windows desktop uses localhost. Android Emulators require 10.0.2.2.
  static final String _baseUrl = "https://instructormate.onrender.com";

  Future<List<Course>> fetchCourses() async {
    var response = await http.get(Uri.parse('$_baseUrl/courses/'));
    if (response.statusCode == 200) {
      List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.map((j) => Course.fromJson(j)).toList();
    } else {
      throw Exception("Failed to load courses");
    }
  }

  Future<void> uploadMaterial(int courseId, File file, String type) async {
    var uri = Uri.parse('$_baseUrl/courses/$courseId/materials/');
    
    // Create a Multipart request for file uploading
    var request = http.MultipartRequest('POST', uri);
    
    // 1. Add the text field data (syllabus or slides)
    request.fields['material_type'] = type;
    
    // 2. Attach the physical file
    var multipartFile = await http.MultipartFile.fromPath('file', file.path);
    request.files.add(multipartFile);
    
    // 3. Send it to the Python server
    var response = await request.send();
    if (response.statusCode != 200) {
      var responseBody = await response.stream.bytesToString();
      throw Exception("Upload failed: $responseBody");
    }
  }

  // NEW: Added the List<QuestionTypeConfig> configs parameter
  Future<List<QuizQuestion>> generateDirectlyFromFile(File file, List<QuestionTypeConfig> configs) async {
    var request = http.MultipartRequest(
      'POST', 
      Uri.parse('$_baseUrl/generate-direct')
    );
    
    // 1. Attach the physical file
    request.files.add(
      await http.MultipartFile.fromPath('file', file.path)
    );

    // 2. Package the configurations into a JSON string
    List<Map<String, dynamic>> configList = configs.map((c) => {
      'type': c.name,
      'count': c.count,
      'difficulty': c.difficulty,
      'topic': c.topicController.text, // Grabs any specific focus instructions
    }).toList();
    
    // 3. Attach the JSON string as a form field named 'configs'
    request.fields['configs'] = jsonEncode(configList);

    var response = await request.send();
    var responseData = await http.Response.fromStream(response);

    if (response.statusCode == 200) {
      final decodedData = jsonDecode(responseData.body);
      List<dynamic> questionsList = decodedData['questions'] ?? decodedData;
      return questionsList.map((q) => QuizQuestion.fromJson(q)).toList();
    } else {
      final errorData = jsonDecode(responseData.body);
      throw Exception(errorData['detail']?.toString() ?? 'Generation failed');
    }
  }
}