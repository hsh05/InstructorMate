// lib/config/app_config.dart // file path comment

class AppConfig { // central place for app constants/config
  static const String baseUrl = String.fromEnvironment( // read compile-time env var
    'BASE_URL', // ✅ correct key name (Netlify can inject later if needed)
    defaultValue: 'http://127.0.0.1:8000', // local dev fallback
  ); // end baseUrl

  static const Duration httpTimeout = Duration(minutes: 5); // ✅ web-safe
// backend conversion can take time
} // end class
