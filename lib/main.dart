import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:instructor_mate/screens/login_screen.dart';
import 'package:instructor_mate/screens/profile_screen.dart'; // import ProfileScreen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load dotenv from backend/.env
  await dotenv.load(fileName: ".env");

  runApp(const InstructorMateApp());
}

class InstructorMateApp extends StatelessWidget {
  const InstructorMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
      },
      // Profile needs a userId argument so it uses onGenerateRoute
      onGenerateRoute: (settings) {
        if (settings.name == '/profile') {
          final userId = settings.arguments as String; // make sure this matches your userId type
          return MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: userId),
          );
        }
        return null;
      },
    );
  }
}