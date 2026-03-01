// lib/services/notification_service.dart

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _notifGranted = false;
  bool _alarmGranted = false;

  // Cached Future — concurrent callers all await the same one.
  Future<bool>? _initFuture;

  bool get _supported => !kIsWeb;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<bool> init() {
    if (!_supported) return Future.value(false);
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<bool> _doInit() async {
    if (_initialized) return _notifGranted;

    // Step 1 — Delete plugin SharedPrefs keys directly BEFORE initialize().
    // plugin.cancelAll() internally calls loadScheduledNotifications() which
    // can itself throw "Missing type parameter" on corrupt data, making it
    // useless as a cleanup tool. Deleting the keys directly via the
    // shared_preferences package bypasses the plugin's broken deserializer.
    try {
      final prefs = await SharedPreferences.getInstance();
      final toRemove = prefs
          .getKeys()
          .where(
            (k) =>
                k.startsWith('flutter_local_notifications') ||
                k == 'scheduled_notifications' ||
                k.startsWith('scheduled_notification'),
          )
          .toList();
      for (final key in toRemove) {
        await prefs.remove(key);
      }
      debugPrint('[NS] Cleared ${toRemove.length} plugin SharedPrefs keys.');
    } catch (e) {
      debugPrint('[NS] SharedPrefs clear failed (non-fatal): $e');
    }

    // Step 2 — Initialize the plugin on a now-clean SharedPrefs.
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    final didInit = await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Step 3 — cancelAll() as extra safety net (now safe since keys are gone).
    try {
      await _plugin.cancelAll();
      debugPrint('[NS] cancelAll() completed.');
    } catch (e) {
      debugPrint('[NS] cancelAll() failed (non-fatal): $e');
    }

    _initialized = true;

    // Step 4 — Request permissions.
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImpl != null) {
      _notifGranted =
          await androidImpl.requestNotificationsPermission() ?? false;
      _alarmGranted = await androidImpl.requestExactAlarmsPermission() ?? false;
      debugPrint('[NS] granted=$_notifGranted exactAlarm=$_alarmGranted');
    } else {
      _notifGranted = didInit ?? true;
      _alarmGranted = _notifGranted;
    }

    return _notifGranted;
  }

  // ── Permission check ──────────────────────────────────────────────────────

  Future<bool> hasPermission() async {
    if (!_supported) return false;
    await init();

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImpl != null) {
      _notifGranted =
          await androidImpl.areNotificationsEnabled() ?? _notifGranted;
      _alarmGranted =
          await androidImpl.canScheduleExactNotifications() ?? _alarmGranted;
      return _notifGranted;
    }

    return _notifGranted;
  }

  // ── Schedule ──────────────────────────────────────────────────────────────

  Future<void> scheduleClassReminder({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
  }) async {
    if (!_supported) return;
    await init();

    if (!_notifGranted) {
      debugPrint('[NS] No permission — skipping id=$id');
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_reminders',
        'Class Reminders',
        channelDescription: 'Reminders before class starts',
        importance: Importance.high,
        priority: Priority.high,
        fullScreenIntent: false,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _scheduleWithFallback(id, title, body, when, details);
  }

  Future<void> _scheduleWithFallback(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    NotificationDetails details,
  ) async {
    // Attempt 1 — exact alarm
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      debugPrint('[NS] Scheduled exact id=$id at $when');
      return;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isExactError =
          msg.contains('missing type parameter') ||
          msg.contains('schedule_exact') ||
          msg.contains('exact alarm') ||
          msg.contains('platformexception');
      if (!isExactError) {
        debugPrint('[NS] Unexpected error id=$id: $e');
        rethrow;
      }
      debugPrint('[NS] Exact blocked, trying inexact id=$id');
    }

    // Attempt 2 — inexact fallback
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
    debugPrint('[NS] Scheduled inexact id=$id at $when');
  }

  Future<void> cancel(int id) async {
    if (!_supported) return;
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    if (!_supported) return;
    await _plugin.cancelAll();
    debugPrint('[NS] All cancelled.');
  }

  static void _onNotificationResponse(NotificationResponse response) {
    debugPrint('[NS] Tapped id=${response.id}');
  }
}
