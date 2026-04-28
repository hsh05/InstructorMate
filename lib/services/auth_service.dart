import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final String _baseUrl = dotenv.env['BACKEND_URL'] ?? 'https://fallback-url.com';
const _storage = FlutterSecureStorage();

class AuthService {

  // ── Google Sign-In Setup ─────────────────────────────────────
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static Future<void> initialize() async {
    await _googleSignIn.initialize(
      serverClientId: 'YOUR_GOOGLE_CLIENT_ID',
    );
  }

  // ── Token Storage ────────────────────────────────────────────

  static Future<void> _saveTokens(String access, String refresh) async {
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  static Future<String?> getAccessToken() {
    return _storage.read(key: 'access_token');
  }

  static Future<String?> getRefreshToken() {
    return _storage.read(key: 'refresh_token');
  }

  static Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  // ── Email / Password Auth ────────────────────────────────────

  static Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    String? fullName,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
      }),
    );

    final data = jsonDecode(res.body);

    if (res.statusCode == 200) {
      await _saveTokens(data['access_token'], data['refresh_token']);
    }

    return {'status': res.statusCode, ...data};
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final data = jsonDecode(res.body);

    if (res.statusCode == 200) {
      await _saveTokens(data['access_token'], data['refresh_token']);
    }

    return {'status': res.statusCode, ...data};
  }

  // ── Google OAuth ─────────────────────────────────────────────

  static Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.authenticate();

      final auth = account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        throw Exception('No Google ID Token received');
      }

      final res = await http.post(
        Uri.parse('$_baseUrl/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id_token': idToken}),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        await _saveTokens(data['access_token'], data['refresh_token']);
      }

      return {'status': res.statusCode, ...data};

    } catch (e) {
      return {'status': 500, 'detail': e.toString()};
    }
  }

  // ── Token Refresh ────────────────────────────────────────────

  static Future<bool> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();

    if (refreshToken == null) return false;

    final res = await http.post(
      Uri.parse('$_baseUrl/auth/refresh'),
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

  // ── Authenticated Requests ───────────────────────────────────

  static Future<http.Response> authGet(String path) async {
    String? token = await getAccessToken();

    var res = await http.get(
      Uri.parse('$_baseUrl$path'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (res.statusCode == 401) {
      final refreshed = await refreshAccessToken();

      if (refreshed) {
        token = await getAccessToken();

        res = await http.get(
          Uri.parse('$_baseUrl$path'),
          headers: {'Authorization': 'Bearer $token'},
        );
      }
    }

    return res;
  }

  // ── User Profile ─────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getMe() async {
    final res = await authGet('/auth/me');

    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }

    return null;
  }

  // ── Logout ───────────────────────────────────────────────────

  static Future<void> logout() async {
    final refreshToken = await getRefreshToken();

    if (refreshToken != null) {
      await http.post(
        Uri.parse('$_baseUrl/auth/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
    }

    await clearTokens();
    await _googleSignIn.signOut();
  }
}