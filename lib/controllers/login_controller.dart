import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:instructor_mate/config/apiConfig.dart';

class LoginController {
  final TextEditingController email;
  final TextEditingController password;

  LoginController(this.email, this.password);

  static const _storage = FlutterSecureStorage();

  // Returns the userId (UUID string) on success, null on failure
  Future<String?> login() async {
    try {
      final response = await http.post(
        ApiConfig.loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.text.trim(),
          'password': password.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Login successful: ${response.body}');

        // Store tokens securely for future authenticated requests
        await _storage.write(key: 'access_token', value: data['access_token']);
        await _storage.write(key: 'refresh_token', value: data['refresh_token']);
        await _storage.write(key: 'user_id', value: data['user_id']);

        return data['user_id'] as String?;
      } else {
        debugPrint('❌ Login failed: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Login error: $e');
      return null;
    }
  }
}