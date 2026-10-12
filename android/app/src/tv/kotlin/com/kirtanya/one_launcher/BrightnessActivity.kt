package com.kirtanya.one_launcher

import android.app.Activity
import android.os.Bundle
import android.provider.Settings

/**
 * Sets the TV's brightness for the phone's remote. The Android TV remote protocol has no
 * brightness command, but it can open links on the TV — the phone sends
 * `onelauncher://brightness?level=0…255`, Android opens this invisible screen, it sets the
 * backlight and closes at once. Needs "Modify system settings" for One Launcher TV (granted
 * once). Without it, it does nothing.
 */
class BrightnessActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val level = intent?.data?.getQueryParameter("level")?.toIntOrNull()
            if (level != null && Settings.System.canWrite(this)) {
                Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
                Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, level.coerceIn(1, 255))
            }
        } catch (_: Exception) {
        }
        finish()
        overridePendingTransition(0, 0)
    }
}
