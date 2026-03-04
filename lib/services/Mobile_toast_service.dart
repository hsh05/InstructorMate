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
    debugPrint('[Toast] >>> show() called title="$title"');
    if (kIsWeb) {
      debugPrint('[Toast] kIsWeb=true — skipping (web uses bell)');
      return;
    }

    void doShow() {
      debugPrint('[Toast] doShow() executing on frame callback');
      try {
        debugPrint('[Toast] Step A — checking navigatorKey...');
        final navState = navigatorKey.currentState;
        debugPrint('[Toast] Step B — navState=$navState');
        if (navState == null) {
          debugPrint(
            '[Toast] !!! navigatorKey.currentState is NULL — toast skipped',
          );
          return;
        }
        final overlay = navState.overlay;
        debugPrint('[Toast] Step C — overlay=$overlay');
        if (overlay == null) {
          debugPrint('[Toast] !!! overlay is NULL — toast skipped');
          return;
        }

        debugPrint('[Toast] Step D — playing sound...');
        try {
          SystemSound.play(SystemSoundType.alert);
          debugPrint('[Toast] Step D — sound ok');
        } catch (e) {
          debugPrint('[Toast] Step D — sound failed (non-fatal): $e');
        }

        debugPrint('[Toast] Step E — inserting overlay entry...');
        showNotifToast(overlay: overlay, title: title, body: body);
        debugPrint('[Toast] Step F — toast inserted successfully ✓');
      } catch (e, stack) {
        debugPrint('[Toast] !!! CRASH in doShow: $e');
        debugPrint('[Toast] !!! STACK: $stack');
      }
    }

    try {
      debugPrint('[Toast] Step 1 — getting SchedulerBinding...');
      final scheduler = SchedulerBinding.instance;
      debugPrint('[Toast] Step 2 — phase=${scheduler.schedulerPhase}');
      scheduler.addPostFrameCallback((_) => doShow());
      debugPrint('[Toast] Step 3 — postFrameCallback registered');
      WidgetsBinding.instance.ensureVisualUpdate();
      debugPrint('[Toast] Step 4 — ensureVisualUpdate called');
    } catch (e, stack) {
      debugPrint('[Toast] !!! CRASH registering callback: $e');
      debugPrint('[Toast] !!! STACK: $stack');
    }
  }
}
