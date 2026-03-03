// lib/services/web_notification_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, VoidCallback, debugPrint;

import '../app/workspace_models.dart';
import '../utils/schedule_utils.dart';

// ─── Model ────────────────────────────────────────────────────────────────────
class PendingNotification {
  final String sectionName;
  final String courseName;
  final String startTime;
  final String location;
  final int minutesUntil;
  final DateTime fireAt;

  const PendingNotification({
    required this.sectionName,
    required this.courseName,
    required this.startTime,
    required this.location,
    required this.minutesUntil,
    required this.fireAt,
  });

  String get title => '⏰ $courseName starts in ${minutesUntil}min';

  String get body {
    final loc = location.isNotEmpty ? ' @ $location' : '';
    final friendlyTime = ScheduleUtils.formatTime(startTime);
    return '$sectionName$loc — $friendlyTime';
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────
class WebNotificationService {
  WebNotificationService._();
  static final WebNotificationService instance = WebNotificationService._();

  Timer? _ticker;

  // Stores the current workspace list — updated via init() / updateWorkspaces()
  List<Workspace> _workspaces = [];

  final List<PendingNotification> activeNotifications = [];
  int get unreadCount => activeNotifications.length;
  VoidCallback? onChanged;

  Future<void> init(List<Workspace> workspaces) async {
    if (!kIsWeb) return;
    _workspaces = List.of(workspaces);
    _ticker?.cancel();
    _startTicker();
  }

  void dispose() => _ticker?.cancel();

  void clearAll() {
    activeNotifications.clear();
    onChanged?.call();
  }

  void updateWorkspaces(List<Workspace> workspaces) {
    _workspaces = List.of(workspaces);
    _ticker?.cancel();
    _startTicker();
  }

  void _startTicker() {
    _checkNow();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _checkNow());
  }

  void _checkNow() {
    if (!kIsWeb) return;
    final now = DateTime.now(); // device local time — no UTC conversion needed
    debugPrint(
      '[WebNotif] CHECK at $now — watching ${_workspaces.length} workspaces',
    );

    for (final ws in _workspaces) {
      for (final section in ws.sections) {
        final sch = section.schedule;

        if (sch.startTime.isEmpty) continue;
        final parts = sch.startTime.split(':');
        if (parts.length < 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) continue;

        final remind = sch.reminderMinutes > 0 ? sch.reminderMinutes : 15;

        for (final day in sch.days) {
          final weekday = ScheduleUtils.weekdayFor(day.trim());
          if (weekday == null) continue;

          // FIX: Find the next upcoming fireAt for this weekday — don't just
          // use "today". If today's occurrence already passed, look at next week.
          // Previously classTime was always "today at HH:mm" which made diff
          // permanently ~hours-past when the class time had already passed today,
          // so the 0–60s window was never hit.
          final fireAt = _nextFireAt(
            now: now,
            weekday: weekday,
            hour: hour,
            minute: minute,
            reminderMinutes: remind,
          );

          final diff = now.difference(fireAt).inSeconds;

          debugPrint(
            '[WebNotif] ${section.name} day=$day | '
            'nextFire=$fireAt | diff=${diff}s',
          );

          // Fire if we are within the 60-second window of the reminder time
          if (diff >= 0 && diff < 60) {
            _fire(
              PendingNotification(
                sectionName: section.name.isNotEmpty ? section.name : 'Class',
                courseName: ws.title,
                startTime: sch.startTime,
                location: section.location,
                minutesUntil: remind,
                fireAt: fireAt,
              ),
            );
          }
        }
      }
    }
  }

  /// Returns the next DateTime when a reminder should fire for a given
  /// weekday + class time + reminder offset, relative to [now].
  ///
  /// Steps:
  /// 1. Start at today's date with the class hour:minute.
  /// 2. Walk forward (up to 7 days) until the weekday matches.
  /// 3. Subtract the reminder offset to get fireAt.
  /// 4. If fireAt is already in the past (even by 1 second), add 7 days
  ///    so we always return the NEXT upcoming occurrence.
  static DateTime _nextFireAt({
    required DateTime now,
    required int weekday,
    required int hour,
    required int minute,
    required int reminderMinutes,
  }) {
    // Start from today at class time
    var classTime = DateTime(now.year, now.month, now.day, hour, minute);

    // Advance to the correct weekday (0–6 iterations max)
    int safety = 0;
    while (classTime.weekday != weekday && safety < 7) {
      classTime = classTime.add(const Duration(days: 1));
      safety++;
    }

    var fireAt = classTime.subtract(Duration(minutes: reminderMinutes));

    // If this fire time is already past, jump to next week's occurrence
    if (fireAt.isBefore(now)) {
      fireAt = fireAt.add(const Duration(days: 7));
    }

    return fireAt;
  }

  void _fire(PendingNotification notif) {
    final already = activeNotifications.any(
      (n) =>
          n.sectionName == notif.sectionName &&
          n.fireAt.difference(notif.fireAt).inSeconds.abs() < 60,
    );
    if (already) return;
    debugPrint('[WebNotif] FIRED: ${notif.title}');
    activeNotifications.insert(0, notif);
    onChanged?.call();
  }
}
