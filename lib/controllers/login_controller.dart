import 'package:flutter/material.dart';

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

  Future<bool> login() async {
    await Future.delayed(const Duration(seconds: 2));
    return validateInput();
  }
}