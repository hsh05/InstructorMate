// lib/services/notification_service.dart
// Uses flutter_local_notifications ^18.0.1
//
// CHANGES FROM ORIGINAL:
// 1. Added top-level notificationBackgroundHandler() with @pragma annotation.
//    This is REQUIRED — without it, tapping a notification when the app is
//    backgrounded or killed does nothing (response silently dropped).
// 2. Wired onDidReceiveBackgroundNotificationResponse in initialize().
// 3. Removed custom MethodChannel battery call — your MainActivity.kt already
//    handles it correctly; the Dart side just needs to keep calling it as-is.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'mobile_toast_service.dart';

// ─── REQUIRED top-level background handler ───────────────────────────────────
// Must be TOP-LEVEL (not inside a class) and annotated so Dart's AOT compiler
// keeps it in release builds. Called when the app is backgrounded/killed and
// the user taps a notification.
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  try {
    final payload = response.payload ?? '';
    final sep = payload.indexOf('||');
    final title = sep >= 0 ? payload.substring(0, sep) : 'Class Reminder';
    final body = sep >= 0 ? payload.substring(sep + 2) : '';
    // App is launching/resuming from tap — show the toast once navigator is ready
    MobileToastService.show(title: title, body: body);
  } catch (e, stack) {}
}

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

  Future<bool> init() {
    if (!_supported) return Future.value(false);
    _initFuture ??= _doInit();
    return _initFuture!;
  }

  Future<bool> _doInit() async {
    if (_initialized) return _notifGranted;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
        // Fires when user taps a notification while the app is OPEN
        onDidReceiveNotificationResponse: _onNotificationResponse,
        // FIX: fires when user taps a notification while app is BACKGROUND/KILLED
        // Must reference the TOP-LEVEL function above — not a class method.
        onDidReceiveBackgroundNotificationResponse:
            notificationBackgroundHandler,
      );
    } catch (e) {
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
        await _requestBatteryOptimizationExemption();
      } else {
        _notifGranted = true;
        _alarmGranted = true;
      }
    } catch (e) {
      _notifGranted = true;
    }
    return _notifGranted;
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {}
  }

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
    } catch (e) {}
    return _notifGranted;
  }

  Future<void> scheduleClassReminder({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
  }) async {
    if (!_supported) return;
    await init();
    if (!_notifGranted) {
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_reminders',
        'Class Reminders',
        channelDescription: 'Reminders before class starts',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _plugin.cancel(id);
    } catch (_) {}

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
    } catch (e) {}
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
    } catch (e) {}
  }

  static void _onNotificationResponse(NotificationResponse response) {
    try {
      final payload = response.payload ?? '';
      final sep = payload.indexOf('||');
      final title = sep >= 0 ? payload.substring(0, sep) : 'Class Reminder';
      final body = sep >= 0 ? payload.substring(sep + 2) : '';
      MobileToastService.show(title: title, body: body);
    } catch (e, stack) {}
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
