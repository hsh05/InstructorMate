import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LoginController {
  final TextEditingController email;
  final TextEditingController password;

  LoginController(this.email, this.password);

  Future<bool> login() async {
    final apiUrl = 'http://10.0.2.2:8000/auth/login'; // Change to your backend URL if needed
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.text.trim(),
          'password': password.text.trim(),
        }),
      );

      if (response.statusCode == 200) {
        // Optionally parse response JSON for tokens or user info
        debugPrint('✅ Login successful: ${response.body}');
        return true;
      } else {
        debugPrint('❌ Login failed: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Login error: $e');
      return false;
    }
  }
}