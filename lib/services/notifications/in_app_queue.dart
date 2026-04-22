// lib/services/notifications/in_app_queue.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'mobile_toast_service.dart';

class InAppQueue {
  static const _storage = FlutterSecureStorage();
  static const _key = 'in_app_notif_queue';
  static Timer? _timer;

  // Starts the background clock
  static void startTimer() {
    _timer?.cancel();
    // Check the clock every 20 seconds silently
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _checkQueue());
    _checkQueue(); // Initial check on boot
  }

  // Adds a notification to the desktop queue
  static Future<void> add({
    required int id,
    required String title,
    required String body,
    required DateTime fireTime,
  }) async {
    final existingStr = await _storage.read(key: _key);
    List<dynamic> queue = [];
    if (existingStr != null) {
      try { queue = jsonDecode(existingStr); } catch (_) {}
    }
    
    // Remove old entry with same id if it exists
    queue.removeWhere((q) => q['id'] == id);

    queue.add({
      'id': id,
      'title': title,
      'body': body,
      'fireTime': fireTime.toIso8601String(),
    });

    await _storage.write(key: _key, value: jsonEncode(queue));
  }

  // Cancels a specific notification
  static Future<void> cancel(int id) async {
    final existingStr = await _storage.read(key: _key);
    if (existingStr == null) return;
    List<dynamic> queue = [];
    try { queue = jsonDecode(existingStr); } catch (_) { return; }
    
    queue.removeWhere((q) => q['id'] == id);
    await _storage.write(key: _key, value: jsonEncode(queue));
  }

  // Clears the whole queue
  static Future<void> cancelAll() async {
    await _storage.delete(key: _key);
  }

  // The engine that fires the notification
  static Future<void> _checkQueue() async {
    final existingStr = await _storage.read(key: _key);
    if (existingStr == null) return;

    List<dynamic> queue = [];
    try { queue = jsonDecode(existingStr); } catch (_) { return; }

    final now = DateTime.now();
    bool changed = false;
    List<dynamic> toKeep = [];

    for (var item in queue) {
      final fireTime = DateTime.tryParse(item['fireTime'].toString());
      
      if (fireTime != null) {
        if (now.isAfter(fireTime)) {
          // Fire it! (As long as it's not super stale, e.g. missed by > 1 hour)
          if (now.difference(fireTime).inMinutes < 60) {
            MobileToastService.show(title: item['title'], body: item['body']);
          }
          changed = true; // Mark to be removed from the queue
        } else {
          toKeep.add(item); // Keep for the future
        }
      }
    }

    if (changed) {
      await _storage.write(key: _key, value: jsonEncode(toKeep));
    }
  }
}