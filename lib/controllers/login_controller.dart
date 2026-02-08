import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class LoginController {
  final TextEditingController emailController;
  final TextEditingController passwordController;

  LoginController({
    required this.emailController,
    required this.passwordController,
  });

  bool validateInput() {
    final email = emailController.text;
    final password = passwordController.text;

    if (email.isEmpty || !email.contains('@')) return false;
    if (password.isEmpty || password.length < 6) return false;

    return true;
  }

  /// New login method that checks credentials against users.csv
  Future<bool> login() async {
    if (!validateInput()) return false;

    // Load CSV from assets
    final csvContent = await rootBundle.loadString('lib/assets/users.csv');
    final lines = csvContent.split('\n');

    final inputEmail = emailController.text.trim();
    final inputPassword = passwordController.text.trim();

    for (var line in lines) {
      final fields = line.split(',');
      if (fields.length < 2) continue; // skip invalid lines

      final csvEmail = fields[0].trim();
      final csvPassword = fields[1].trim();

      if (csvEmail == inputEmail && csvPassword == inputPassword) {
        return true; // found a match
      }
    }

    return false; // no match
  }
}