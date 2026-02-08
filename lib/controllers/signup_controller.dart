import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SignupController {
  final TextEditingController name, email, password, confirmPassword;

  SignupController(this.name, this.email, this.password, this.confirmPassword);

  Future<bool> signup(String role) async {
    try {
      if (await _emailExists()) return false;
      
      debugPrint('=== SIGNUP (DEMO) ===');
      debugPrint('Name: ${name.text.trim()}');
      debugPrint('Email: ${email.text.trim()}');
      debugPrint('Role: $role');
      
      await Future.delayed(const Duration(seconds: 1));
      return true;
    } catch (e) {
      debugPrint('Signup error: $e');
      return false;
    }
  }

  Future<bool> _emailExists() async {
    try {
      final csv = await rootBundle.loadString('lib/assets/users.csv');
      final inputEmail = email.text.trim().toLowerCase();
      
      return csv.split('\n').skip(1).any((line) {
        final fields = line.split(',');
        return fields.isNotEmpty && fields[0].trim().toLowerCase() == inputEmail;
      });
    } catch (e) {
      return false;
    }
  }
}