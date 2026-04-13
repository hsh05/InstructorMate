// lib/services/auth_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';
import '../models/instructor_model.dart';

const _storage = FlutterSecureStorage();

class AuthService {
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static Future<void> initialize() async {
    await _googleSignIn.initialize(serverClientId: 'YOUR_GOOGLE_CLIENT_ID');
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
}