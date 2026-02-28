import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


class LoginController {
  final TextEditingController email, password;

  LoginController(this.email, this.password);

  Future<bool> login() async {
    try {
      final csv = await rootBundle.loadString('lib/assets/users.csv');
      final inputEmail = email.text.trim().toLowerCase();
      final inputPassword = password.text.trim();

      // Split and clean lines properly
      final lines = csv.split('\n')
        .map((line) => line.trim())  // Remove whitespace from each line
        .where((line) => line.isNotEmpty)  // Remove empty lines
        .toList();

      // Skip header and check each line
      for (int i = 1; i < lines.length; i++) {
        final fields = lines[i].split(',');
        
        if (fields.length >= 2) {
          final csvEmail = fields[0].trim().toLowerCase();
          final csvPassword = fields[1].trim();
          
          if (csvEmail == inputEmail && csvPassword == inputPassword) {
            debugPrint('✅ Login successful for: $inputEmail');
            return true;
          }
        }
      }
      
      debugPrint('❌ Login failed - no match found');
      return false;
      
    } catch (e) {
      debugPrint('❌ Login error: $e');
      return false;
    }
  }
}