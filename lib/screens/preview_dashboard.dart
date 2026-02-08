import 'package:flutter/material.dart';
import 'package:instructor_mate/screens/workspace.dart';
void main() {
  runApp(const DashboardPreview());
}

class DashboardPreview extends StatelessWidget {
  const DashboardPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dashboard Preview',
      home: WorkspacesScreen(), // directly show your dashboard
    );
  }
}