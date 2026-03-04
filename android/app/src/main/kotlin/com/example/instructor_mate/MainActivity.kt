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

class MainActivity : FlutterActivity() {

    private val BATTERY_CHANNEL = "com.instructormate/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATTERY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {

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