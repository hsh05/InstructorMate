import 'package:flutter/material.dart';
import 'package:instructor_mate/screens/workspace.dart';
void main() {
  runApp(const InstructorMateApp());
}

class InstructorMateApp extends StatelessWidget {
  const InstructorMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
home: WorkspacesScreen(),
    );
  }
}