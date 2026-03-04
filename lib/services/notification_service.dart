// lib/services/notification_service.dart

import 'log_buffer.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'mobile_toast_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channel = MethodChannel('com.instructormate/battery');

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
    AppLog.d('[NS] _doInit starting...');

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      AppLog.d('[NS] plugin.initialize() succeeded');
    } catch (e) {
      AppLog.e('[NS] plugin.initialize() FAILED: $e');
      // Do not rethrow — app must not crash if notifications are broken
      _initialized = true;
      return false;
    }

    _initialized = true;

    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidImpl != null) {
        _notifGranted =
            await androidImpl.requestNotificationsPermission() ?? false;
        _alarmGranted =
            await androidImpl.requestExactAlarmsPermission() ?? false;
        AppLog.d('[NS] granted=$_notifGranted exactAlarm=$_alarmGranted');
        await _requestBatteryOptimizationExemption();
      } else {
        _notifGranted = true;
        _alarmGranted = true;
      }
    } catch (e) {
      AppLog.e('[NS] permission request failed (non-fatal): $e');
      _notifGranted = true;
    }

    return _notifGranted;
  }

  // ── Battery optimization ──────────────────────────────────────────────────

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      AppLog.d('[NS] Battery optimization exemption requested.');
    } catch (e) {
      AppLog.d('[NS] Battery exemption failed (non-fatal): $e');
    }
  }

  Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod('openBatterySettings');
    } catch (e) {
      AppLog.d('[NS] openBatterySettings failed: $e');
    }
  }

  // ── Permission check ──────────────────────────────────────────────────────

  Future<bool> hasPermission() async {
    if (!_supported) return false;
    await init();
    try {
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
    } catch (e) {
      AppLog.e('[NS] hasPermission failed: $e');
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
      AppLog.d('[NS] No permission — skipping id=$id');
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_reminders',
        'Class Reminders',
        channelDescription: 'Reminders before class starts',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: false,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        visibility: NotificationVisibility.public,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    final payload = '$title||$body';
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      AppLog.d('[NS] Scheduled id=$id at $when');
    } catch (e) {
      final msg = e.toString().toLowerCase();
      AppLog.e('[NS] zonedSchedule failed id=$id: $e');
      if (msg.contains('exact') || msg.contains('platformexception')) {
        try {
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            when,
            details,
            payload: payload,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          AppLog.d('[NS] Scheduled inexact id=$id');
        } catch (e2) {
          AppLog.e('[NS] inexact also failed id=$id: $e2');
        }
      }
    }
  }

  // ── Native purge (bypass broken plugin cancelAll) ─────────────────────────

  Future<void> nativePurgeAndCancel() async {
    if (!_supported) return;
    AppLog.d('[NS] nativePurgeAndCancel — no-op (purge done in MainActivity)');
  }

  Future<void> cancel(int id) async {
    if (!_supported) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_supported) return;
    try {
      await _plugin.cancelAll();
      AppLog.d('[NS] cancelAll done');
    } catch (e) {
      AppLog.e('[NS] cancelAll failed: $e');
    }
  }

  // ── Notification response ─────────────────────────────────────────────────

  static void _onNotificationResponse(NotificationResponse response) {
    AppLog.d('[NS] >>> onNotificationResponse id=${response.id}');
    try {
      final payload = response.payload ?? '';
      final sep = payload.indexOf('||');
      final title = sep >= 0 ? payload.substring(0, sep) : 'Class Reminder';
      final body = sep >= 0 ? payload.substring(sep + 2) : '';
      AppLog.d('[NS] Toast: title="$title"');
      MobileToastService.show(title: title, body: body);
    } catch (e, stack) {
      AppLog.e('[NS] onNotificationResponse crash: $e\n$stack');
    }
  }

  Future<void> showImmediateTest() async {
    if (!_supported) return;
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_reminders',
        'Class Reminders',
        importance: Importance.max,
        priority: Priority.max,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(11111, '🚀 Test', 'Notifications working!', details);
  }
}
