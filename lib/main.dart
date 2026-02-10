// lib/main.dart
import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'app/api_client.dart';
import 'app/state/syllabus_vm.dart';
import 'ui/syllabus_home.dart';

void main() => runApp(const SyllabusApp());

class SyllabusApp extends StatelessWidget {
  const SyllabusApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6D5EF6);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      surface: const Color(0xFFFCFAFF),
      background: const Color(0xFFF7F2FF),
    );

    return MaterialApp(
      title: 'Syllabus Q&A',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFFF7F2FF),
        visualDensity: VisualDensity.standard,
        appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
        snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
        dividerTheme: const DividerThemeData(space: 1),
      ),
      home: SyllabusHome(
        vm: SyllabusViewModel(
          api: ApiClient(baseUrl: AppConfig.baseUrl),
        )..init(),
      ),
    );
  }
}
