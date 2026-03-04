// lib/services/mobile_toast_service.dart
//
// Shows the same in-app popup toast on mobile that web shows via the bell.
// Called from NotificationService when flutter_local_notifications delivers
// a notification while the app is in the FOREGROUND.
//
// Flutter_local_notifications behaviour by platform:
//   Android: foreground notifications are suppressed by default — the OS
//            calls onDidReceiveNotificationResponse only if you set
//            android.showWhen=true AND the app handles it. We intercept here.
//   iOS:     foreground notifications show a banner AND call the callback.
//            We additionally show our in-app popup for consistency.
//
// Usage: MobileToastService.show(title, body) from anywhere.

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../main.dart' show navigatorKey;
import '../ui/widgets/notification_toast.dart';

class MobileToastService {
  MobileToastService._();

  /// Show the in-app notification popup on mobile.
  /// Safe to call from any isolate context — posts to the UI thread.
  static void show({required String title, required String body}) {
    if (kIsWeb) return; // web uses NotificationBell.onChanged instead

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = navigatorKey.currentState?.overlay;
      if (overlay == null) {
        debugPrint('[MobileToast] overlay not ready — toast skipped');
        return;
      }
      debugPrint('[MobileToast] Showing toast: $title');
      // Play system alert sound — works on Android + iOS, no extra package needed
      SystemSound.play(SystemSoundType.alert);
      showNotifToast(overlay: overlay, title: title, body: body);
    });
  }
}
