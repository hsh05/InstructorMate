// lib/services/notifications/notification_service.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app_styles.dart'; 
import 'mobile_toast_service.dart';

// ─── REQUIRED top-level background handler ───────────────────────────────────
@pragma('vm:entry-point')
void notificationBackgroundHandler(NotificationResponse response) {
  try {
    final payload = response.payload ?? '';
    final sep = payload.indexOf('||');
    final title = sep >= 0 ? payload.substring(0, sep) : 'Class Reminder';
    final body = sep >= 0 ? payload.substring(sep + 2) : '';
    MobileToastService.show(title: title, body: body);
  } catch (e) {}
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
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse:
            notificationBackgroundHandler,
      );
    } catch (e) {
      _initialized = true;
      return false;
    }
    _initialized = true;
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
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
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
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
    if (!_notifGranted) return;

    final bigTextStyle = BigTextStyleInformation(
      body,
      htmlFormatBigText: false,
      contentTitle: title,
      htmlFormatContentTitle: false,
      summaryText: 'InstructorMate',
      htmlFormatSummaryText: false,
    );

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_reminders',
        'Class Reminders',
        channelDescription: 'Upcoming class reminders from InstructorMate',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        
        color: AppStyles.primaryPurple, 
        
        ticker: title,
        subText: 'Class Reminder',
        styleInformation: bigTextStyle,
        visibility: NotificationVisibility.public,
        fullScreenIntent: false,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: 'Class Reminder',
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
    } catch (e) {}
  }

  Future<void> showImmediateTest() async {
    if (!_supported) return;
    await init();
    final bigTextStyle = BigTextStyleInformation(
      'Your notifications are working correctly. You will be reminded before each class starts.',
      contentTitle: '🚀 InstructorMate — Test Notification',
      summaryText: 'InstructorMate',
    );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_reminders',
        'Class Reminders',
        importance: Importance.max,
        priority: Priority.max,
        
        color: AppStyles.primaryPurple, 
        
        subText: 'Test',
        styleInformation: bigTextStyle,
        visibility: NotificationVisibility.public,
      ),
      iOS: const DarwinNotificationDetails(
        subtitle: 'Test',
      ),
    );
    await _plugin.show(
        11111, '🚀 InstructorMate', 'Notifications working!', details);
  }
}