// lib/main.dart
import 'package:flutter/material.dart';

import 'app/api_client.dart';
import 'app/state/workspaces_vm.dart';
import 'ui/workspaces_home.dart';
import 'ui/workspace_detail.dart';

void main() => runApp(const _Bootstrap());

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
    final api = ApiClient(baseUrl:"http://127.0.0.1:8000");
    vm = WorkspacesViewModel(api: api);
    vm.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: {
        "/": (_) => WorkspacesHome(vm: vm),
        "/workspace": (_) => WorkspaceDetailPage(vm: vm),
      },
    );
  }
}
