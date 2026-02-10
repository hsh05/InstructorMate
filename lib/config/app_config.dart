// lib/config/app_config.dart

/// App-wide configuration (environment switching, URLs, flags)

class AppConfig {
  static const String baseUrl = String.fromEnvironment(
    'https://instructormate1.onrender.com',
    defaultValue: 'http://127.0.0.1:8000', // local dev fallback
  );
}
