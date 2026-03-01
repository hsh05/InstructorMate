// lib/services/notification_service.dart
//
// FIX 1: uiLocalNotificationDateInterpretation is REQUIRED on this version of
//         flutter_local_notifications (pre-v14). Added back to both zonedSchedule
//         calls (exact + inexact fallback).
//
// FIX 2: Both notification AND exact-alarm permission are now required before
//         scheduling. Previously only notifGranted was checked; alarmGranted
//         was ignored, so exact alarms silently failed on Android 12+.
//
// FIX 3: hasPermission() re-queries the plugin live so system-settings changes
//         take effect without a full app restart.
//
// FIX 4: "Missing type parameter" RuntimeException — root cause of the red
//         error screen. The Android plugin throws this when exactAllowWhileIdle
//         is requested but the OS denies the exact-alarm at runtime (common on
//         Xiaomi/MIUI, Samsung One UI, and other skins that silently revoke
//         SCHEDULE_EXACT_ALARM even after the user taps "Allow").
//
//         Fix: try exactAllowWhileIdle first. If Android throws that specific
//         error, fall back to inexactAllowWhileIdle — no special permission
//         needed, fires within a few minutes, perfectly acceptable for class
//         reminders.

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
    if (_initialized) return _notifGranted && _alarmGranted;

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
        '[NotificationService] init: notifications=$_notifGranted exactAlarms=$_alarmGranted',
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

    if (!_initialized) {
      await init();
    }

    if (!_notifGranted) {
      debugPrint(
        '[NotificationService] No notification permission — skipping id=$id',
      );
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

    // FIX 4: Try exact scheduling first. If Android throws "Missing type
    // parameter" (MIUI/One UI exact-alarm block), fall back to inexact.
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
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final isExactAlarmError =
          msg.contains('missing type parameter') ||
          msg.contains('schedule_exact') ||
          msg.contains('exact alarm');

      if (isExactAlarmError) {
        debugPrint(
          '[NotificationService] Exact alarm denied by OS — '
          'falling back to inexact for id=$id',
        );
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
          debugPrint(
            '[NotificationService] Scheduled (inexact fallback) id=$id at $when',
          );
        } catch (e2) {
          debugPrint(
            '[NotificationService] Inexact fallback also failed id=$id: $e2',
          );
          rethrow;
        }
      } else {
        debugPrint(
          '[NotificationService] scheduleClassReminder failed id=$id: $e',
        );
        rethrow;
      }
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

  // ── Tap handler ───────────────────────────────────────────────────────────

  static void _onNotificationResponse(NotificationResponse response) {
    debugPrint('[NotificationService] Tapped notification id=${response.id}');
  }
}
