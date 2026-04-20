// lib/ui/widgets/notification_toast.dart
//
// Shared in-app notification popup used by BOTH platforms:
//   • Web  — triggered by WebNotificationService via NotificationBell.onChanged
//   • Mobile — triggered by MobileToastService when OS delivers a foreground notif
//
// Exported publicly so both callers can use NotifToast directly.

import 'package:flutter/material.dart';
import '../../app_styles.dart'; // Ensure this points to the right path

// ── Public helper — insert toast into the global overlay ─────────────────────
// Pass the navigatorKey overlay. Works from any context, any page.
void showNotifToast({
  required OverlayState overlay,
  required String title,
  required String body,
}) {
  OverlayEntry? entry;
  entry = OverlayEntry(
    builder: (_) => Directionality(
      textDirection: TextDirection.ltr,
      child: NotifToast(
        title: title,
        body: body,
        onDismiss: () {
          entry?.remove();
          entry = null;
        },
      ),
    ),
  );
  overlay.insert(entry!);
}

// ── Toast widget ──────────────────────────────────────────────────────────────
class NotifToast extends StatefulWidget {
  const NotifToast({
    super.key,
    required this.title,
    required this.body,
    required this.onDismiss,
  });

  final String title;
  final String body;
  final VoidCallback onDismiss;

  @override
  State<NotifToast> createState() => _NotifToastState();
}

class _NotifToastState extends State<NotifToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  static const _toastDuration = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(_toastDuration, () {
      if (mounted) _dismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    _ctrl.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dim backdrop — draws the eye immediately
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _fade,
              builder: (_, __) => Container(
                color: Colors.black.withOpacity(0.18 * _fade.value),
              ),
            ),
          ),
        ),
        // Centered card
        Positioned.fill(
          child: Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: 0.7 + 0.3 * _scale.value,
                  child: child,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 340,
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppStyles.primary.withOpacity(0.22), // Mapped
                        blurRadius: 48,
                        offset: const Offset(0, 16),
                        spreadRadius: 4,
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Gradient header ───────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppStyles.primaryDark, // Mapped
                                Color(0xFF9B78E0),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            children: [
                              _PulsingBell(),
                              const SizedBox(height: 14),
                              const Text(
                                'CLASS REMINDER',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white70,
                                  letterSpacing: 2.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Body ──────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                          child: Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppStyles.mediumGray, // Mapped
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppStyles.primary.withOpacity(0.15), // Mapped
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: const Icon(
                                        Icons.school_rounded,
                                        color: AppStyles.primary, // Mapped
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        widget.body,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppStyles.textPrimary, // Mapped
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: _dismiss,
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppStyles.lightGray, // Mapped
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Got it',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppStyles.darkGray, // Mapped
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ── Progress bar ──────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                          child: _ToastProgressBar(
                            duration: _toastDuration,
                            color: AppStyles.primary, // Mapped
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Animated ringing bell ─────────────────────────────────────────────────────
class _PulsingBell extends StatefulWidget {
  @override
  State<_PulsingBell> createState() => _PulsingBellState();
}

class _PulsingBellState extends State<_PulsingBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _ring;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _ring = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.15, end: 0.15), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: -0.10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.10, end: 0.10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.10, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _ctrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _ctrl.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ring,
      builder: (_, child) => Transform.rotate(angle: _ring.value, child: child),
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 2),
        ),
        child: const Icon(
          Icons.notifications_active_rounded,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }
}

// ── Draining progress bar ─────────────────────────────────────────────────────
class _ToastProgressBar extends StatefulWidget {
  const _ToastProgressBar({required this.duration, required this.color});
  final Duration duration;
  final Color color;

  @override
  State<_ToastProgressBar> createState() => _ToastProgressBarState();
}

class _ToastProgressBarState extends State<_ToastProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => LinearProgressIndicator(
        value: 1 - _ctrl.value,
        backgroundColor: widget.color.withOpacity(0.15),
        valueColor: AlwaysStoppedAnimation(widget.color),
        minHeight: 4,
      ),
    );
  }
}