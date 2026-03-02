// lib/services/notification_scheduler.dart
//
// ARCHITECTURAL CHANGE: No longer uses matchDateTimeComponents (repeating).
//
// The "Missing type parameter" crash is caused by the repeating notification
// serialization format (type=2) in flutter_local_notifications. The plugin's
// Java deserializer is brittle — any mismatch in the stored JSON causes a
// RuntimeException that cannot be caught in Dart.
//
// FIX: Schedule the next 4 individual one-time occurrences per section/day
// instead of one repeating notification. Type=1 (one-shot) serialization
// is simple and never causes deserialization crashes.
// rescheduleAll() is already called on every app launch and after every
// section change, so notifications stay current.

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:timezone/timezone.dart' as tz;

import '../app/workspace_models.dart';
import '../utils/schedule_utils.dart';
import 'notification_service.dart';

class NotificationScheduler {
  // How many future occurrences to schedule per section+day.
  // 4 weeks covers a month; rescheduleAll on next app open refreshes them.
  static const int _weeksAhead = 4;

  static Future<void> rescheduleAll(List<Workspace> workspaces) async {
    if (kIsWeb) return;

    final hasPermission = await NotificationService.instance.hasPermission();
    if (!hasPermission) {
      debugPrint('[Scheduler] No permission — skipping.');
      return;
    }

    await NotificationService.instance.cancelAll();

    for (final ws in workspaces) {
      for (final section in ws.sections) {
        await _scheduleSection(
          section: section,
          courseName: ws.title,
          workspaceId: ws.id,
        );
      }
    }
    debugPrint('[Scheduler] Done for ${workspaces.length} workspaces.');
  }

  // Stable ID from workspace + section + day + week offset.
  // Keeps IDs consistent across reschedules.
  static int _notifId(
    String workspaceId,
    String sectionId,
    String day,
    int weekIndex,
  ) {
    final key = '$workspaceId:$sectionId:$day:$weekIndex';
    int hash = 5381;
    for (final c in key.codeUnits) {
      hash = ((hash << 5) + hash) + c;
    }
    return hash.abs() % 2000000000; // stay within Android int range
  }

  static Future<void> _scheduleSection({
    required Section section,
    required String courseName,
    required String workspaceId,
  }) async {
    final sch = section.schedule;

    // FIX: log clearly when skipping so you can see it in the debug console
    // instead of silently returning with no trace.
    if (sch.startTime.isEmpty) {
      debugPrint(
        '[Scheduler] SKIP section "${section.name}" — startTime is empty. '
        'Edit the section and set a start time.',
      );
      return;
    }
    final timeParts = sch.startTime.split(':');
    if (timeParts.length < 2) {
      debugPrint(
        '[Scheduler] SKIP section "${section.name}" — bad startTime format: "${sch.startTime}"',
      );
      return;
    }
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    if (hour == null || minute == null) {
      debugPrint(
        '[Scheduler] SKIP section "${section.name}" — non-numeric time: "${sch.startTime}"',
      );
      return;
    }

    tz.Location location;
    try {
      location = tz.getLocation(sch.timezone.isNotEmpty ? sch.timezone : 'UTC');
    } catch (_) {
      location = tz.local;
    }

    final reminderMinutes = sch.reminderMinutes > 0 ? sch.reminderMinutes : 15;
    final sectionLabel = section.name.isNotEmpty ? section.name : 'Class';
    final locationStr = section.location.isNotEmpty
        ? ' @ ${section.location}'
        : '';
    final friendlyTime = ScheduleUtils.formatTime(sch.startTime);

    for (final day in sch.days) {
      // FIX: trim day strings — CSV round-trips can introduce leading spaces
      // e.g. "Mon, Tue" split by "," gives [" Tue"] which weekdayFor() won't match.
      final dayTrimmed = day.trim();
      final weekday = ScheduleUtils.weekdayFor(dayTrimmed);
      if (weekday == null) {
        debugPrint(
          '[Scheduler] SKIP day "$day" in section "${section.name}" — unrecognised. '
          'Expected Mon/Tue/Wed/Thu/Fri/Sat/Sun.',
        );
        continue;
      }

      // Find the next occurrence of this weekday
      final firstOccurrence = _nextOccurrence(
        weekday: weekday,
        hour: hour,
        minute: minute,
        location: location,
        reminderMinutes: reminderMinutes,
      );

      // Schedule _weeksAhead individual one-time notifications
      for (int week = 0; week < _weeksAhead; week++) {
        final fireTime = firstOccurrence.add(Duration(days: week * 7));

        await NotificationService.instance.scheduleClassReminder(
          id: _notifId(workspaceId, section.id, day, week),
          title: '⏰ $courseName starts in ${reminderMinutes}min',
          body: '$sectionLabel$locationStr — $friendlyTime',
          when: fireTime,
        );
      }
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

    var classTime = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // Advance to the correct weekday
    int safety = 0;
    while (classTime.weekday != weekday) {
      classTime = classTime.add(const Duration(days: 1));
      if (++safety > 7) break;
    }

    // Subtract reminder offset
    var fireTime = classTime.subtract(Duration(minutes: reminderMinutes));

    // If already past, jump to next week
    if (fireTime.isBefore(now)) {
      fireTime = fireTime.add(const Duration(days: 7));
    }

    return fireTime;
  }
}
