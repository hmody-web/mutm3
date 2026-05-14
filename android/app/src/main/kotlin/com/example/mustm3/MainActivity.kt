package com.example.mustm3

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.mustm3/app_icon"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIcon" -> {
                        try {
                            val isDark = call.argument<Boolean>("isDark") ?: false
                            val packageName = applicationContext.packageName

                            val defaultAlias = ComponentName(
                                packageName,
                                "$packageName.MainActivityDefault"
                            )
                            val darkAlias = ComponentName(
                                packageName,
                                "$packageName.MainActivityDark"
                            )

                            val pm = applicationContext.packageManager

                            if (isDark) {
                                // تفعيل الأيقونة الداكنة وإلغاء الافتراضية
                                pm.setComponentEnabledSetting(
                                    defaultAlias,
                                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                                pm.setComponentEnabledSetting(
                                    darkAlias,
                                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                            } else {
                                // العودة للأيقونة الافتراضية
                                pm.setComponentEnabledSetting(
                                    darkAlias,
                                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                                pm.setComponentEnabledSetting(
                                    defaultAlias,
                                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                            }

                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ICON_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}