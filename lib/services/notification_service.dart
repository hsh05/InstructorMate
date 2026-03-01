// lib/services/notification_service.dart
//
// Compatible with flutter_local_notifications v9 through v17.
// uiLocalNotificationDateInterpretation is included for older versions
// and is safely ignored by v17+.

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

  bool get _supported => !kIsWeb;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<bool> init() async {
    if (!_supported) return false;
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

    // Wipe stale SharedPreferences from old builds — prevents
    // "Missing type parameter" deserialization crash on next schedule call.
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
    if (!_initialized) await init();

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
    if (!_initialized) await init();

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
    debugPrint('[NotificationService] Tapped notification id=${response.id}');
  }
}
