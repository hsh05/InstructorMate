import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// --- UI Screens ---
// 👉 THE FIX: Updated to point to the correct workspaces_home.dart file
import 'screens/workspace/workspace_home.dart'; 
import 'screens/workspace/workspace_detail.dart';
import 'screens/auth/login_screen.dart';
import 'screens/profile_screen.dart';

// --- API, Services, and State Management ---
import 'services/api_service.dart';
import 'services/auth_service.dart'; // 👉 THE FIX: Added so we can init Google Auth
import 'state/workspaces_vm.dart';   // 👉 THE FIX: Updated to the new state/ folder path

import 'app_styles.dart';            // 👉 THE FIX: Removed the slash

// 1. The Global Navigator Key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load dotenv from assets
  await dotenv.load(fileName: ".env");

  // 👉 THE FIX: Initialize Google Sign-In before the app boots!
  await AuthService().initialize();

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
    final apiService = ApiService(); 
    _workspacesVM = WorkspacesViewModel(api: apiService);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstructorMate',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      
      // 👉 Inject AppStyles globally here!
      theme: ThemeData(
        primaryColor: AppStyles.primary,
        scaffoldBackgroundColor: AppStyles.lightGray,
        colorScheme: const ColorScheme.light(
          primary: AppStyles.primary,
          secondary: AppStyles.accent,
          error: AppStyles.error,
          surface: AppStyles.white,
        ),
        textTheme: const TextTheme(
          displayLarge: AppStyles.headingLarge,
          displayMedium: AppStyles.headingMedium,
          displaySmall: AppStyles.headingSmall,
          bodyLarge: AppStyles.bodyLarge,
          bodyMedium: AppStyles.bodyMedium,
          bodySmall: AppStyles.bodySmall,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: AppStyles.elevatedButtonStyle,
        ),
      ),

      initialRoute: '/login',

      // 4. Define the static routes for navigation
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => WorkspacesHome(vm: _workspacesVM),
        '/workspace': (context) => WorkspaceDetailPage(vm: _workspacesVM),
      },

      // 5. Dynamic routes (Profile needs a userId argument)
      onGenerateRoute: (settings) {
        if (settings.name == '/profile') {
          final userId = settings.arguments as String; 
          return MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: userId),
          );
        }
        return null;
      },
    );
  }
}