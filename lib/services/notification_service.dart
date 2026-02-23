// lib/app/notifications/notification_service.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Web doesn't support flutter_local_notifications — guard every call
  bool get _supported => !kIsWeb;

  Future<void> init() async {
    if (!_supported) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS: request permission on init
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);

    // Android 13+: request exact alarm permission
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  }

  Future<void> scheduleClassReminder({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
  }) async {
    if (!_supported) return;

    const androidDetails = AndroidNotificationDetails(
      'class_reminders',
      'Class Reminders',
      channelDescription: 'Reminders before class starts',
      importance: Importance.high,
      priority: Priority.high,
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

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Repeat weekly — fires every week on the same day/time
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
    );
  }

  Future<void> cancel(int id) async {
    if (!_supported) return;
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    if (!_supported) return;
    await _plugin.cancelAll();
  }
}
