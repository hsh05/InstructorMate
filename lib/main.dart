import 'package:flutter/material.dart';

// --- Your New UI Screens ---
import 'ui/workspaces_home.dart';
import 'ui/workspace_detail.dart';

// --- Your API and State Management ---
import 'services/api_service.dart';
import 'app/state/workspaces_vm.dart';

// --- Your Original Screens ---
import 'screens/generate_screen.dart';

// 1. The Global Navigator Key (Kept exactly as you had it!)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const InstructorMateApp());
}

class InstructorMateApp extends StatefulWidget {
  const InstructorMateApp({super.key});

  @override
  State<InstructorMateApp> createState() => _InstructorMateAppState();
}

class _InstructorMateAppState extends State<InstructorMateApp> {
  // 2. Initialize your ViewModel
  late final WorkspacesViewModel _workspacesVM;

  @override
  void initState() {
    super.initState();
    // Use the new class name here:
    final apiService = ApiService(); 
    _workspacesVM = WorkspacesViewModel(api: apiService);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstructorMate',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,

      // 3. Set WorkspacesHome as the first screen the user sees
      home: WorkspacesHome(vm: _workspacesVM),

      // 4. Define the routes for navigation
      routes: {
        '/workspace': (context) => WorkspaceDetailPage(vm: _workspacesVM),
        '/generate': (context) => const GenerateScreen(), // Your original screen is safe here!
      },
    );
  }
}