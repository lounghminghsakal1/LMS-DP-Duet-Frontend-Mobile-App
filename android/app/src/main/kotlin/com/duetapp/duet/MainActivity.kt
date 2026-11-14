package com.duetapp.duet

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter and switches the home-screen icon between the General / Love /
 * Friends launcher aliases declared in AndroidManifest.xml.
 */
class MainActivity : FlutterActivity() {
    private val aliases = linkedMapOf(
        "general" to "LauncherGeneral",
        "love" to "LauncherLove",
        "friends" to "LauncherFriends",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "duet/app_icon").setMethodCallHandler { call, result ->
            when (call.method) {
                "current" -> result.success(currentIcon())
                "set" -> {
                    val name = call.argument<String>("name")
                    if (name == null || name !in aliases) {
                        result.error("bad_icon", "Unknown icon: $name", null)
                    } else {
                        try {
                            result.success(setIcon(name))
                        } catch (error: Exception) {
                            result.error("icon_failed", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun component(alias: String) = ComponentName(this, "${javaClass.`package`?.name}.$alias")

    private fun isEnabled(name: String): Boolean {
        val state = packageManager.getComponentEnabledSetting(component(aliases.getValue(name)))
        return when (state) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DEFAULT -> name == "general" // manifest default
            else -> false
        }
    }

    private fun currentIcon(): String = aliases.keys.firstOrNull { isEnabled(it) } ?: "general"

    /** Returns true if the icon changed. Enables the new alias before disabling the
     *  others so there is always a launcher entry. */
    private fun setIcon(name: String): Boolean {
        if (currentIcon() == name && aliases.keys.count { isEnabled(it) } == 1) return false
        packageManager.setComponentEnabledSetting(
            component(aliases.getValue(name)),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )
        for ((other, alias) in aliases) {
            if (other == name) continue
            packageManager.setComponentEnabledSetting(
                component(alias),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
        return true
    }
}
