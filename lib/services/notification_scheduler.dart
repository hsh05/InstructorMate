// lib/services/notification_scheduler.dart

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
      debugPrint('[Scheduler] No permission — skipping.');
      return;
    }

    // Cancel all existing before rescheduling.
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

  // Stable hash-based notification ID from workspace + section + day.
  // Same section+day always gets the same ID regardless of list order.
  static int _notifId(String workspaceId, String sectionId, String day) {
    final key = '$workspaceId:$sectionId:$day';
    int hash = 5381;
    for (final c in key.codeUnits) {
      hash = ((hash << 5) + hash) + c;
    }
    return hash.abs() % 100000;
  }

  static Future<void> _scheduleSection({
    required Section section,
    required String courseName,
    required String workspaceId,
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
    final sectionLabel = section.name.isNotEmpty ? section.name : 'Class';
    final locationStr = section.location.isNotEmpty
        ? ' @ ${section.location}'
        : '';
    final friendlyTime = ScheduleUtils.formatTime(sch.startTime);

    for (final day in sch.days) {
      final weekday = ScheduleUtils.weekdayFor(day);
      if (weekday == null) continue;

      final scheduledTime = _nextOccurrence(
        weekday: weekday,
        hour: hour,
        minute: minute,
        location: location,
        reminderMinutes: reminderMinutes,
      );

      await NotificationService.instance.scheduleClassReminder(
        id: _notifId(workspaceId, section.id, day),
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

    // Start at today's class time, advance to the correct weekday, then
    // subtract the reminder offset. If the result is already past, add a week.
    var classTime = tz.TZDateTime(
      location,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    int safety = 0;
    while (classTime.weekday != weekday) {
      classTime = classTime.add(const Duration(days: 1));
      if (++safety > 7) break;
    }

    var fireTime = classTime.subtract(Duration(minutes: reminderMinutes));
    if (fireTime.isBefore(now)) {
      fireTime = fireTime.add(const Duration(days: 7));
    }

    return fireTime;
  }
}
