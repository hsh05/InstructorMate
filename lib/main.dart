// lib/main.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app/api_client.dart';
import 'services/notification_service.dart';
import 'app/state/workspaces_vm.dart';
import 'config/app_config.dart';
import 'config/app_colors.dart';
import 'ui/workspaces_home.dart';
import 'ui/workspace_detail.dart';

// Global navigator key so the toast can insert into the overlay
// from anywhere — even when WorkspacesHome is not in the tree.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz_data.initializeTimeZones();
  if (!kIsWeb) {
    try {
      final deviceTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTz));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

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

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: AppConfig.baseUrl);
    _vm = WorkspacesViewModel(api: _api);
    _vm.load();

    // Toast is triggered from NotificationBell.onChanged — see notification_bell.dart
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: AppColors.primary),
      home: WorkspacesHome(vm: _vm),
      routes: {'/workspace': (_) => WorkspaceDetailPage(vm: _vm)},
    );
  }
}
