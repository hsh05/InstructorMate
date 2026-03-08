import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class SignupController {
  final TextEditingController name, email, password, confirmPassword;

  SignupController(this.name, this.email, this.password, this.confirmPassword);

  Future<bool> signup(String role) async {
    final apiUrl = 'http://10.0.2.2:8000/auth/signup'; // backend URL for Android emulator

    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.text.trim(),
          'password': password.text.trim(),
          'full_name': name.text.trim(),
          // optionally send 'role' if backend supports it
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Signup successful: ${response.body}');
        return true;
      } else {
        debugPrint('❌ Signup failed: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Signup error: $e');
      return false;
    }
  }
}