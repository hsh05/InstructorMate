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

    debugPrint(
      '[Scheduler] rescheduleAll START — ${workspaces.length} workspaces',
    );
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
    debugPrint(
      '[Scheduler] rescheduleAll DONE for ${workspaces.length} workspaces.',
    );
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
        '[Scheduler] SKIP section "${section.name}" — startTime is empty.',
      );
      return;
    }
    // FIX: Use robust parser — handles "9:00", "09:00", "9:00 AM", "9:00 PM".
    // The old split(':') + int.tryParse failed silently for any time with an
    // AM/PM suffix: "00 AM" → int.tryParse → null → section skipped with no alarm.
    final parsed = _parseHHmm(sch.startTime);
    if (parsed == null) {
      debugPrint(
        '[Scheduler] SKIP section "${section.name}" — unparseable startTime="${sch.startTime}"',
      );
      return;
    }
    final hour = parsed.hour;
    final minute = parsed.minute;
    final location = tz.local;

    final reminderMinutes = sch.reminderMinutes > 0 ? sch.reminderMinutes : 10;
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

      debugPrint(
        '[Scheduler] "${section.name}" $day → firstFire=$firstOccurrence remind=${reminderMinutes}min',
      );
      // Schedule _weeksAhead individual one-time notifications
      for (int week = 0; week < _weeksAhead; week++) {
        final fireTime = firstOccurrence.add(Duration(days: week * 7));
        final notifId = _notifId(workspaceId, section.id, day, week);
        debugPrint('[Scheduler]   week=$week id=$notifId fireTime=$fireTime');
        await NotificationService.instance.scheduleClassReminder(
          id: notifId,
          title: '⏰ $courseName starts in ${reminderMinutes}min',
          body: '$sectionLabel$locationStr — $friendlyTime',
          when: fireTime,
        );
      }
    }
  }

  // FIX: Robust time parser — identical to web_notification_service._parseHHmm.
  // Handles "HH:mm", "H:mm", "H:mm AM", "H:mm PM", "12:00 PM"→12, "12:00 AM"→0.
  static ({int hour, int minute})? _parseHHmm(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final upper = s.toUpperCase();
    final isPM = upper.contains('PM');
    final isAM = upper.contains('AM');
    final timeOnly = s
        .replaceAll(RegExp(r'[AaPp][Mm]', caseSensitive: false), '')
        .trim();
    final parts = timeOnly.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    int hour24 = h;
    if (isPM && h != 12) hour24 = h + 12;
    if (isAM && h == 12) hour24 = 0;
    return (hour: hour24, minute: m);
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

    // FIX: Only jump to next week if more than 60 seconds past.
    // Mirrors the web service fix — if the scheduler runs at e.g. 09:50:30
    // and fireTime=09:50:00, isBefore(now) was true so it jumped to next week,
    // meaning the notification was never scheduled for today.
    final secondsPast = now.difference(fireTime).inSeconds;
    if (secondsPast >= 60) {
      fireTime = fireTime.add(const Duration(days: 7));
    }

    return fireTime;
  }
}
