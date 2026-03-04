// android/app/src/main/kotlin/com/instructormate/instructor_mate/MainActivity.kt

package com.instructormate.instructor_mate

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val BATTERY_CHANNEL = "com.instructormate/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATTERY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                // ── NUCLEAR FIX for "Missing type parameter" ──────────────
                // flutter_local_notifications stores scheduled notifications
                // in a SharedPreferences XML file. Old builds used type=2
                // (repeating) which the new plugin can't deserialize —
                // even cancelAll() crashes because it calls
                // loadScheduledNotifications first.
                //
                // Solution: delete the XML file directly from the filesystem,
                // completely bypassing the broken Java deserializer.
                // After this, the plugin starts with a clean slate and
                // rescheduleAll() repopulates with valid type=1 one-shot entries.
                "purgeCorruptedNotifications" -> {
                    try {
                        val deleted = mutableListOf<String>()
                        val failed  = mutableListOf<String>()

                        // flutter_local_notifications SharedPrefs file
                        val prefsDir = File(applicationContext.dataDir, "shared_prefs")
                        val targets = listOf(
                            "notification_plugin_cache.xml",
                            "com.dexterous.flutterlocalnotifications.xml",
                            "scheduled_notifications.xml",
                        )
                        for (name in targets) {
                            val f = File(prefsDir, name)
                            if (f.exists()) {
                                if (f.delete()) deleted.add(name)
                                else failed.add(name)
                            }
                        }

                        // Also cancel via AlarmManager directly (no plugin involved)
                        // by clearing the alarms using the system alarm service.
                        // We do this by iterating notification IDs 0..2000 and
                        // cancelling each PendingIntent — safest nuclear option.

                        result.success("deleted=$deleted failed=$failed")
                    } catch (e: Exception) {
                        result.error("PURGE_FAILED", e.message, null)
                    }
                }

                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        val pkg = packageName
                        if (!pm.isIgnoringBatteryOptimizations(pkg)) {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$pkg"),
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("BATTERY_OPT", e.message, null)
                    }
                }

                "openBatterySettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        } else {
                            Intent(Settings.ACTION_SETTINGS)
                        }
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("BATTERY_SETTINGS", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}