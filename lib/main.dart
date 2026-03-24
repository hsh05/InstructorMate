import 'package:flutter/material.dart';
import 'screens/generate_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: GenerateScreen()
  ));
}