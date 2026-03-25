import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'web_notification_service.dart';
// Note: Ensure this path is correct relative to this file
import '../main.dart' show navigatorKey; 
import '../screens/widgets/notification_toast.dart';

class MobileToastService {
  MobileToastService._();

  static void show({required String title, required String body}) {
    if (kIsWeb) return;

    // Record in universal history
    WebNotificationService.instance.addMobileNotif(
      title: title,
      body: body,
      fireAt: DateTime.now(),
    );

    _playChime();
    _tryShow(title: title, body: body, attempt: 0);
  }

  static void _playChime() {
    try {
      // FIX: In version 4.x, we use FlutterRingtonePlayer.playNotification(...) 
      // without the parentheses () if it's a static call, 
      // or ensure the instance is handled correctly.
      FlutterRingtonePlayer().playNotification(
        looping: false,
        volume: 0.8,
        asAlarm: false,
      );
    } catch (e) {
      debugPrint("Ringtone Player Error: $e");
    }
  }

  static void _tryShow({
    required String title,
    required String body,
    required int attempt,
  }) {
    // We use SchedulerBinding to ensure we aren't calling this during a build phase
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final navState = navigatorKey.currentState;

      if (navState == null) {
        if (attempt < 5) { // Increased attempts slightly for slow app boots
          Future.delayed(const Duration(milliseconds: 500), () {
            _tryShow(title: title, body: body, attempt: attempt + 1);
          });
        }
        return;
      }

      final overlay = navState.overlay;
      if (overlay != null) {
        showNotifToast(overlay: overlay, title: title, body: body);
      }
    });
  }
}