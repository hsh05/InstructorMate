// lib/services/notifications/notification_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../app_styles.dart';
import 'in_app_queue.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const _channel = MethodChannel('com.instructormate/battery');

  bool _initialized = false;
  bool _notifGranted = false;

  Future<bool>? _initFuture;

  bool get _isDesktopOrWeb => 
      kIsWeb || 
      defaultTargetPlatform == TargetPlatform.windows || 
      defaultTargetPlatform == TargetPlatform.macOS || 
      defaultTargetPlatform == TargetPlatform.linux;

  Future<bool> init() {
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
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // If the user clicks the notification, we don't need the toast anymore.
          // Tapping it naturally opens the app. 
          debugPrint("User tapped notification.");
        },
      );
    } catch (e) {
      _initialized = true;
      return false;
    }
    _initialized = true;
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        _notifGranted = await androidImpl.requestNotificationsPermission() ?? false;
        await requestExactAlarmPermission();
        await _requestBatteryOptimizationExemption();
      } else {
        _notifGranted = true;
      }
    } catch (e) {
      _notifGranted = true;
    }
    return _notifGranted;
  }

  Future<void> requestExactAlarmPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.requestExactAlarmsPermission();
      }
    }
  }

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (e) {}
  }

  Future<bool> hasPermission() async {
    if (_isDesktopOrWeb) return true;
    await init();
    return _notifGranted;
  }

  Future<void> scheduleClassReminder({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
  }) async {
    if (_isDesktopOrWeb) {
      await InAppQueue.add(id: id, title: title, body: body, fireTime: when);
      return;
    }

    await init();
    if (!_notifGranted) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'class_reminders',
        'Class Reminders',
        importance: Importance.max,
        priority: Priority.max,
        color: AppStyles.primary,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        // 👉 THE FIX 3: Removed the massive payload string that was choking the BroadcastReceiver
        payload: 'InstructorMate_Reminder',
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint("Schedule Error: $e");
    }
  }

  Future<void> cancel(int id) async {
    if (_isDesktopOrWeb) {
      await InAppQueue.cancel(id);
      return;
    }
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (_isDesktopOrWeb) {
      await InAppQueue.cancelAll();
      return;
    }
    try {
      await _plugin.cancelAll();
    } catch (e) {}
  }
}