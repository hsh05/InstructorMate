// lib/config/app_config.dart

/// App-wide configuration (environment switching, URLs, flags)
class AppConfig {
  // 🔁 Switch between local backend and production (Render)
  static const bool useLocalBackend = true;

  // 🌐 Backend base URL
  static const String baseUrl = useLocalBackend
      ? "http://127.0.0.1:8000"
      : "https://instructormate1.onrender.com";
}
