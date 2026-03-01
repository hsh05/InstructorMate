// lib/services/notification_scheduler.dart
//
// FIX: _nextOccurrence previously called .subtract(reminderMinutes) BEFORE
//      aligning to the correct weekday. When the reminder offset crossed
//      midnight (e.g. class at 00:05 with 15-min reminder → 23:50 previous
//      day), candidate.weekday was already wrong and the while-loop
//      overshot by a full week.
//
//      Fix: align to the target weekday FIRST, then subtract the reminder
//      offset. Also tightened the safety cap to 7 days (one full week is
//      enough to find the next occurrence).
//
// No other logic changed.

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:timezone/timezone.dart' as tz;

import '../app/workspace_models.dart';
import '../utils/schedule_utils.dart';
import 'notification_service.dart';

class NotificationScheduler {
  static Future<void> rescheduleAll(List<Workspace> workspaces) async {
    if (kIsWeb) return;

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
        notifId += 10;
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

    tz.Location location;
    try {
      location = tz.getLocation(sch.timezone.isNotEmpty ? sch.timezone : 'UTC');
    } catch (_) {
      location = tz.local;
    }

    final reminderMinutes = sch.reminderMinutes > 0 ? sch.reminderMinutes : 15;

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

    // FIX: start from today at the class time (no reminder offset yet)
    var classTime = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // Step 1 — advance to the correct weekday (max 7 days forward)
    int safety = 0;
    while (classTime.weekday != weekday) {
      classTime = classTime.add(const Duration(days: 1));
      if (++safety > 7) break;
    }

    // Step 2 — subtract reminder offset to get the fire time
    var fireTime = classTime.subtract(Duration(minutes: reminderMinutes));

    // Step 3 — if the fire time is already in the past, skip ahead one week
    if (fireTime.isBefore(now)) {
      fireTime = fireTime.add(const Duration(days: 7));
    }

    return fireTime;
  }
}
