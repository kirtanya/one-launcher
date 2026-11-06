package com.kirtanya.one_launcher

import android.app.AlarmManager
import android.app.PendingIntent
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.tv.TvInputInfo
import android.media.tv.TvInputManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Quick settings panel (lib/tv/tv_quick_settings.dart): only what any Android TV really
 * does, read live — volume and mute (AudioManager), a sleep timer (ours: an alarm), the
 * screensaver now, the HDMI / hardware inputs, network and Bluetooth state — plus links to the
 * TV's own pages, offered only when they resolve on this TV (Sony's own quick settings too).
 * Nothing vendor-specific is faked: picture mode, brightness, speakers… aren't here.
 */
class QuickSettings(private val activity: TvActivity) {
    private val audio by lazy { activity.getSystemService(AudioManager::class.java) }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "qsState" -> result.success(state())
            "qsVolume" -> {
                val v = call.argument<Int>("value") ?: 0
                try { audio.setStreamVolume(AudioManager.STREAM_MUSIC, v.coerceIn(0, audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)), 0) } catch (_: Exception) {}
                result.success(audio.getStreamVolume(AudioManager.STREAM_MUSIC)) // what the TV really took
            }
            "qsMute" -> {
                val on = call.argument<Boolean>("on") == true
                try { audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, if (on) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE, 0) } catch (_: Exception) {}
                result.success(audio.isStreamMute(AudioManager.STREAM_MUSIC))
            }
            "qsSleep" -> result.success(setSleep(activity, call.argument<Int>("minutes") ?: 0))
            "qsOpen" -> result.success(open(call.argument<String>("id")!!))
            else -> return false
        }
        return true
    }

    private fun state(): Map<String, Any?> {
        val c = activity
        return mapOf(
            "volume" to audio.getStreamVolume(AudioManager.STREAM_MUSIC),
            "volumeMax" to audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC),
            "volumeFixed" to audio.isVolumeFixed, // HDMI-CEC / an amplifier owns the volume: show, don't set
            "muted" to audio.isStreamMute(AudioManager.STREAM_MUSIC),
            "sleepAt" to sleepAt(c), // wall-clock ms, 0 = off
            "sleepOff" to ShowNameService.canSleep(), // the timer can turn the screen off (else: screensaver)
            "network" to network(c),
            "bluetooth" to bluetooth(c),
            "inputs" to inputs(c),
            "links" to links.keys.filter { id -> links[id]!!().any { resolves(it) } },
        )
    }

    private fun network(c: Context): String = try {
        val cm = c.getSystemService(ConnectivityManager::class.java)
        val caps = cm.getNetworkCapabilities(cm.activeNetwork)
        when {
            caps == null -> "none"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            else -> "other"
        }
    } catch (_: Exception) {
        "unknown"
    }

    /** true / false, or null when the TV has no Bluetooth (or won't say). */
    private fun bluetooth(c: Context): Boolean? = try {
        c.getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled
    } catch (_: Exception) {
        null
    }

    /** The TV's hardware inputs (HDMI 1, HDMI 2 …), by the names the TV gives them. */
    private fun inputs(c: Context): List<String> = try {
        val tim = c.getSystemService(TvInputManager::class.java)
        tim?.tvInputList.orEmpty()
            .filter { it.isPassthroughInput && it.type != TvInputInfo.TYPE_TUNER }
            .map { (it.loadCustomLabel(c) ?: it.loadLabel(c)).toString() }
            .distinct()
    } catch (_: Exception) {
        emptyList()
    }

    // Each link: what to try, in order. Shown only when one of them resolves here.
    private fun tvSettings(cls: String) = Intent().setClassName("com.android.tv.settings", "com.android.tv.settings.$cls")
    private val links: Map<String, () -> List<Intent>> = linkedMapOf(
        "settings" to { listOf(Intent(Settings.ACTION_SETTINGS)) },
        "screensaver" to { listOf(Intent("com.google.android.pano.action.SLEEP"), Intent(Intent.ACTION_MAIN).setClassName("com.android.systemui", "com.android.systemui.Somnambulator")) },
        "inputs" to { listOf(Intent("com.android.tv.action.VIEW_INPUTS")) },
        "network" to { listOf(Intent(Settings.ACTION_WIFI_SETTINGS)) },
        "bluetooth" to { listOf(tvSettings("accessories.AddAccessoryActivity"), Intent(Settings.ACTION_BLUETOOTH_SETTINGS)) },
        "display" to { listOf(Intent(Settings.ACTION_DISPLAY_SETTINGS)) },
        "sound" to { listOf(Intent(Settings.ACTION_SOUND_SETTINGS), tvSettings("device.displaysound.DisplaySoundActivity")) },
        "accessibility" to { listOf(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) },
        // Sony BRAVIA: its own Quick Settings (picture mode, speakers…), when it lets us open it.
        "sony" to { listOf(Intent().setComponent(ComponentName("com.sony.dtv.smartui", "com.sony.dtv.smartui.settings.SmartSettingsActivity"))) },
    )

    /** Opens on this TV: an exported activity, and not the "open with" chooser. */
    private fun resolves(i: Intent): Boolean = try {
        val ri = activity.packageManager.resolveActivity(i, PackageManager.MATCH_DEFAULT_ONLY)
        val a = ri?.activityInfo
        a != null && a.exported && a.name != "com.android.internal.app.ResolverActivity" && !a.name.endsWith(".ResolverActivity")
    } catch (_: Exception) {
        false
    }

    private fun open(id: String): Boolean {
        val tries = links[id]?.invoke() ?: return false
        return tries.filter { resolves(it) }.any { i ->
            try {
                activity.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (_: Exception) {
                false
            }
        }
    }

    companion object {
        private const val PREFS = "one_quick_settings"

        fun sleepAt(c: Context): Long {
            val at = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong("sleepAt", 0)
            return if (at > System.currentTimeMillis()) at else 0
        }

        /** Sleep timer: [minutes] from now (0 = off). An alarm fires SleepTimerReceiver. Returns when (ms). */
        fun setSleep(c: Context, minutes: Int): Long {
            val am = c.getSystemService(AlarmManager::class.java)
            val pi = PendingIntent.getBroadcast(c, 0, Intent(c, SleepTimerReceiver::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            am.cancel(pi)
            val at = if (minutes > 0) System.currentTimeMillis() + minutes * 60_000L else 0L
            c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putLong("sleepAt", at).apply()
            if (minutes > 0) am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + minutes * 60_000L, pi)
            return at
        }
    }
}

/**
 * The sleep timer ran out: the screen goes off through the accessibility service when it's on
 * (Read show names), else the screensaver starts (the most an app may do on its own).
 */
class SleepTimerReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        context.getSharedPreferences("one_quick_settings", Context.MODE_PRIVATE).edit().putLong("sleepAt", 0).apply()
        if (ShowNameService.sleep()) return
        try {
            context.startActivity(Intent("com.google.android.pano.action.SLEEP").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            try {
                context.startActivity(Intent(Intent.ACTION_MAIN).setClassName("com.android.systemui", "com.android.systemui.Somnambulator").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) {}
        }
    }
}
