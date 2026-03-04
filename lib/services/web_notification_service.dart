// lib/services/web_notification_service.dart
//
// CHANGE: Now works as a UNIVERSAL notification history store on BOTH
// platforms, not just web.
// - Web: timer-based ticker fires toasts automatically (unchanged)
// - Mobile: MobileToastService.show() and notificationBackgroundHandler
//   both call WebNotificationService.instance.addMobileNotif() to record
//   the notification so the bell history is populated on mobile too.
// - kIsWeb guard removed from _fire() so history is stored on both.
// - playBellChime() still only called on web (mobile uses ringtone player).
// - unlockAudio() still web-only.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, VoidCallback, debugPrint;

import '../app/workspace_models.dart';
import '../utils/schedule_utils.dart';

import 'web_audio_stub.dart' if (dart.library.js_interop) 'web_audio_impl.dart';

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
  List<Workspace> _workspaces = [];

  // Universal notification history — populated on BOTH web and mobile.
  final List<PendingNotification> activeNotifications = [];
  int get unreadCount => activeNotifications.length;

  // Multiple bells can be mounted simultaneously (home + workspace detail).
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback cb) {
    if (!_listeners.contains(cb)) _listeners.add(cb);
  }

  void removeListener(VoidCallback cb) {
    _listeners.remove(cb);
  }

  void _notifyListeners() {
    for (final cb in List.of(_listeners)) cb();
  }

  // Legacy single-setter kept for compatibility — maps into list.
  set onChanged(VoidCallback? cb) {
    if (cb != null && !_listeners.contains(cb)) _listeners.add(cb);
  }

  // ── Audio unlock (web only) ────────────────────────────────────────────────
  void unlockAudio() {
    if (!kIsWeb) return;
    unlockWebAudio();
  }

  // ── Init / update (web ticker) ─────────────────────────────────────────────

  Future<void> init(List<Workspace> workspaces) async {
    if (!kIsWeb) return;
    _workspaces = List.of(workspaces);
    _ticker?.cancel();
    _startTicker();
  }

  void dispose() => _ticker?.cancel();

  void clearAll() {
    activeNotifications.clear();
    _notifyListeners();
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
    final now = DateTime.now();

    for (final ws in _workspaces) {
      for (final section in ws.sections) {
        final sch = section.schedule;
        if (sch.startTime.isEmpty) continue;

        final parsed = _parseHHmm(sch.startTime);
        if (parsed == null) {
          continue;
        }
        final hour = parsed.$1;
        final minute = parsed.$2;
        final remind = sch.reminderMinutes > 0 ? sch.reminderMinutes : 15;

        for (final day in sch.days) {
          final weekday = ScheduleUtils.weekdayFor(day.trim());
          if (weekday == null) continue;

          final fireAt = _nextFireAt(
            now: now,
            weekday: weekday,
            hour: hour,
            minute: minute,
            reminderMinutes: remind,
          );

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

  // ── Called by mobile (MobileToastService + background handler) ─────────────
  // Records the notification in history so the bell badge appears on mobile.
  void addMobileNotif({
    required String title,
    required String body,
    required DateTime fireAt,
  }) {
    // Parse title: "⏰ CourseName starts in Nmin"
    // Parse body:  "SectionName @ Location — HH:MM AM"
    // We store a synthetic PendingNotification for history display.
    final notif = PendingNotification(
      sectionName: body.split(' — ').first.split(' @ ').first.trim(),
      courseName: title
          .replaceAll('⏰ ', '')
          .replaceAll(RegExp(r' starts in \d+min'), '')
          .trim(),
      startTime: body.contains(' — ') ? body.split(' — ').last.trim() : '',
      location: body.contains(' @ ')
          ? body.split(' @ ').last.split(' — ').first.trim()
          : '',
      minutesUntil: _extractMinutes(title),
      fireAt: fireAt,
    );
    _fire(notif);
  }

  static int _extractMinutes(String title) {
    final match = RegExp(r'(\d+)min').firstMatch(title);
    return match != null ? int.tryParse(match.group(1) ?? '10') ?? 10 : 10;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static (int, int)? _parseHHmm(String raw) {
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
    return (hour24, m);
  }

  static DateTime _nextFireAt({
    required DateTime now,
    required int weekday,
    required int hour,
    required int minute,
    required int reminderMinutes,
  }) {
    var classTime = DateTime(now.year, now.month, now.day, hour, minute);
    int safety = 0;
    while (classTime.weekday != weekday && safety < 7) {
      classTime = classTime.add(const Duration(days: 1));
      safety++;
    }
    var fireAt = classTime.subtract(Duration(minutes: reminderMinutes));
    final secondsPast = now.difference(fireAt).inSeconds;
    if (secondsPast >= 60) fireAt = fireAt.add(const Duration(days: 7));
    return fireAt;
  }

  void _fire(PendingNotification notif) {
    final already = activeNotifications.any(
      (n) =>
          n.sectionName == notif.sectionName &&
          n.fireAt.difference(notif.fireAt).inSeconds.abs() < 60,
    );
    if (already) return;
    activeNotifications.insert(0, notif);
    if (kIsWeb) playBellChime(); // web audio only
    _notifyListeners();
  }
}
