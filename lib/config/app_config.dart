// lib/app/app_config.dart
//
// Single source of truth for base URL and timeouts.
// Previously defined here but never used — main.dart hardcoded the URL
// and api_client.dart hardcoded timeouts. Both now read from here.

class AppConfig {
  //https://instructormate1.onrender.com
  // FIX: Change this to your server IP/hostname before deploying.
  static const String baseUrl = "https://instructormate1.onrender.com";

  // Per-request timeouts (formerly hardcoded inline in api_client.dart)
  static const Duration shortTimeout = Duration(seconds: 40);
  static const Duration standardTimeout = Duration(seconds: 450);
  static const Duration uploadTimeout = Duration(seconds: 300);
  static const Duration reuploadTimeout = Duration(seconds: 120);
}
