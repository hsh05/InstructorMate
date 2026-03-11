// lib/config/api_config.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  // Base URLs
  static String get baseUrl => dotenv.env['BACKEND_URL'] ?? 'http://10.0.2.2:8000';
  static String get databaseUrl => dotenv.env['DATABASE_URL'] ?? '';
  static String get openAIApiKey => dotenv.env['OPENAI_API_KEY'] ?? '';

  // Auth endpoints
  static Uri get loginUri => Uri.parse('$baseUrl/auth/login');
  static Uri get signupUri => Uri.parse('$baseUrl/auth/signup');
  static Uri get refreshTokenUri => Uri.parse('$baseUrl/auth/refresh');
  static Uri get logoutUri => Uri.parse('$baseUrl/auth/logout');
  static Uri get googleAuthUri => Uri.parse('$baseUrl/auth/google');
  static Uri get meUri => Uri.parse('$baseUrl/auth/me');

  // Profile endpoints
  static Uri getProfileUri(int userId) => Uri.parse('$baseUrl/profile/$userId');

}