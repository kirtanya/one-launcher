package com.kirtanya.one_launcher

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.provider.Settings

/**
 * The phone remote's picture controls. The Android TV remote protocol has no brightness command,
 * but it can open links on the TV, so the phone sends:
 *  - `onelauncher://picture` → opens the TV's own picture panel (backlight lives there on most
 *    TVs; the phone's D-pad then adjusts it)
 *  - `onelauncher://brightness?level=0…255` → Android's screen brightness (only TVs whose
 *    backlight follows it; needs "Modify system settings")
 * Invisible: does its job and closes at once.
 */
class BrightnessActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val uri = intent?.data
            when (uri?.host) {
                "picture" -> openPicture()
                "brightness" -> {
                    val level = uri.getQueryParameter("level")?.toIntOrNull()
                    if (level != null && Settings.System.canWrite(this)) {
                        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
                        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, level.coerceIn(1, 255))
                    }
                }
            }
        } catch (_: Exception) {
        }
        finish()
        overridePendingTransition(0, 0)
    }

    /** The TV maker's picture panel if there is one, else Android TV's display settings. */
    private fun openPicture() {
        val tries = listOf(
            Intent("com.apps.settings.picture.PictureAdjustActivity"), // Realtek-based TVs (e.g. this Acer)
            Intent("android.settings.PICTURE_SETTINGS"),
            Intent(Settings.ACTION_DISPLAY_SETTINGS),
            Intent(Settings.ACTION_SETTINGS),
        )
        for (i in tries) {
            try {
                startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: Exception) {
            }
        }
    }
}
