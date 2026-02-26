// lib/services/web_notification_service.dart
//
// Works on ALL platforms (web + Android + iOS).
// Browser JS calls are only made when kIsWeb is true at runtime.
//
// FIX: Removed duplicated _dayMap — now uses shared ScheduleUtils.dayMap.
// FIX: Notification body uses ScheduleUtils.formatTime for 12-h AM/PM display.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, VoidCallback;

import '../app/workspace_models.dart';
import '../utils/schedule_utils.dart';

// ─── Model ────────────────────────────────────────────────────────────────────
class PendingNotification {
  final String sectionName;
  final String courseName;
  final String startTime; // raw HH:mm stored for dedup
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
    // FIX: show 12-h AM/PM time
    final friendlyTime = ScheduleUtils.formatTime(startTime);
    return '$sectionName$loc — $friendlyTime';
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────
class WebNotificationService {
  WebNotificationService._();
  static final WebNotificationService instance = WebNotificationService._();

  Timer? _ticker;
  final List<PendingNotification> activeNotifications = [];
  int get unreadCount => activeNotifications.length;
  VoidCallback? onChanged;

  Future<void> init(List<Workspace> workspaces) async {
    if (!kIsWeb) return;
    _startTicker(workspaces);
  }

  void dispose() => _ticker?.cancel();

  void clearAll() {
    activeNotifications.clear();
    onChanged?.call();
  }

  void updateWorkspaces(List<Workspace> workspaces) {
    _ticker?.cancel();
    _startTicker(workspaces);
  }

  void _startTicker(List<Workspace> workspaces) {
    _checkNow(workspaces);
    _ticker = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkNow(workspaces),
    );
  }

  void _checkNow(List<Workspace> workspaces) {
    if (!kIsWeb) return;
    final now = DateTime.now();
    for (final ws in workspaces) {
      for (final section in ws.sections) {
        final sch = section.schedule;
        final parts = sch.startTime.split(':');
        if (parts.length < 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) continue;

        for (final day in sch.days) {
          // FIX: use shared ScheduleUtils instead of local _dayMap
          final weekday = ScheduleUtils.weekdayFor(day);
          if (weekday == null || now.weekday != weekday) continue;

          final classTime = DateTime(
            now.year,
            now.month,
            now.day,
            hour,
            minute,
          );
          final remind = sch.reminderMinutes > 0 ? sch.reminderMinutes : 15;
          final fireAt = classTime.subtract(Duration(minutes: remind));
          final diff = now.difference(fireAt).inSeconds;

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

  void _fire(PendingNotification notif) {
    final already = activeNotifications.any(
      (n) =>
          n.sectionName == notif.sectionName &&
          n.fireAt.difference(notif.fireAt).inSeconds.abs() < 60,
    );
    if (already) return;
    activeNotifications.insert(0, notif);
    onChanged?.call();
  }
}
