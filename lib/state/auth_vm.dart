// lib/state/auth_vm.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class AuthViewModel {
  static const _storage = FlutterSecureStorage();

  // ── Login ────────────────────────────────────────────────────────────
  Future<String?> login({required String email, required String password}) async {
    try {
      final response = await http.post(
        AppConfig.loginUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password.trim(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('✅ Login successful');

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

  // ── Signup ───────────────────────────────────────────────────────────
  Future<bool> signup({
    required String name, 
    required String email, 
    required String password, 
    String role = 'Instructor'
  }) async {
    try {
      final response = await http.post(
        AppConfig.signupUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password.trim(),
          'full_name': name.trim(),
          'role': role,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ Signup successful');
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