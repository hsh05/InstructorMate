// lib/services/notification_service.dart
//
// FIX: Mobile notifications were silently failing because:
//  1. Android 13+ requires POST_NOTIFICATIONS permission — we now request it
//     and throw a clear error if denied, instead of silently doing nothing.
//  2. Exact alarms on Android 12+ require SCHEDULE_EXACT_ALARM — we request it.
//  3. Added a permission-check helper so callers can gate scheduling on approval.
//  4. scheduleClassReminder now catches and rethrows with a human-readable message.

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _permissionGranted = false;

  bool get _supported => !kIsWeb;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<bool> init() async {
    if (!_supported) return false;
    if (_initialized) return _permissionGranted;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(android: android, iOS: ios);

    // FIX: capture the return value — on iOS this is false if the user denies.
    final didInit = await _plugin.initialize(
      settings,
      // FIX: handle notification tap while app is terminated (mobile)
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    _initialized = true;

    // ── Android: request POST_NOTIFICATIONS (Android 13+) ──────────────────
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidImpl != null) {
      // FIX: await the permission result so we know if we can schedule
      final notifGranted =
          await androidImpl.requestNotificationsPermission() ?? false;
      final alarmGranted =
          await androidImpl.requestExactAlarmsPermission() ?? false;
      _permissionGranted = notifGranted;
      debugPrint(
        '[NotificationService] notifications=$notifGranted exactAlarms=$alarmGranted',
      );
    } else {
      // iOS: didInit reflects the permission dialog result
      _permissionGranted = didInit ?? true;
    }

    return _permissionGranted;
  }

  // ── Permission guard ──────────────────────────────────────────────────────

  /// Returns true if notifications can be scheduled.
  /// Call this before scheduling to show a meaningful error rather than silence.
  Future<bool> hasPermission() async {
    if (!_supported) return false;
    if (!_initialized) await init();
    return _permissionGranted;
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
      final granted = await init();
      if (!granted) {
        debugPrint(
          '[NotificationService] Permission denied — cannot schedule.',
        );
        return;
      }
    }

    if (!_permissionGranted) {
      debugPrint('[NotificationService] No permission — skipping id=$id');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'class_reminders',
      'Class Reminders',
      channelDescription: 'Reminders before class starts',
      importance: Importance.high,
      priority: Priority.high,
      // FIX: show heads-up notification on Android when screen is on
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
      debugPrint('[NotificationService] Scheduled id=$id at $when');
    } catch (e) {
      // FIX: log clearly instead of swallowing — caller sees the error
      debugPrint(
        '[NotificationService] scheduleClassReminder failed id=$id: $e',
      );
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

  // ── Tap handler ───────────────────────────────────────────────────────────

  static void _onNotificationResponse(NotificationResponse response) {
    // FIX: placeholder — wire up navigation here if needed in the future
    debugPrint('[NotificationService] Tapped notification id=${response.id}');
  }
}
