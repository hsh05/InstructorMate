// lib/main.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app/api_client.dart';
import 'services//notification_service.dart';
import 'app/state/workspaces_vm.dart';
import 'config/app_config.dart';
import 'ui/workspaces_home.dart';
import 'ui/workspace_detail.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('UTC'));
  if (!kIsWeb) await NotificationService.instance.init();
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

  // Startup state
  bool _waking = true; // waiting for server ping
  int _attempt = 0; // retry count shown to user
  String? _startupError; // fatal error after all retries exhausted

  static const _primary = Color(0xFF7C5CBF);

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
      await _api.pingUntilAlive(
        onRetry: (attempt) => setState(() => _attempt = attempt),
      );
      // Server is up — load workspaces
      setState(() => _waking = false);
      _vm.load();
    } catch (e) {
      setState(() {
        _waking = false;
        _startupError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _primary),
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

  static const _primary = Color(0xFF7C5CBF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2FF),
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
                  color: const Color(0xFFEDE8FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.school_rounded,
                  color: _primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'InstructorMate',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D2640),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                attempt == 0
                    ? 'Connecting to server…'
                    : 'Server is waking up, please wait… (${attempt * 10}s)',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF7B748F)),
              ),
              const SizedBox(height: 28),
              const CircularProgressIndicator(color: _primary, strokeWidth: 3),
              if (attempt > 0) ...[
                const SizedBox(height: 16),
                Text(
                  'Attempt $attempt of 6',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFABA6C0),
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
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  static const _primary = Color(0xFF7C5CBF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F2FF),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFFD93025),
                size: 52,
              ),
              const SizedBox(height: 16),
              const Text(
                'Cannot reach server',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D2640),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF7B748F)),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text(
                  'Try Again',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
