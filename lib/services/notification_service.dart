// lib/services/notification_service.dart

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

    // Cancel all on init to clear any stale entries.
    // Safe because we no longer use matchDateTimeComponents — all
    // notifications are simple one-shot (type=1) which never causes
    // the "Missing type parameter" deserialization crash.
    try {
      await _plugin.cancelAll();
      debugPrint('[NS] Init: cleared existing notifications.');
    } catch (e) {
      debugPrint('[NS] Init cancelAll failed (non-fatal): $e');
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
        importance: Importance.max, // max = forces heads-up banner
        priority: Priority.max, // max = shows over other notifications
        fullScreenIntent: false,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        visibility: NotificationVisibility.public, // shows on lock screen
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    // One-shot scheduling — NO matchDateTimeComponents.
    // The scheduler calls this multiple times (once per week) to cover
    // upcoming occurrences. This avoids the repeating notification
    // serialization format that causes "Missing type parameter" crashes.
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
        // NO matchDateTimeComponents — intentionally one-shot
      );
      debugPrint('[NS] Scheduled id=$id at $when');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // If exact alarm is blocked by OS, fall back to inexact
      if (msg.contains('exact') ||
          msg.contains('schedule_exact') ||
          msg.contains('platformexception')) {
        debugPrint('[NS] Exact blocked, trying inexact id=$id');
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
            // NO matchDateTimeComponents — intentionally one-shot
          );
          debugPrint('[NS] Scheduled inexact id=$id');
        } catch (e2) {
          debugPrint('[NS] Both exact and inexact failed id=$id: $e2');
        }
      } else {
        debugPrint('[NS] Schedule failed id=$id: $e');
      }
    }
  }

  Future<void> cancel(int id) async {
    if (!_supported) return;
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    if (!_supported) return;
    try {
      await _plugin.cancelAll();
      debugPrint('[NS] All cancelled.');
    } catch (e) {
      debugPrint('[NS] cancelAll failed: $e');
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    debugPrint('[NS] Tapped id=${response.id}');
  }
}
