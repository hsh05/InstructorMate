import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// --- UI Screens ---
import 'screens/workspaces_home.dart';
import 'screens/workspace_detail.dart';
import 'screens/login_screen.dart';
import 'screens/profile_screen.dart';

// --- API and State Management ---
import 'services/api_service.dart';
import 'app/state/workspaces_vm.dart';

import '/app_styles.dart';

// 1. The Global Navigator Key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load dotenv from backend/.env
  await dotenv.load(fileName: ".env");

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

    _workspacesVM.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstructorMate',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      
      // 👉 Inject AppStyles globally here!
      theme: ThemeData(
        primaryColor: AppStyles.primaryPurple,
        scaffoldBackgroundColor: AppStyles.lightGray,
        colorScheme: const ColorScheme.light(
          primary: AppStyles.primaryPurple,
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