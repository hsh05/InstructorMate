// lib/services/notification_scheduler.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:timezone/timezone.dart' as tz;

import '../app/workspace_models.dart';
import '../utils/schedule_utils.dart';
import 'notification_service.dart';

class NotificationScheduler {
  // How many future occurrences to schedule per section+day.
  static const int _weeksAhead = 4;

  static Future<void> rescheduleAll(List<Workspace> workspaces) async {
    if (kIsWeb) return;

    final hasPermission = await NotificationService.instance.hasPermission();
    if (!hasPermission) return;

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
  }

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
    return hash.abs() % 2000000000;
  }

  static Future<void> _scheduleSection({
    required Section section,
    required String courseName,
    required String workspaceId,
  }) async {
    final sch = section.schedule;
    if (sch.startTime.isEmpty) return;

    final parsed = _parseHHmm(sch.startTime);
    if (parsed == null) return;

    final hour = parsed.hour;
    final minute = parsed.minute;
    final location = tz.local;
    final reminderMinutes = sch.reminderMinutes > 0 ? sch.reminderMinutes : 10;

    // ── Build notification content ────────────────────────────────────────────
    //
    // Title: always short so it NEVER gets truncated on any screen size.
    // The emoji + countdown is the most urgent info — must always be visible.
    final title = '⏰ Class starting in ${reminderMinutes}min';

    // Body line 1: full course name (visible when notification is expanded)
    final courseDisplay = courseName.isNotEmpty ? courseName : 'Your class';

    // Body line 2: section · location · day time
    // Only include parts that actually have data
    final sectionLabel = section.name.isNotEmpty ? section.name : '';
    final locationLabel = section.location.isNotEmpty ? section.location : '';
    final friendlyTime = ScheduleUtils.formatTime(sch.startTime);

    for (final day in sch.days) {
      final dayTrimmed = day.trim();
      final weekday = ScheduleUtils.weekdayFor(dayTrimmed);
      if (weekday == null) continue;

      // Include the day name in the details line so the user knows
      // which day this is for (important for multi-day sections)
      final parts = <String>[];
      if (sectionLabel.isNotEmpty) parts.add(sectionLabel);
      if (locationLabel.isNotEmpty) parts.add(locationLabel);
      parts.add('$dayTrimmed $friendlyTime');

      final detailsLine = parts.join('  ·  ');

      // Full body shown when notification is expanded via BigTextStyle
      final body = '$courseDisplay\n$detailsLine';

      final firstOccurrence = _nextOccurrence(
        weekday: weekday,
        hour: hour,
        minute: minute,
        location: location,
        reminderMinutes: reminderMinutes,
      );

      for (int week = 0; week < _weeksAhead; week++) {
        final fireTime = firstOccurrence.add(Duration(days: week * 7));
        final notifId = _notifId(workspaceId, section.id, day, week);
        await NotificationService.instance.scheduleClassReminder(
          id: notifId,
          title: title,
          body: body,
          when: fireTime,
        );
      }
    }
  }

  static ({int hour, int minute})? _parseHHmm(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final upper = s.toUpperCase();
    final isPM = upper.contains('PM');
    final isAM = upper.contains('AM');
    final timeOnly =
        s.replaceAll(RegExp(r'[AaPp][Mm]', caseSensitive: false), '').trim();
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
    int safety = 0;
    while (classTime.weekday != weekday) {
      classTime = classTime.add(const Duration(days: 1));
      if (++safety > 7) break;
    }
    var fireTime = classTime.subtract(Duration(minutes: reminderMinutes));
    final secondsPast = now.difference(fireTime).inSeconds;
    if (secondsPast >= 60) {
      fireTime = fireTime.add(const Duration(days: 7));
    }
    return fireTime;
  }
}
