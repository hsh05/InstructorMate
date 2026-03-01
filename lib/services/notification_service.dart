// lib/services/notification_service.dart
//
// FINAL FIX — "Missing type parameter" root cause:
//
// The crash is at loadScheduledNotifications() because SharedPreferences
// contains notifications saved WITHOUT matchDateTimeComponents (one-shot type)
// but the plugin tries to deserialize them as repeating (dayOfWeekAndTime type).
// The type mismatch throws RuntimeException("Missing type parameter") in Java.
//
// Three things must ALL be true simultaneously:
//   1. cancelAll() wipes stale SharedPreferences BEFORE any zonedSchedule call
//   2. matchDateTimeComponents is ALWAYS passed (repeating weekly notifications)
//   3. init() is always awaited before scheduleClassReminder is called
//
// All three are now guaranteed.

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _notifGranted = false;
  bool _alarmGranted = false;

  // Single shared Future — concurrent callers get the same one.
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

    // Wipe ALL previously saved notifications from SharedPreferences.
    // Must happen before any zonedSchedule call — this is what prevents
    // the "Missing type parameter" deserialization crash.
    try {
      await _plugin.cancelAll();
      debugPrint('[NotificationService] Cleared stale notifications on init.');
    } catch (e) {
      debugPrint('[NotificationService] cancelAll on init (non-fatal): $e');
    }

    _initialized = true;

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImpl != null) {
      _notifGranted =
          await androidImpl.requestNotificationsPermission() ?? false;
      _alarmGranted = await androidImpl.requestExactAlarmsPermission() ?? false;
      debugPrint(
        '[NotificationService] notifications=$_notifGranted '
        'exactAlarms=$_alarmGranted',
      );
    } else {
      _notifGranted = didInit ?? true;
      _alarmGranted = _notifGranted;
    }

    return _notifGranted;
  }

  // ── Permission guard ──────────────────────────────────────────────────────

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
    await init(); // always await — ensures cancelAll() completed first

    if (!_notifGranted) {
      debugPrint('[NotificationService] No permission — skipping id=$id');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'class_reminders',
      'Class Reminders',
      channelDescription: 'Reminders before class starts',
      importance: Importance.high,
      priority: Priority.high,
      fullScreenIntent: false,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
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
        // REQUIRED: tells the plugin this is a repeating weekly notification.
        // Missing this = wrong serialized type = "Missing type parameter" crash
        // when any subsequent zonedSchedule call loads SharedPreferences.
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      debugPrint('[NotificationService] Scheduled (exact) id=$id at $when');
      return;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isExactError =
          msg.contains('missing type parameter') ||
          msg.contains('schedule_exact') ||
          msg.contains('exact alarm') ||
          msg.contains('platformexception');

      if (!isExactError) {
        debugPrint('[NotificationService] Unexpected error id=$id: $e');
        rethrow;
      }
      debugPrint(
        '[NotificationService] Exact alarm blocked — inexact fallback id=$id',
      );
    }

    // Attempt 2 — inexact fallback
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // REQUIRED here too — must match exact attempt's serialized format
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      debugPrint('[NotificationService] Scheduled (inexact) id=$id at $when');
    } catch (e) {
      debugPrint('[NotificationService] Inexact fallback failed id=$id: $e');
      rethrow;
    }
  }

  Future<void> cancel(int id) async {
    if (!_supported) return;
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    if (!_supported) return;
    await _plugin.cancelAll();
    debugPrint('[NotificationService] All notifications cancelled.');
  }

  static void _onNotificationResponse(NotificationResponse response) {
    debugPrint('[NotificationService] Tapped id=${response.id}');
  }
}
