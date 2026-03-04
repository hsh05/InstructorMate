// lib/services/mobile_toast_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'web_notification_service.dart';
import '../main.dart' show navigatorKey;
import '../ui/widgets/notification_toast.dart';

class MobileToastService {
  MobileToastService._();

  static void show({required String title, required String body}) {
    if (kIsWeb) return;

    // Record in universal bell history so badge appears on mobile bell
    WebNotificationService.instance.addMobileNotif(
      title: title,
      body: body,
      fireAt: DateTime.now(),
    );

    // Play bell chime
    _playChime();

    _tryShow(title: title, body: body, attempt: 0);
  }

  static void _playChime() {
    try {
      FlutterRingtonePlayer().playNotification(
        looping: false,
        volume: 0.8,
        asAlarm: false,
      );
    } catch (e) {}
  }

  static void _tryShow({
    required String title,
    required String body,
    required int attempt,
  }) {
    void doShow() {
      try {
        final navState = navigatorKey.currentState;
        if (navState == null) {
          if (attempt < 3) {
            Future.delayed(const Duration(milliseconds: 300), () {
              _tryShow(title: title, body: body, attempt: attempt + 1);
            });
          } else {}
          return;
        }
        final overlay = navState.overlay;
        if (overlay == null) {
          return;
        }
        showNotifToast(overlay: overlay, title: title, body: body);
      } catch (e, stack) {}
    }

    try {
      SchedulerBinding.instance.addPostFrameCallback((_) => doShow());
      WidgetsBinding.instance.ensureVisualUpdate();
    } catch (e, stack) {}
  }
}
