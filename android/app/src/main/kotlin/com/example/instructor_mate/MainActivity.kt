// android/app/src/main/kotlin/com/instructormate/instructor_mate/MainActivity.kt

package com.instructormate.instructor_mate

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

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // ── NUCLEAR PURGE before Flutter engine starts ───────────────────────
        // flutter_local_notifications v17+ stores scheduled notifications in
        // TWO places:
        //   1. SharedPreferences XML files (older versions)
        //   2. SQLite database: databases/notifications.db (v17+, PRIMARY)
        //
        // Old builds used matchDateTimeComponents (type=2 repeating).
        // The new plugin's Java deserializer crashes on type=2 in BOTH stores.
        // Even initialize(), cancelAll(), and zonedSchedule() all crash because
        // they call loadScheduledNotifications which reads the SQLite DB first.
        //
        // We MUST delete BOTH stores here, before super.onCreate() starts
        // the Flutter engine, so the plugin starts with a completely clean slate.
        purgeAllNotificationStorage()
        super.onCreate(savedInstanceState)
    }

    private fun purgeAllNotificationStorage() {
        try {
            val flagFile = File(applicationContext.filesDir, "notif_purge_v4.flag")
            if (flagFile.exists()) return  // already purged on a previous launch

            var log = ""

            // ── 1. Delete SQLite database (PRIMARY store in v17+) ─────────────
            val dbDir = applicationContext.getDatabasePath("notifications.db").parentFile
            val dbTargets = listOf(
                "notifications.db",
                "notifications.db-shm",
                "notifications.db-wal",
                "notifications.db-journal",
            )
            for (name in dbTargets) {
                val f = if (dbDir != null) File(dbDir, name)
                        else applicationContext.getDatabasePath(name)
                if (f.exists()) {
                    val ok = f.delete()
                    log += "DB $name deleted=$ok; "
                }
            }

            // ── 2. Delete SharedPreferences XML files (fallback/older store) ──
            val prefsDir = File(applicationContext.dataDir, "shared_prefs")
            val xmlTargets = listOf(
                "notification_plugin_cache.xml",
                "com.dexterous.flutterlocalnotifications.xml",
                "scheduled_notifications.xml",
                "notification_appLaunch.xml",
            )
            for (name in xmlTargets) {
                val f = File(prefsDir, name)
                if (f.exists()) {
                    val ok = f.delete()
                    log += "XML $name deleted=$ok; "
                }
            }

            // ── 3. Set flag so purge never runs again ─────────────────────────
            flagFile.createNewFile()
            android.util.Log.d("InstructorMate", "Purge complete: $log")

        } catch (e: Exception) {
            android.util.Log.e("InstructorMate", "Purge error (non-fatal): ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATTERY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {

                "purgeCorruptedNotifications" -> {
                    // Reset the flag so purge runs again on next launch
                    try {
                        File(applicationContext.filesDir, "notif_purge_v4.flag").delete()
                        purgeAllNotificationStorage()
                        result.success("purge complete")
                    } catch (e: Exception) {
                        result.error("PURGE", e.message, null)
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