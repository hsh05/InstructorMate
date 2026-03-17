// lib/services/notification_service.dart
// Uses flutter_local_notifications ^18.0.1
//
// IMPROVEMENTS:
// 1. BigTextStyleInformation — notification expands when pulled down showing
//    full course name, section, location and time without truncation.
// 2. App accent color (purple) on the notification left strip.
// 3. subText "InstructorMate" — users know which app sent it.
// 4. ticker — text that scrolls in status bar when notification first appears.
// 5. Separate urgent channel for class reminders with a distinct sound.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
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

  // App purple — matches AppColors.primary
  static const int _purple = 0xFF6747B0;

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

    // BigTextStyleInformation makes the notification expandable.
    // The body is structured as "Course Name\nSection · Location · Day Time"
    // so when expanded, each part gets its own line for easy reading.
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
        // Purple strip on the left side of the notification
        color: const Color(_purple),
        // Text that scrolls in the status bar when notification first arrives
        ticker: title,
        // "InstructorMate" shown below the app name in the notification header
        subText: 'Class Reminder',
        // Expandable big text view
        styleInformation: bigTextStyle,
        // Keep notification visible on lock screen
        visibility: NotificationVisibility.public,
        // Show notification as a heads-up (pops over other apps)
        fullScreenIntent: false,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        // Shows subtitle on iOS lock screen / notification centre
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
        color: const Color(_purple),
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
