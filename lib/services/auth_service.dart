// lib/services/auth_service.dart

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';
import '../models/instructor_model.dart';

const _storage = FlutterSecureStorage();

class AuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<void> initialize() async {
    // 👉 THE FIX: Skip Google Sign-In on Windows/Mac/Linux
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      debugPrint("⚠️ Skipping Google Sign-In initialization on Desktop.");
      return; // Stop here, don't crash the app!
    }

    // Your existing Google initialization code goes here
    await _googleSignIn.initialize(); 
  }

  // ── Tokens ──────────────────────────────────────────────────────────────────
  static Future<void> _saveTokens(String access, String refresh) async {
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  static Future<String?> getAccessToken() => _storage.read(key: 'access_token');
  static Future<String?> getRefreshToken() => _storage.read(key: 'refresh_token');

  static Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  static Future<bool> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return false;

    final res = await http.post(
      AppConfig.refreshTokenUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await _saveTokens(data['access_token'], data['refresh_token']);
      return true;
    }
    return false;
  }

  // ── Authenticated Requests ──────────────────────────────────────────────────
  static Future<http.Response> authGet(Uri uri) async {
    String? token = await getAccessToken();
    var res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});

    if (res.statusCode == 401) {
      if (await refreshAccessToken()) {
        token = await getAccessToken();
        res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      }
    }
    return res;
  }

  // ── Profile (Merged from ProfileService) ────────────────────────────────────
  static Future<Instructor?> getMe() async {
    final res = await authGet(AppConfig.meUri);
    if (res.statusCode == 200) return Instructor.fromJson(jsonDecode(res.body));
    return null;
  }

  static Future<Instructor> getProfile(String userId) async {
    final res = await authGet(AppConfig.getProfileUri(userId));
    if (res.statusCode == 200) return Instructor.fromJson(jsonDecode(res.body));
    throw Exception('Failed to load profile (${res.statusCode})');
  }

  static Future<Instructor> updateProfile(String userId, Map<String, dynamic> data) async {
    String? token = await getAccessToken();
    final res = await http.put(
      AppConfig.getProfileUri(userId),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token'
      },
      body: jsonEncode(data),
    );
    if (res.statusCode == 200) return Instructor.fromJson(jsonDecode(res.body));
    throw Exception('Failed to update profile (${res.statusCode})');
  }

  // ── Logout ──────────────────────────────────────────────────────────────────
  static Future<void> logout() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken != null) {
      await http.post(
        AppConfig.logoutUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
    }
    await clearTokens();
    await _googleSignIn.signOut();
  }

  // ─── SIGNUP ─────────────────────────────────────────────────────────────────
  static Future<bool> signUp(String email, String password, String name) async {
    try {
      debugPrint("🔍 Trying to hit EXACT URL: ${AppConfig.signupUri.toString()}");

      final res = await http.post(
        AppConfig.signupUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password.trim(),
          'full_name': name.trim(),
          'role': 'Instructor' // 👉 THE FIX: We must send the role!
        }),
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode == 200 || res.statusCode == 201) {
        return true;
      } else {
        // This prints the EXACT reason FastAPI rejected it!
        debugPrint("Signup failed: ${res.body}"); 
        return false;
      }
    } catch (e) {
      debugPrint("Service Signup Error: $e");
      return false;
    }
  }

  // ─── LOGIN ──────────────────────────────────────────────────────────────────
  static Future<bool> login(String email, String password) async {
    try {
      final res = await http.post(
        AppConfig.loginUri,
        // 👉 THE FIX: Changed back to JSON format to match your backend!
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(), 
          'password': password.trim()
        }),
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // Save the tokens and user ID
        await _storage.write(key: 'user_id', value: data['user_id'].toString()); 
        await _saveTokens(data['access_token'], data['refresh_token']);
        return true;
      } else {
        // This will print to your terminal if it fails again!
        debugPrint("Login failed: Status ${res.statusCode} - ${res.body}");
        return false;
      }
    } catch (e) {
      debugPrint("Service Login Error: $e");
      return false;
    }
  }
}