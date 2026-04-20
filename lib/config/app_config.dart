// lib/config/app_config.dart

import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // Base URLs
  static String get baseUrl => dotenv.env['API_URL'] ?? 'https://instructormate.onrender.com';
  static String get databaseUrl => dotenv.env['DATABASE_URL'] ?? '';

  // Timeouts
  static const Duration shortTimeout = Duration(seconds: 40);
  static const Duration standardTimeout = Duration(seconds: 450);
  static const Duration uploadTimeout = Duration(seconds: 300);
  static const Duration reuploadTimeout = Duration(seconds: 120);

  // Auth URIs
  static Uri get loginUri => Uri.parse('$baseUrl/auth/login');
  static Uri get signupUri => Uri.parse('$baseUrl/auth/signup');
  static Uri get refreshTokenUri => Uri.parse('$baseUrl/auth/refresh');
  static Uri get logoutUri => Uri.parse('$baseUrl/auth/logout');
  static Uri get googleAuthUri => Uri.parse('$baseUrl/auth/google');
  
  // Profile URIs
  static Uri get meUri => Uri.parse('$baseUrl/profile/me');
  static Uri getProfileUri(String userId) => Uri.parse('$baseUrl/profile/$userId');
}