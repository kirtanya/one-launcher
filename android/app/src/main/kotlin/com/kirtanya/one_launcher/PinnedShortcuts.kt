package com.kirtanya.one_launcher

import android.app.Activity
import android.content.Context
import android.content.pm.LauncherApps
import android.content.pm.ShortcutInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Bundle
import android.os.Process
import android.os.UserManager
import java.io.ByteArrayOutputStream

/**
 * "Add to Home screen" from other apps (Chrome's Add to Home screen / Install app, Maps
 * directions, contacts…). Android only offers it when the default home app has this
 * activity; we say yes straight away (no dialog) and the shortcut shows up in the app list.
 * Pinned widgets are declined (widgets are added from Settings → top carousel instead).
 */
class PinShortcutActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val launcherApps = getSystemService(LauncherApps::class.java)
        val request = try { launcherApps.getPinItemRequest(intent) } catch (e: Exception) { null }
        if (request != null && request.isValid) {
            if (request.requestType == LauncherApps.PinItemRequest.REQUEST_TYPE_SHORTCUT) {
                try {
                    // Accepting pins it to us: Android keeps it (and its icon) for this launcher.
                    if (request.accept()) PinnedShortcuts.onPinned?.invoke()
                } catch (e: Exception) {
                }
            }
        }
        finish()
    }
}

/**
 * Shortcuts pinned to One Launcher, listed with the apps. Id: "s:<package>|<shortcutId>|<profile serial>".
 * Android stores them (per launcher), so nothing is kept on our side.
 */
class PinnedShortcuts(private val context: Context) {
    companion object {
        /** Set by MainActivity: refresh the app list when a new shortcut is pinned. */
        var onPinned: (() -> Unit)? = null

        fun isShortcut(id: String) = id.startsWith("s:")
    }

    private val launcherApps = context.getSystemService(LauncherApps::class.java)
    private val users = context.getSystemService(UserManager::class.java)

    private fun allowed() = try { launcherApps.hasShortcutHostPermission() } catch (e: Exception) { false }

    /** App-list entries for every pinned shortcut (same keys as MainActivity.loadApps, plus "shortcut"). */
    fun list(): List<Map<String, Any>> {
        if (!allowed()) return emptyList()
        val me = Process.myUserHandle()
        val pm = context.packageManager
        val out = mutableListOf<Map<String, Any>>()
        for (user in launcherApps.profiles) {
            val serial = users.getSerialNumberForUser(user)
            val pinned = try {
                launcherApps.getShortcuts(LauncherApps.ShortcutQuery().setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED), user)
            } catch (e: Exception) {
                null
            } ?: continue
            for (s in pinned) {
                if (!s.isPinned || !s.isEnabled) continue
                val app = try { pm.getApplicationInfo(s.`package`, 0) } catch (e: Exception) { null }
                out += mapOf(
                    "package" to "s:${s.`package`}|${s.id}|$serial",
                    "label" to (s.shortLabel?.toString() ?: s.longLabel?.toString() ?: s.id),
                    "system" to false,
                    // The source app's category, so it lands in the same folder as that app.
                    "category" to (app?.category ?: -1),
                    "installed" to s.lastChangedTimestamp,
                    "work" to (user != me),
                    "paused" to false,
                    "shortcut" to true,
                    "app" to (app?.let { pm.getApplicationLabel(it).toString() } ?: s.`package`),
                )
            }
        }
        return out
    }

    private fun parse(id: String): Triple<String, String, android.os.UserHandle>? {
        val body = id.removePrefix("s:")
        val first = body.indexOf('|')
        val last = body.lastIndexOf('|')
        if (first < 0 || last <= first) return null
        val user = users.getUserForSerialNumber(body.substring(last + 1).toLongOrNull() ?: return null) ?: Process.myUserHandle()
        return Triple(body.substring(0, first), body.substring(first + 1, last), user)
    }

    private fun find(id: String): ShortcutInfo? {
        val (pkg, sid, user) = parse(id) ?: return null
        return try {
            launcherApps.getShortcuts(
                LauncherApps.ShortcutQuery().setPackage(pkg).setShortcutIds(listOf(sid))
                    .setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED),
                user,
            )?.firstOrNull()
        } catch (e: Exception) {
            null
        }
    }

    fun launch(id: String, rect: android.graphics.Rect?, opts: Bundle?): Boolean {
        if (!allowed()) return false
        val (pkg, sid, user) = parse(id) ?: return false
        return try {
            launcherApps.startShortcut(pkg, sid, rect, opts, user)
            true
        } catch (e: Exception) {
            false // the app removed or disabled it
        }
    }

    /** Unpin: keep every other shortcut this package has pinned to us. */
    fun remove(id: String): Boolean {
        if (!allowed()) return false
        val (pkg, sid, user) = parse(id) ?: return false
        return try {
            val keep = launcherApps.getShortcuts(
                LauncherApps.ShortcutQuery().setPackage(pkg).setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED),
                user,
            )?.map { it.id }?.filter { it != sid } ?: emptyList()
            launcherApps.pinShortcuts(pkg, keep, user)
            true
        } catch (e: Exception) {
            false
        }
    }

    fun packageOf(id: String): String? = parse(id)?.first

    /** The shortcut's own icon (badged for work), as PNG; the app's icon if it has none. */
    fun icon(id: String): ByteArray? = try {
        val info = find(id)
        val d = info?.let { launcherApps.getShortcutBadgedIconDrawable(it, context.resources.displayMetrics.densityDpi) }
            ?: context.packageManager.getApplicationIcon(packageOf(id)!!)
        val size = 144
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, size, size)
        d.draw(Canvas(bmp))
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    } catch (e: Exception) {
        null
    }
}
