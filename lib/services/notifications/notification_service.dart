// lib/services/notifications/notification_service.dart

import 'package:flutter/foundation.dart'; // 👉 NEW: Imported for defaultTargetPlatform
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app_styles.dart'; 
import 'mobile_toast_service.dart';
import 'in_app_queue.dart'; // 👉 NEW: Import the Desktop Queue

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

  // 👉 NEW: Helper to check if we are on a desktop/web platform
  bool get _isDesktopOrWeb => 
      kIsWeb || 
      defaultTargetPlatform == TargetPlatform.windows || 
      defaultTargetPlatform == TargetPlatform.macOS || 
      defaultTargetPlatform == TargetPlatform.linux;

  Future<bool> init() {
    // 👉 THE FIX: Bypass OS initialization if on Desktop/Web
    if (_isDesktopOrWeb) return Future.value(true); 
    
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
    // 👉 THE FIX: Always grant permission on desktop so the Bell Icon shows up!
    if (_isDesktopOrWeb) return true;

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
    // 👉 THE FIX: Route Desktop/Web requests to our custom queue
    if (_isDesktopOrWeb) {
      await InAppQueue.add(id: id, title: title, body: body, fireTime: when);
      return;
    }

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
        
        color: AppStyles.primary, 
        
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
    // 👉 THE FIX: Cancel from the queue if on Desktop
    if (_isDesktopOrWeb) {
      await InAppQueue.cancel(id);
      return;
    }

    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    // 👉 THE FIX: Clear the entire queue if on Desktop
    if (_isDesktopOrWeb) {
      await InAppQueue.cancelAll();
      return;
    }

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
    // 👉 THE FIX: Show the custom toast immediately on Desktop
    if (_isDesktopOrWeb) {
      MobileToastService.show(
        title: '🚀 InstructorMate', 
        body: 'Notifications working!'
      );
      return;
    }

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
        
        color: AppStyles.primary, 
        
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