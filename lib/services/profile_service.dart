import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:instructor_mate/models/instructor_profile.dart';
import 'package:instructor_mate/config/apiConfig.dart';

class ProfileService {
  static Future<InstructorProfile> getProfile(String userId) async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/profile/$userId'),
    );

    if (response.statusCode == 200) {
      return InstructorProfile.fromJson(jsonDecode(response.body));
    }

    throw Exception('Failed to load profile (${response.statusCode})');
  }

  static Future<InstructorProfile> updateProfile(
      String userId, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('${ApiConfig.baseUrl}/profile/$userId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return InstructorProfile.fromJson(jsonDecode(response.body));
    }

    throw Exception('Failed to update profile (${response.statusCode})');
  }
}