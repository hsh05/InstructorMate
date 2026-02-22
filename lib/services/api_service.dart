import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/course_model.dart';

class ApiService {
  // Windows desktop uses localhost. Android Emulators require 10.0.2.2.
  static final String _baseUrl = "https://instructormateassessment.onrender.com/";

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
}