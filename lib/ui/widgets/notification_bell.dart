// lib/ui/widgets/notification_bell.dart
//
// Bell icon shown only on web (returns empty on mobile).
// No dart:js_interop — safe for APK builds.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../services/web_notification_service.dart';
import '../../config/app_colors.dart';
import '../../main.dart' show navigatorKey;

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  final _overlayKey = GlobalKey();
  OverlayEntry? _dropdown;
  late final AnimationController _shake;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeInOut));

    // Unlock audio on the very first user interaction with the bell.
    // Browser autoplay policy requires this before AudioContext can play.
    WebNotificationService.instance.unlockAudio();

    WebNotificationService.instance.onChanged = () {
      if (!mounted) return;
      setState(() {});
      _shake.forward(from: 0);
      final notifs = WebNotificationService.instance.activeNotifications;
      if (notifs.isNotEmpty) _showToast(notifs.first);
    };
  }

  @override
  void dispose() {
    _dropdown?.remove();
    _shake.dispose();
    WebNotificationService.instance.onChanged = null;
    super.dispose();
  }

  void _showToast(PendingNotification notif) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = navigatorKey.currentState?.overlay;
      if (overlay == null) return;
      OverlayEntry? entry;
      entry = OverlayEntry(
        builder: (_) => Directionality(
          textDirection: TextDirection.ltr,
          child: _NotifToast(
            notif: notif,
            onDismiss: () {
              entry?.remove();
              entry = null;
            },
          ),
        ),
      );
      overlay.insert(entry!);
    });
  }

  void _toggleDropdown() =>
      _dropdown != null ? _closeDropdown() : _openDropdown();

  void _openDropdown() {
    final box = _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;

    _dropdown = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeDropdown,
              behavior: HitTestBehavior.translucent,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: pos.dy + size.height + 8,
            right: 8,
            child: _DropdownPanel(
              onDismiss: _closeDropdown,
              onClearAll: () {
                WebNotificationService.instance.clearAll();
                _closeDropdown();
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_dropdown!);
  }

  void _closeDropdown() {
    _dropdown?.remove();
    _dropdown = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return const SizedBox.shrink();
    final count = WebNotificationService.instance.unreadCount;
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(_shakeAnim.value, 0),
        child: child,
      ),
      child: GestureDetector(
        key: _overlayKey,
        onTap: () {
          WebNotificationService.instance.unlockAudio();
          _toggleDropdown();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                count > 0
                    ? Icons.notifications_rounded
                    : Icons.notifications_none_rounded,
                color: count > 0 ? Colors.white : Colors.white70,
                size: 26,
              ),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppColors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dropdown panel ───────────────────────────────────────────────────────────
class _DropdownPanel extends StatelessWidget {
  const _DropdownPanel({required this.onDismiss, required this.onClearAll});
  final VoidCallback onDismiss;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final notifs = WebNotificationService.instance.activeNotifications;
    return Material(
      elevation: 12,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      shadowColor: AppColors.primary.withOpacity(0.15),
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Upcoming Classes',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  if (notifs.isNotEmpty)
                    GestureDetector(
                      onTap: onClearAll,
                      child: const Text(
                        'Clear all',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            if (notifs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppColors.accent,
                      size: 32,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No upcoming reminders',
                      style: TextStyle(
                        color: AppColors.inkLight,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: notifs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) => _NotifTile(notif: notifs[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.notif});
  final PendingNotification notif;

  @override
  Widget build(BuildContext context) {
    final h = notif.fireAt.hour.toString().padLeft(2, '0');
    final m = notif.fireAt.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notif.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  notif.body,
                  style: const TextStyle(fontSize: 12, color: AppColors.inkMid),
                ),
                const SizedBox(height: 2),
                Text(
                  'Notified at $h:$m',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Center-screen professional notification popup ────────────────────────────
// Appears centered on screen, styled like a mobile push notification card.
// Returns a Stack so Positioned is valid inside OverlayEntry.
class _NotifToast extends StatefulWidget {
  const _NotifToast({required this.notif, required this.onDismiss});
  final PendingNotification notif;
  final VoidCallback onDismiss;

  @override
  State<_NotifToast> createState() => _NotifToastState();
}

class _NotifToastState extends State<_NotifToast>
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
        // Semi-transparent backdrop to draw the eye
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
                        color: AppColors.primary.withOpacity(0.22),
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
                        // ── Header gradient band ──────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primaryDark,
                                Color(0xFF9B78E0),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            children: [
                              // Animated bell icon
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
                                widget.notif.title,
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
                        // ── Body ─────────────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                          child: Column(
                            children: [
                              // Section + location row
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(
                                          0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(11),
                                      ),
                                      child: const Icon(
                                        Icons.school_rounded,
                                        color: AppColors.primary,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        widget.notif.body,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.ink,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Dismiss button
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: _dismiss,
                                  style: TextButton.styleFrom(
                                    backgroundColor: AppColors.surfaceAlt,
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
                                      color: AppColors.inkMid,
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
                            color: AppColors.primary,
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

// Animated pulsing bell icon for the toast header
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
      TweenSequenceItem(tween: Tween(begin: 0.15, end: -0.1), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.1), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.1, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    // Ring twice with a gap
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
