import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// 👉 THE FIX: Updated all of these import paths for the new folder structure!
import '../services/notifications/web_notification_service.dart';
import '../app_styles.dart'; 
import '../main.dart' show navigatorKey;
import 'notification_toast.dart';

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

    if (kIsWeb) WebNotificationService.instance.unlockAudio();

    // Register with the universal listener list — safe for multiple
    // bells mounted at once (home + workspace detail).
    WebNotificationService.instance.addListener(_onNotifChanged);
  }

  void _onNotifChanged() {
    if (!mounted) return;
    setState(() {});
    _shake.forward(from: 0);
    // On web: trigger overlay toast from the bell.
    // On mobile: toast already shown by MobileToastService — skip to avoid double.
    if (kIsWeb) {
      final notifs = WebNotificationService.instance.activeNotifications;
      if (notifs.isNotEmpty) _showWebToast(notifs.first);
    }
  }

  @override
  void dispose() {
    _dropdown?.remove();
    _shake.dispose();
    WebNotificationService.instance.removeListener(_onNotifChanged);
    super.dispose();
  }

  void _showWebToast(PendingNotification notif) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = navigatorKey.currentState?.overlay;
      if (overlay == null) return;
      showNotifToast(overlay: overlay, title: notif.title, body: notif.body);
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
    // ✅ NO kIsWeb guard — bell renders on BOTH web and mobile
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
          if (kIsWeb) WebNotificationService.instance.unlockAudio();
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
                color: count > 0 ? AppStyles.textPrimary : AppStyles.primary,
                size: 26,
              ),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppStyles.error, 
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5), 
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
      shadowColor: AppStyles.primary.withOpacity(0.15), 
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 400),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(color: AppStyles.borderLight), 
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: const BoxDecoration(
                color: AppStyles.mediumGray, 
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.notifications_rounded,
                    color: AppStyles.textPrimary, 
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Notifications',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppStyles.textPrimary, 
                      ),
                    ),
                  ),
                  if (notifs.isNotEmpty)
                    GestureDetector(
                      onTap: onClearAll,
                      child: const Text(
                        'Clear all',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppStyles.primary, 
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppStyles.borderLight), 
            if (notifs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppStyles.accent,
                      size: 32,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'No notifications yet',
                      style: TextStyle(
                        color: AppStyles.darkGray, 
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Reminders will appear here when they fire.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppStyles.darkGray, 
                        fontSize: 11,
                        height: 1.4,
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
                      const Divider(height: 1, color: AppStyles.borderLight), 
                  itemBuilder: (_, i) => _NotifTile(notif: notifs[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Notification tile ────────────────────────────────────────────────────────
class _NotifTile extends StatelessWidget {
  const _NotifTile({required this.notif});
  final PendingNotification notif;

  String _timeAgo(DateTime fireAt) {
    final diff = DateTime.now().difference(fireAt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppStyles.mediumGray, 
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: AppStyles.primary, 
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
                    color: AppStyles.textPrimary, 
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  notif.body,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppStyles.darkGray, 
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _timeAgo(notif.fireAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppStyles.darkGray, 
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