// lib/state/auth_vm.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class AuthViewModel extends ChangeNotifier {
  bool isLoading = false;
  String? error;

  // ─── SIGNUP ─────────────────────────────────────────────────────────────────
  Future<bool> signUp(String email, String password, String name) async {
    isLoading = true;
    error = null;
    notifyListeners(); // Tells the UI to START the spinner

    try {
      // Calls the kitchen (AuthService)
      final success = await AuthService.signUp(email, password, name);
      if (!success) {
        error = "Signup failed. Please check your details or try a different email.";
      }
      return success;
    } catch (e) {
      debugPrint("AuthVM Signup Exception: $e");
      error = "A network error occurred. Please try again.";
      return false;
    } finally {
      isLoading = false;
      notifyListeners(); // 👉 Tells the UI to STOP the spinner, no matter what!
    }
  }

  // ─── LOGIN ──────────────────────────────────────────────────────────────────
  Future<bool> login(String email, String password) async {
    isLoading = true;
    error = null;
    notifyListeners(); // Tells the UI to START the spinner

    try {
      // Calls the kitchen (AuthService)
      final success = await AuthService.login(email, password);
      if (!success) {
        error = "Invalid email or password.";
      }
      return success;
    } catch (e) {
      debugPrint("AuthVM Login Exception: $e");
      error = "A network error occurred. Please try again.";
      return false;
    } finally {
      isLoading = false;
      notifyListeners(); // 👉 Tells the UI to STOP the spinner, no matter what!
    }
  }

  // ─── LOGOUT ─────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    isLoading = true;
    error = null;
    notifyListeners(); 

    try {
      await AuthService.logout();
    } catch (e) {
      debugPrint("AuthVM Logout Exception: $e");
    } finally {
      isLoading = false;
      notifyListeners(); 
    }
  }

  // ─── UTILITIES ──────────────────────────────────────────────────────────────
  
  /// Call this to manually clear any error messages from the UI 
  /// (for example, when the user starts typing a new password)
  void clearError() {
    if (error != null) {
      error = null;
      notifyListeners();
    }
  }
}