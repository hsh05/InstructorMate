// lib/services/notification_service.dart

import 'log_buffer.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'mobile_toast_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // Native method channel — used to request battery optimization exemption.
  // This is the fix for Samsung Device Care killing AlarmManager alarms
  // within seconds of the user pressing the home button.
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

    // ── ONE-TIME PURGE of corrupted legacy notifications ──────────────────
    // Old builds used matchDateTimeComponents (repeating, type=2).
    // The flutter_local_notifications Java deserializer crashes with
    // "Missing type parameter" when it tries to load those stored entries
    // during zonedSchedule → saveScheduledNotification → loadScheduledNotifications.
    // Fix: on the very first run of this build, wipe ALL stored notification
    // data via cancelAll() BEFORE initialize() deserializes anything.
    // After the purge we set a flag so we never wipe again (rescheduleAll
    // will repopulate with clean one-shot type=1 entries).
    try {
      final prefs = await SharedPreferences.getInstance();
      final purged = prefs.getBool('notif_purge_v2') ?? false;
      if (!purged) {
        AppLog.d('[NS] First run — purging legacy corrupted notifications...');
        // cancelAll via the raw plugin before initialize to avoid deserialization
        await _plugin.cancelAll();
        await prefs.setBool('notif_purge_v2', true);
        AppLog.d('[NS] Purge complete — legacy entries wiped.');
      }
    } catch (e) {
      AppLog.d('[NS] Purge step failed (non-fatal): $e');
    }

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
      AppLog.d('[NS] granted=$_notifGranted exactAlarm=$_alarmGranted');

      // REQUEST BATTERY OPTIMIZATION EXEMPTION.
      // Without this, Samsung Device Care suspends AlarmManager alarms
      // within seconds of the app being backgrounded. The system shows a
      // one-time dialog — user taps "Allow" and it persists permanently.
      await _requestBatteryOptimizationExemption();
    } else {
      _notifGranted = didInit ?? true;
      _alarmGranted = _notifGranted;
    }

    return _notifGranted;
  }

  // ── Battery optimization exemption ────────────────────────────────────────

  Future<void> _requestBatteryOptimizationExemption() async {
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      AppLog.d('[NS] Battery optimization exemption requested.');
    } catch (e) {
      AppLog.d('[NS] Battery exemption request failed (non-fatal): $e');
    }
  }

  /// Opens the battery settings page so the user can manually whitelist the
  /// app if they dismissed the initial prompt. Wire to a settings button.
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

    // Encode title+body as payload so foreground callback can show toast
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

      // ── "Missing type parameter" — corrupted legacy data in storage ───────
      // Happens when old repeating notifications (type=2) are still stored.
      // Self-heal: wipe ALL stored data and retry once with a clean slate.
      if (msg.contains('missing type parameter')) {
        AppLog.d(
          '[NS] !!! Missing type parameter on id=$id — wiping and retrying...',
        );
        try {
          await _plugin.cancelAll();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('notif_purge_v2', true);
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
          AppLog.d('[NS] Retry after purge succeeded id=$id');
        } catch (e2) {
          AppLog.e('[NS] Retry after purge also failed id=$id: $e2');
        }
      } else if (msg.contains('exact') ||
          msg.contains('schedule_exact') ||
          msg.contains('platformexception')) {
        AppLog.d('[NS] Exact blocked, trying inexact id=$id');
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
          AppLog.e('[NS] Both exact and inexact failed id=$id: $e2');
        }
      } else {
        AppLog.e('[NS] Schedule failed id=$id: $e');
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
      AppLog.d('[NS] All cancelled.');
    } catch (e) {
      AppLog.d('[NS] cancelAll failed: $e');
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    AppLog.d('[NS] >>> onNotificationResponse CALLED');
    AppLog.d('[NS]     actionId=${response.actionId}');
    AppLog.d('[NS]     notifResponseType=${response.notificationResponseType}');
    AppLog.d('[NS]     id=${response.id}');
    AppLog.d('[NS]     payload="${response.payload}"');
    try {
      final payload = response.payload ?? '';
      AppLog.d('[NS] Step 1 — payload parsed ok: "$payload"');
      final sep = payload.indexOf('||');
      final title = sep >= 0 ? payload.substring(0, sep) : 'Class Reminder';
      final body = sep >= 0 ? payload.substring(sep + 2) : '';
      AppLog.d('[NS] Step 2 — title="$title" body="$body"');
      AppLog.d('[NS] Step 3 — calling MobileToastService.show...');
      MobileToastService.show(title: title, body: body);
      AppLog.d('[NS] Step 4 — MobileToastService.show returned ok');
    } catch (e, stack) {
      AppLog.d('[NS] !!! CRASH in onNotificationResponse: $e');
      AppLog.d('[NS] !!! STACK: $stack');
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

    await _plugin.show(
      11111,
      '🚀 Immediate Notification',
      'If you see this, notifications are working.',
      details,
    );
  }
}
