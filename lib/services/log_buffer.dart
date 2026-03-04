// lib/services/log_buffer.dart
//
// Captures debugPrint-style log lines to an in-memory buffer AND a file
// in the app's documents directory. Works in release APK builds where
// the terminal is unavailable.
//
// Usage:
//   AppLog.d('[NS] Scheduled id=123 at ...');   // replaces debugPrint
//   AppLog.e('[Toast] CRASH: $e\n$stack');       // error level
//
// View logs: tap the bug icon in the AppBar on the home screen.

import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:path_provider/path_provider.dart';

class AppLog {
  AppLog._();

  // ── In-memory ring buffer — last 500 lines ────────────────────────────────
  static final Queue<String> _buffer = Queue();
  static const int _maxLines = 500;

  // ── File handle — opened once on first write ──────────────────────────────
  static File? _file;
  static bool _fileReady = false;
  static bool _fileAttempted = false; // only try once — never block the app

  static Future<void> _ensureFile() async {
    if (_fileReady || _fileAttempted || kIsWeb) return;
    _fileAttempted = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _file = File('${dir.path}/instructormate_debug.log');
      // Rotate: if file > 200 KB, wipe it
      if (await _file!.exists()) {
        final size = await _file!.length();
        if (size > 200 * 1024) await _file!.writeAsString('');
      }
      _fileReady = true;
    } catch (e) {
      debugPrint('[AppLog] Could not open log file: $e');
    }
  }

  /// Log a line. Call this instead of debugPrint for anything you want
  /// to see later in the log viewer.
  static void d(String line) {
    final ts = DateTime.now().toIso8601String().substring(
      11,
      23,
    ); // HH:mm:ss.mmm
    final full = '[$ts] $line';
    debugPrint(full); // still goes to terminal in debug mode
    _buffer.addLast(full);
    if (_buffer.length > _maxLines) _buffer.removeFirst();
    _writeToFile(full);
  }

  /// Error level — same as d() but prefixed with !!!
  static void e(String line) => d('!!! $line');

  static void _writeToFile(String line) {
    if (kIsWeb) return;
    _ensureFile().then((_) {
      try {
        _file?.writeAsStringSync('$line\n', mode: FileMode.append);
      } catch (_) {}
    });
  }

  /// All buffered lines as a single string (newest at bottom).
  static String get all => _buffer.join('\n');

  /// Clear buffer and file.
  static Future<void> clear() async {
    _buffer.clear();
    try {
      await _file?.writeAsString('');
    } catch (_) {}
  }

  /// Path to the log file (for sharing).
  static Future<String?> get filePath async {
    await _ensureFile();
    return _file?.path;
  }
}
