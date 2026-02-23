// lib/app/notifications/notification_scheduler.dart
//
// Schedules a "15 minutes before class" notification for every
// (section × day) pair. Each notification repeats weekly automatically
// because NotificationService uses DateTimeComponents.dayOfWeekAndTime.
//
// Notification ID scheme:
//   id = sectionIndex * 10 + dayIndex
// This gives each (section, day) a stable unique int ID so we can
// cancel/replace individual ones without touching others.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:timezone/timezone.dart' as tz;

import '../app/workspace_models.dart';
import 'notification_service.dart';

class NotificationScheduler {
  // Day abbreviation → DateTime weekday (Monday=1 … Sunday=7)
  static const _dayMap = {
    'mon': DateTime.monday,
    'tue': DateTime.tuesday,
    'wed': DateTime.wednesday,
    'thu': DateTime.thursday,
    'fri': DateTime.friday,
    'sat': DateTime.saturday,
    'sun': DateTime.sunday,
  };

  /// Cancel all existing reminders then re-schedule for every section
  /// in every workspace. Call this after load() or after creating a section.
  static Future<void> rescheduleAll(List<Workspace> workspaces) async {
    if (kIsWeb) return; // not supported on web

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
        notifId += 10; // leave 10 slots per section (one per day of week)
      }
    }
  }

  static Future<void> _scheduleSection({
    required Section section,
    required String courseName,
    required int baseId,
  }) async {
    final sch = section.schedule;

    // Parse start time "HH:mm"
    final timeParts = sch.startTime.split(':');
    if (timeParts.length < 2) return; // malformed time — skip
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

    for (int di = 0; di < sch.days.length; di++) {
      final dayKey = sch.days[di].toLowerCase().substring(0, 3);
      final weekday = _dayMap[dayKey];
      if (weekday == null) continue;

      final notifId = baseId + di;

      // Find the next occurrence of this weekday at class time
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

      await NotificationService.instance.scheduleClassReminder(
        id: notifId,
        title: '⏰ $courseName starts in ${reminderMinutes}min',
        body: '$sectionLabel$locationStr — ${sch.startTime}',
        when: scheduledTime,
      );
    }
  }

  /// Returns the next TZDateTime that falls on [weekday] at [hour]:[minute],
  /// minus [reminderMinutes], from now.
  static tz.TZDateTime _nextOccurrence({
    required int weekday,
    required int hour,
    required int minute,
    required tz.Location location,
    required int reminderMinutes,
  }) {
    final now = tz.TZDateTime.now(location);

    // Start from today at the class time minus reminder offset
    var candidate = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    ).subtract(Duration(minutes: reminderMinutes));

    // Advance day by day until we land on the correct weekday and it's in the future
    int safety = 0;
    while (candidate.weekday != weekday || candidate.isBefore(now)) {
      candidate = candidate.add(const Duration(days: 1));
      if (++safety > 14) break; // should never need more than 7 days
    }

    return candidate;
  }
}
