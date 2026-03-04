// lib/services/mobile_toast_service.dart

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart' show navigatorKey;
import '../ui/widgets/notification_toast.dart';

class MobileToastService {
  MobileToastService._();

  static void show({required String title, required String body}) {
    if (kIsWeb) return;

    // Use SchedulerBinding which is available earlier than WidgetsBinding.
    // addPostFrameCallback fires after the current frame completes —
    // safe even if called during app startup or from a notification callback.
    void doShow() {
      try {
        final overlay = navigatorKey.currentState?.overlay;
        if (overlay == null) {
          debugPrint('[MobileToast] overlay not ready — skipped');
          return;
        }
        // Play sound — wrapped separately so a sound failure never blocks the toast
        try {
          SystemSound.play(SystemSoundType.alert);
        } catch (e) {
          debugPrint('[MobileToast] sound failed (non-fatal): $e');
        }
        showNotifToast(overlay: overlay, title: title, body: body);
        debugPrint('[MobileToast] Showed: $title');
      } catch (e) {
        debugPrint('[MobileToast] show failed: $e');
      }
    }

    // If the scheduler is already in a frame, post to next frame.
    // If not (e.g. cold start), post immediately via addPostFrameCallback.
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase == SchedulerPhase.idle) {
      // No frame is running — safe to call after next frame
      scheduler.addPostFrameCallback((_) => doShow());
      // Ensure a frame is scheduled so the callback actually runs
      WidgetsBinding.instance.ensureVisualUpdate();
    } else {
      scheduler.addPostFrameCallback((_) => doShow());
    }
  }
}
