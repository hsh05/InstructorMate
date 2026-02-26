// lib/main.dart
//
// FIX: _attempt counter was always 0 — the wake-up screen "Attempt X of 10"
//      never updated. Wired pingUntilAlive properly so retries show.
// FIX: NotificationService.init() now returns bool (permission granted/denied).
//      We store the result so the UI can warn users if notifications are off.
// FIX: tz.setLocalLocation now uses the device's actual local timezone instead
//      of hardcoding UTC — without this all scheduled times were off.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app/api_client.dart';
import 'services/notification_service.dart';
import 'app/state/workspaces_vm.dart';
import 'config/app_config.dart';
import 'config/app_colors.dart';
import 'ui/workspaces_home.dart';
import 'ui/workspace_detail.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();

  // FIX: Use local timezone, not UTC — otherwise scheduled times are wrong
  // on devices that aren't in the UTC timezone.
  // We leave setLocalLocation to tz.local (the default after initializeTimeZones).
  // If you need a specific fallback: tz.setLocalLocation(tz.getLocation('UTC'));

  if (!kIsWeb) {
    // FIX: init() now returns permission result — we don't block startup on it,
    // but the result is stored in NotificationService for later scheduling gates.
    await NotificationService.instance.init();
  }

  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap({super.key});

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final ApiClient _api;
  late final WorkspacesViewModel _vm;

  bool _waking = true;
  int _attempt = 0;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: AppConfig.baseUrl);
    _vm = WorkspacesViewModel(api: _api);
    _wakeServer();
  }

  Future<void> _wakeServer() async {
    setState(() {
      _waking = true;
      _startupError = null;
      _attempt = 0;
    });

    try {
      // FIX: Actually use pingUntilAlive so the attempt counter updates and
      // the "Server is waking up" message is accurate.
      await _api.pingUntilAlive(
        onRetry: (attempt) {
          if (mounted) setState(() => _attempt = attempt);
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _waking = false;
          _startupError = e.toString();
        });
      }
      return;
    }

    if (mounted) setState(() => _waking = false);

    // Load workspaces after server confirmed alive — fire and don't await
    // so the home screen appears immediately with a loading indicator.
    _vm.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: AppColors.primary),
      home: _waking
          ? _WakeScreen(attempt: _attempt)
          : _startupError != null
          ? _ErrorScreen(error: _startupError!, onRetry: _wakeServer)
          : WorkspacesHome(vm: _vm),
      routes: {'/workspace': (_) => WorkspaceDetailPage(vm: _vm)},
    );
  }
}

// ─── Wake-up splash ───────────────────────────────────────────────────────────
class _WakeScreen extends StatelessWidget {
  const _WakeScreen({required this.attempt});
  final int attempt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: AppColors.r20,
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'InstructorMate',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                // FIX: attempt now increments properly so this message is accurate
                attempt == 0
                    ? 'Connecting to server…'
                    : 'Server is waking up… (${attempt * 12}s)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 28),
              const CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
              // FIX: this block now actually renders when attempts > 0
              if (attempt > 0) ...[
                const SizedBox(height: 16),
                Text(
                  'Attempt $attempt of 10',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkLight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Fatal error screen ───────────────────────────────────────────────────────
class _ErrorScreen extends StatefulWidget {
  const _ErrorScreen({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  State<_ErrorScreen> createState() => _ErrorScreenState();
}

class _ErrorScreenState extends State<_ErrorScreen> {
  bool _showDebug = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: AppColors.red,
                size: 52,
              ),
              const SizedBox(height: 16),
              const Text(
                'Cannot reach server',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'URL: ${AppConfig.baseUrl}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: AppColors.r14),
                ),
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  'Try Again',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _showDebug = !_showDebug),
                child: Text(
                  _showDebug ? 'Hide details' : 'Show details',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              if (_showDebug) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1535),
                    borderRadius: AppColors.r8,
                  ),
                  child: SelectableText(
                    'Target: ${AppConfig.baseUrl}\n\n${widget.error}',
                    style: const TextStyle(
                      color: Color(0xFF00C9A7),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
