// lib/services/notification_scheduler.dart
//
// Schedules a "N minutes before class" notification for every (section × day).
// Each notification repeats weekly via DateTimeComponents.dayOfWeekAndTime.
//
// FIX: Previously _dayMap was duplicated here and in WebNotificationService.
//      Now uses shared ScheduleUtils.dayMap.
// FIX: Now checks for notification permission before scheduling, so on Android
//      13+ that denied permission we fail gracefully with a debugPrint rather
//      than silently doing nothing or throwing.
// FIX: Improved time display uses ScheduleUtils.formatTime (12-h AM/PM).

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:timezone/timezone.dart' as tz;

import '../app/workspace_models.dart';
import '../utils/schedule_utils.dart';
import 'notification_service.dart';

class NotificationScheduler {
  /// Cancel all existing reminders then re-schedule for every section
  /// in every workspace. Call after load() or after creating/deleting a section.
  static Future<void> rescheduleAll(List<Workspace> workspaces) async {
    if (kIsWeb) return;

    // FIX: check permission first — avoids silent failure on Android 13+
    final hasPermission = await NotificationService.instance.hasPermission();
    if (!hasPermission) {
      debugPrint(
        '[NotificationScheduler] No permission — skipping reschedule.',
      );
      return;
    }

    await NotificationService.instance.cancelAll();

    int notifId = 0;
    for (final ws in workspaces) {
      for (int si = 0; si < ws.sections.length; si++) {
        final section = ws.sections[si];
        await _scheduleSection(
          section: section,
          courseName: ws.title,
          baseId: notifId,
        );
        notifId += 10; // 10 slots per section (one per possible day)
      }
    }
    debugPrint(
      '[NotificationScheduler] Rescheduled for ${workspaces.length} workspaces.',
    );
  }

  static Future<void> _scheduleSection({
    required Section section,
    required String courseName,
    required int baseId,
  }) async {
    final sch = section.schedule;

    final timeParts = sch.startTime.split(':');
    if (timeParts.length < 2) return;
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) return;

    // Resolve timezone — fall back to local if unknown
    tz.Location location;
    try {
      location = tz.getLocation(sch.timezone.isNotEmpty ? sch.timezone : 'UTC');
    } catch (_) {
      location = tz.local;
    }

    final reminderMinutes = sch.reminderMinutes > 0 ? sch.reminderMinutes : 15;

    // FIX: use ScheduleUtils instead of local _dayMap
    for (int di = 0; di < sch.days.length; di++) {
      final weekday = ScheduleUtils.weekdayFor(sch.days[di]);
      if (weekday == null) continue;

      final notifId = baseId + di;
      final scheduledTime = _nextOccurrence(
        weekday: weekday,
        hour: hour,
        minute: minute,
        location: location,
        reminderMinutes: reminderMinutes,
      );

      final sectionLabel = section.name.isNotEmpty ? section.name : 'Class';
      final locationStr = section.location.isNotEmpty
          ? ' @ ${section.location}'
          : '';
      // FIX: show 12-h formatted start time so notification body is user-friendly
      final friendlyTime = ScheduleUtils.formatTime(sch.startTime);

      await NotificationService.instance.scheduleClassReminder(
        id: notifId,
        title: '⏰ $courseName starts in ${reminderMinutes}min',
        body: '$sectionLabel$locationStr — $friendlyTime',
        when: scheduledTime,
      );
    }
  }

  static tz.TZDateTime _nextOccurrence({
    required int weekday,
    required int hour,
    required int minute,
    required tz.Location location,
    required int reminderMinutes,
  }) {
    final now = tz.TZDateTime.now(location);

    var candidate = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).subtract(Duration(minutes: reminderMinutes));

    int safety = 0;
    while (candidate.weekday != weekday || candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
      if (++safety > 14) break;
    }

    return candidate;
  }
}
