// lib/main.dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'app/api_client.dart';
import 'services/notification_service.dart';
import 'app/state/workspaces_vm.dart';
import 'ui/workspaces_home.dart';
import 'ui/workspace_detail.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Timezone database — needed for mobile scheduled notifications
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('UTC'));

  // Mobile notifications init (no-op on web)
  if (!kIsWeb) {
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
  late final WorkspacesViewModel vm;

  @override
  void initState() {
    super.initState();
    final api = ApiClient(baseUrl: 'http://192.168.1.202:8000');
    vm = WorkspacesViewModel(api: api);
    vm.load(); // triggers both mobile scheduling + web notification init
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (_) => WorkspacesHome(vm: vm),
        '/workspace': (_) => WorkspaceDetailPage(vm: vm),
      },
    );
  }
}
