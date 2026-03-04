// lib/services/mobile_toast_service.dart

import 'log_buffer.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../main.dart' show navigatorKey;
import '../ui/widgets/notification_toast.dart';

class MobileToastService {
  MobileToastService._();

  static void show({required String title, required String body}) {
    AppLog.d('[Toast] >>> show() called title="$title"');
    if (kIsWeb) {
      AppLog.d('[Toast] kIsWeb=true — skipping (web uses bell)');
      return;
    }

    void doShow() {
      AppLog.d('[Toast] doShow() executing on frame callback');
      try {
        AppLog.d('[Toast] Step A — checking navigatorKey...');
        final navState = navigatorKey.currentState;
        AppLog.d('[Toast] Step B — navState=$navState');
        if (navState == null) {
          AppLog.d(
            '[Toast] !!! navigatorKey.currentState is NULL — toast skipped',
          );
          return;
        }
        final overlay = navState.overlay;
        AppLog.d('[Toast] Step C — overlay=$overlay');
        if (overlay == null) {
          AppLog.d('[Toast] !!! overlay is NULL — toast skipped');
          return;
        }

        AppLog.d('[Toast] Step D — playing sound...');
        try {
          SystemSound.play(SystemSoundType.alert);
          AppLog.d('[Toast] Step D — sound ok');
        } catch (e) {
          AppLog.d('[Toast] Step D — sound failed (non-fatal): $e');
        }

        AppLog.d('[Toast] Step E — inserting overlay entry...');
        showNotifToast(overlay: overlay, title: title, body: body);
        AppLog.d('[Toast] Step F — toast inserted successfully ✓');
      } catch (e, stack) {
        AppLog.d('[Toast] !!! CRASH in doShow: $e');
        AppLog.d('[Toast] !!! STACK: $stack');
      }
    }

    try {
      AppLog.d('[Toast] Step 1 — getting SchedulerBinding...');
      final scheduler = SchedulerBinding.instance;
      AppLog.d('[Toast] Step 2 — phase=${scheduler.schedulerPhase}');
      scheduler.addPostFrameCallback((_) => doShow());
      AppLog.d('[Toast] Step 3 — postFrameCallback registered');
      WidgetsBinding.instance.ensureVisualUpdate();
      AppLog.d('[Toast] Step 4 — ensureVisualUpdate called');
    } catch (e, stack) {
      AppLog.d('[Toast] !!! CRASH registering callback: $e');
      AppLog.d('[Toast] !!! STACK: $stack');
    }
  }
}
