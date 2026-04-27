// lib/services/notifications/mobile_toast_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import 'web_notification_service.dart';
import '../../main.dart' show navigatorKey; 
import '../../widgets/notification_toast.dart';

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
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS) return;
    
    try {
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