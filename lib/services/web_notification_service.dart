// lib/services/web_notification_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, VoidCallback, debugPrint;

import '../app/workspace_models.dart';
import '../utils/schedule_utils.dart';

// Web Audio API access via dart:js_interop (no dart:html needed — works in
// both legacy and modern Flutter web compilers).
import 'dart:js_interop';

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

// ─── Minimal JS interop bindings for Web Audio API ───────────────────────────
// We only need what's required to synthesize a bell chime.

@JS('AudioContext')
@staticInterop
class _AudioContext {
  external factory _AudioContext();
}

extension _AudioContextExt on _AudioContext {
  external JSObject createOscillator();
  external JSObject createGain();
  external JSObject get destination;
  external double get currentTime;
  external JSPromise resume();
}

extension _NodeExt on JSObject {
  // OscillatorNode
  external set type(JSString v);
  external JSObject get frequency;
  // GainNode
  external JSObject get gain;
  // AudioParam (frequency / gain)
  external void setValueAtTime(double value, double time);
  external void exponentialRampToValueAtTime(double value, double endTime);
  external void linearRampToValueAtTime(double value, double endTime);
  // AudioNode
  external void connect(JSObject destination);
  external void start([double when]);
  external void stop([double when]);
}

// ─── Service ──────────────────────────────────────────────────────────────────
class WebNotificationService {
  WebNotificationService._();
  static final WebNotificationService instance = WebNotificationService._();

  Timer? _ticker;
  List<Workspace> _workspaces = [];

  final List<PendingNotification> activeNotifications = [];
  int get unreadCount => activeNotifications.length;
  VoidCallback? onChanged;

  // ── Audio context — created once, unlocked on first user gesture ───────────
  _AudioContext? _audioCtx;
  bool _audioUnlocked = false;

  /// Call this from any tap/click handler (e.g. the bell button onTap).
  /// Browsers require a user gesture before AudioContext can play sound.
  /// Once unlocked it stays unlocked for the session.
  void unlockAudio() {
    if (!kIsWeb || _audioUnlocked) return;
    try {
      _audioCtx ??= _AudioContext();
      _audioCtx!.resume();
      _audioUnlocked = true;
      debugPrint('[WebNotif] Audio unlocked');
    } catch (e) {
      debugPrint('[WebNotif] Audio unlock failed: $e');
    }
  }

  // ── Init / update ──────────────────────────────────────────────────────────

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
    final now = DateTime.now();
    debugPrint(
      '[WebNotif] CHECK at $now — watching ${_workspaces.length} workspaces',
    );

    for (final ws in _workspaces) {
      for (final section in ws.sections) {
        final sch = section.schedule;
        if (sch.startTime.isEmpty) continue;

        final parsed = _parseHHmm(sch.startTime);
        if (parsed == null) {
          debugPrint(
            '[WebNotif] SKIP ${section.name} — unparseable startTime="${sch.startTime}"',
          );
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
          debugPrint(
            '[WebNotif] ${section.name} day=$day | nextFire=$fireAt | diff=${diff}s',
          );

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

  // ── Sound ──────────────────────────────────────────────────────────────────

  /// Plays a gentle 3-note bell chime using the Web Audio API.
  /// Synthesized entirely in code — no audio file required.
  /// Notes: E5 (659 Hz) → G#5 (830 Hz) → B5 (988 Hz), each 0.18s apart.
  void _playBellChime() {
    if (!kIsWeb || !_audioUnlocked) return;
    try {
      final ctx = _audioCtx!;
      final now = ctx.currentTime;

      // Three ascending bell tones
      final notes = [659.0, 830.0, 988.0];
      for (var i = 0; i < notes.length; i++) {
        final t = now + i * 0.18;

        // Oscillator — sine wave for a clean bell tone
        final osc = ctx.createOscillator();
        osc.type = 'sine'.toJS;
        osc.frequency.setValueAtTime(notes[i], t);

        // Gain envelope: fast attack, slow exponential decay (bell-like)
        final gain = ctx.createGain();
        gain.gain.setValueAtTime(0.0, t);
        gain.gain.linearRampToValueAtTime(0.45, t + 0.01); // 10ms attack
        gain.gain.exponentialRampToValueAtTime(0.001, t + 1.2); // 1.2s decay

        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(t);
        osc.stop(t + 1.3);
      }
      debugPrint('[WebNotif] Bell chime played');
    } catch (e) {
      debugPrint('[WebNotif] Sound failed (non-fatal): $e');
    }
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
    if (secondsPast >= 60) {
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
    _playBellChime(); // 🔔 play sound
    onChanged?.call();
  }
}
