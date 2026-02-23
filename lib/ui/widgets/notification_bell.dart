// lib/ui/widgets/notification_bell.dart
//
// Bell icon shown only on web (returns empty on mobile).
// No dart:js_interop — safe for APK builds.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../services/web_notification_service.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  final _overlayKey = GlobalKey();
  OverlayEntry? _overlay;
  late final AnimationController _shake;
  late final Animation<double> _shakeAnim;

  static const _primary = Color(0xFF7C5CBF);
  static const _ink = Color(0xFF2D2640);
  static const _inkLight = Color(0xFFABA6C0);
  static const _border = Color(0xFFE8E3F8);
  static const _soft = Color(0xFFEDE8FF);
  static const _red = Color(0xFFD93025);

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

    WebNotificationService.instance.onChanged = () {
      if (mounted) {
        setState(() {});
        _shake.forward(from: 0);
      }
    };
  }

  @override
  void dispose() {
    _overlay?.remove();
    _shake.dispose();
    WebNotificationService.instance.onChanged = null;
    super.dispose();
  }

  void _toggleDropdown() =>
      _overlay != null ? _closeDropdown() : _openDropdown();

  void _openDropdown() {
    final box = _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final size = box.size;

    _overlay = OverlayEntry(
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
    Overlay.of(context).insert(_overlay!);
  }

  void _closeDropdown() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    // On mobile this widget renders nothing — no web-only code runs
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
        onTap: _toggleDropdown,
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
                      color: _red,
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

  static const _primary = Color(0xFF7C5CBF);
  static const _ink = Color(0xFF2D2640);
  static const _inkMid = Color(0xFF6B6480);
  static const _inkLight = Color(0xFFABA6C0);
  static const _border = Color(0xFFE8E3F8);
  static const _soft = Color(0xFFEDE8FF);

  @override
  Widget build(BuildContext context) {
    final notifs = WebNotificationService.instance.activeNotifications;
    return Material(
      elevation: 12,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      shadowColor: const Color(0xFF7C5CBF).withOpacity(0.15),
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: _border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: const BoxDecoration(
                color: _soft,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_rounded,
                    color: _primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Upcoming Classes',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: _ink,
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
                          color: _primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: _border),
            if (notifs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: Color(0xFF00B896),
                      size: 32,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No upcoming reminders',
                      style: TextStyle(
                        color: Color(0xFFABA6C0),
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
                      const Divider(height: 1, color: _border),
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

  static const _primary = Color(0xFF7C5CBF);
  static const _soft = Color(0xFFEDE8FF);
  static const _ink = Color(0xFF2D2640);
  static const _inkMid = Color(0xFF6B6480);
  static const _inkLight = Color(0xFFABA6C0);

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
              color: _soft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: _primary,
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
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  notif.body,
                  style: const TextStyle(fontSize: 12, color: _inkMid),
                ),
                const SizedBox(height: 2),
                Text(
                  'Notified at $h:$m',
                  style: const TextStyle(fontSize: 11, color: _inkLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
