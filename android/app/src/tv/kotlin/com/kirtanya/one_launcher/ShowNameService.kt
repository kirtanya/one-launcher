package com.kirtanya.one_launcher

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject

/**
 * Customise → Remote & behaviour → Read show names (TV only, off until switched on in
 * Accessibility settings).
 *
 * Some apps share only an episode ("S1 E5 Firewall", JioHotstar) — no show, no picture. Their
 * player overlay shows the show right next to it, as text. While an app is playing, this reads
 * that app's on-screen text (never pictures, never the video), finds the playing episode's title
 * and takes the show name beside it. Only "app | episode → show" is kept, on the TV; the
 * launcher then finds that episode's still in its catalog. Apps that play nothing are ignored.
 */
class ShowNameService : AccessibilityService() {
    private val sessions by lazy { getSystemService(MediaSessionManager::class.java) }
    private val listener by lazy { ComponentName(this, MediaListener::class.java) }
    private val lastLook = mutableMapOf<String, Long>()

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        if (pkg == packageName) return
        val now = SystemClock.uptimeMillis()
        if (now - (lastLook[pkg] ?: 0L) < 1500) return // overlays redraw often; a look every 1.5 s is plenty
        val titles = playing(pkg)
        if (titles.isEmpty()) return // not a media app right now: read nothing
        lastLook[pkg] = now
        val root = try { rootInActiveWindow } catch (e: Exception) { null }
        if (root == null || root.packageName?.toString() != pkg) {
            android.util.Log.i("OneShow", "$pkg playing $titles; screen not readable (${root?.packageName})")
            return
        }
        val show = showBeside(root, titles)
        android.util.Log.i("OneShow", "$pkg playing $titles → ${show?.second ?: "no show beside it on screen"}")
        if (show != null) save(this, pkg, show.first, show.second)
    }

    /** Titles the app's media sessions are playing / paused on (needs Notification access). */
    private fun playing(pkg: String): Set<String> = try {
        sessions.getActiveSessions(listener)
            .filter { it.packageName == pkg }
            .mapNotNull { it.metadata?.let { m -> m.getString(MediaMetadata.METADATA_KEY_TITLE) ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) } }
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .toSet()
    } catch (e: Exception) {
        emptySet()
    }

    /** (episode title, show) when a text on screen is the playing title and a show name sits beside it. */
    private fun showBeside(root: AccessibilityNodeInfo, titles: Set<String>): Pair<String, String>? {
        val wanted = titles.associateBy { it.lowercase() }
        val stack = ArrayDeque<AccessibilityNodeInfo>().apply { add(root) }
        var seen = 0
        while (stack.isNotEmpty() && seen++ < 600) {
            val node = stack.removeLast()
            val text = node.text?.toString()?.trim()
            val title = text?.let { wanted[it.lowercase()] }
            if (title != null) {
                val parent = node.parent
                if (parent != null) pick(parent, node, title)?.let { return title to it }
            }
            for (i in node.childCount - 1 downTo 0) node.getChild(i)?.let(stack::add)
        }
        return null
    }

    /** The show among the episode's siblings: one whose id says "title", else the text just before it. */
    private fun pick(parent: AccessibilityNodeInfo, episode: AccessibilityNodeInfo, title: String): String? {
        var before: String? = null
        var named: String? = null
        var passed = false
        for (i in 0 until parent.childCount) {
            val c = parent.getChild(i) ?: continue
            if (c == episode) {
                passed = true
                continue
            }
            val t = c.text?.toString()?.trim() ?: continue
            if (!looksLikeShow(t, title)) continue
            val id = c.viewIdResourceName?.substringAfter('/')?.lowercase() ?: ""
            if (named == null && id.contains("title") && !id.contains("sub")) named = t
            if (!passed) before = t
        }
        return named ?: before
    }

    private fun looksLikeShow(t: String, title: String): Boolean =
        t.length in 2..80 &&
            !t.equals(title, ignoreCase = true) &&
            !Regex("""^[\d:\s/.-]+$""").matches(t) && // times, counters
            t.none { it in '\uE000'..'\uF8FF' } // icon-font glyphs

    companion object {
        /** Told when a new show name is read (the launcher redraws its artwork). */
        @Volatile var onChange: (() -> Unit)? = null

        private const val MAX = 200
        private fun prefs(c: Context) = c.getSharedPreferences("one_show_names", Context.MODE_PRIVATE)

        fun enabled(c: Context): Boolean {
            val on = Settings.Secure.getString(c.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
            val me = ComponentName(c, ShowNameService::class.java)
            return on.split(':').any { ComponentName.unflattenFromString(it) == me }
        }

        private fun save(c: Context, pkg: String, title: String, show: String) {
            val p = prefs(c)
            val pairs = try { JSONObject(p.getString("pairs", "{}")!!) } catch (e: Exception) { JSONObject() }
            val key = "$pkg|$title"
            if (pairs.optString(key) == show && p.getString("last:$pkg", null) == show) return
            pairs.remove(key)
            pairs.put(key, show) // newest last
            while (pairs.length() > MAX) pairs.remove(pairs.keys().next())
            p.edit().putString("pairs", pairs.toString()).putString("last:$pkg", show).apply()
            Handler(Looper.getMainLooper()).post { onChange?.invoke() }
        }

        /** For the launcher: {pairs: {"pkg|episode": show}, last: {pkg: show}, on: Boolean}. */
        fun read(c: Context): Map<String, Any> {
            val p = prefs(c)
            val pairs = try { JSONObject(p.getString("pairs", "{}")!!) } catch (e: Exception) { JSONObject() }
            return mapOf(
                "pairs" to pairs.keys().asSequence().associateWith { pairs.getString(it) },
                "last" to p.all.filterKeys { it.startsWith("last:") }.map { (k, v) -> k.removePrefix("last:") to v.toString() }.toMap(),
                "on" to enabled(c),
            )
        }
    }
}
