// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart'; 
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data; 
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // 👉 FIX 1: Added this import

// --- UI Screens ---
import 'screens/workspace/workspace_home.dart'; 
import 'screens/workspace/workspace_detail.dart';
import 'screens/auth/login_screen.dart';
import 'screens/profile_screen.dart';

// --- API, Services, and State Management ---
import 'services/api_service.dart';
import 'services/auth_service.dart'; 
import 'services/notifications/in_app_queue.dart'; 
import 'state/workspaces_vm.dart';   
import 'state/auth_vm.dart'; 

import 'app_styles.dart';    

// 1. The Global Navigator Key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the timezone database and set device local timezone
  tz_data.initializeTimeZones();
  try {
    final currentTimeZone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(currentTimeZone.identifier));
  } catch (e) {
    debugPrint('Could not set local timezone: $e');
  }

  // Start the desktop background clock
  InAppQueue.startTimer();

  // Load dotenv from assets
  await dotenv.load(fileName: ".env");

  // Initialize Google Sign-In before the app boots!
  await AuthService().initialize();

  // 👉 NEW: Check for an existing login session before booting!
  const storage = FlutterSecureStorage();
  final userId = await storage.read(key: 'user_id');
  final String startRoute = (userId != null && userId.isNotEmpty) ? '/home' : '/login';

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => WorkspacesViewModel(api: ApiService()),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(),
        ),
      ],
      // 👉 FIX 2: Removed 'const' and passed the startRoute variable
      child: InstructorMateApp(initialRoute: startRoute), 
    ),
  );
}

class InstructorMateApp extends StatelessWidget {
  final String initialRoute; 
  
  const InstructorMateApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstructorMate',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      
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

      // Use the dynamic route passed into the app
      initialRoute: initialRoute,

      // Define the static routes for navigation
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const WorkspacesHome(),
        '/workspace': (context) => const WorkspaceDetailPage(),
      },

      // Dynamic routes (Profile now has access to the provider tree)
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