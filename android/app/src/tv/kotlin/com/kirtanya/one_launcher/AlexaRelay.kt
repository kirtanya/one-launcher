package com.kirtanya.one_launcher

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * "Alexa, ask One TV to search Panchayat" / "… to open YouTube".
 *
 * The Alexa skill (alexa/ in the repo, hosted by Amazon) posts {"type":"search","q":…,"app":…?} or
 * {"type":"open","app":…} to a secret ntfy.sh topic; this keeps one streaming connection to that
 * topic and acts on each message:
 *  - search: inside the named app, else inside the app on screen, when that app takes searches
 *    (YouTube by its search link; apps with a working search screen); otherwise One Launcher TV's
 *    search with the words (the phone's voice search path). Netflix, Prime Video and JioHotstar
 *    take no searches from other apps (tested 2026-10-31): they land in our search, which has
 *    their rows and "Watch on …".
 *  - open: the installed app whose name matches, else a search.
 *
 * The topic comes from ./alexa.topic at build time (R.string.alexa_topic; empty = off). Messages
 * older than a minute are dropped (a reconnect never replays an old search onto the screen).
 * Started by TvActivity and by ShowNameService (bound by the system, so it outlives the activity).
 */
object AlexaRelay {
    private const val TAG = "OneAlexa"
    @Volatile private var thread: Thread? = null

    fun start(c: Context) {
        val app = c.applicationContext
        val topic = app.getString(R.string.alexa_topic)
        if (topic.isEmpty() || thread?.isAlive == true) return
        synchronized(this) {
            if (thread?.isAlive == true) return
            thread = Thread({ loop(app, topic) }, "alexa-relay").apply { isDaemon = true; start() }
        }
    }

    private fun loop(c: Context, topic: String) {
        var since: String? = null
        var wait = 2_000L
        while (true) {
            try {
                val url = "https://ntfy.sh/${URLEncoder.encode(topic, "UTF-8")}/json" + (since?.let { "?since=$it" } ?: "")
                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 10_000
                    readTimeout = 120_000 // ntfy sends a keepalive every ~45 s
                    setRequestProperty("User-Agent", "OneLauncherTV/1.0 (personal launcher)")
                }
                if (conn.responseCode != 200) throw IllegalStateException("HTTP ${conn.responseCode}")
                Log.i(TAG, "listening")
                wait = 2_000L
                conn.inputStream.bufferedReader().useLines { lines ->
                    for (line in lines) {
                        val ev = try { JSONObject(line) } catch (e: Exception) { continue }
                        if (ev.optString("event") != "message") continue
                        since = ev.optString("id").ifEmpty { since }
                        val age = System.currentTimeMillis() / 1000 - ev.optLong("time")
                        if (age > 60) continue
                        val msg = try { JSONObject(ev.optString("message")) } catch (e: Exception) { continue }
                        Handler(Looper.getMainLooper()).post { act(c, msg) }
                    }
                }
            } catch (e: Exception) {
                Log.i(TAG, "connection lost: ${e.message}")
            }
            Thread.sleep(wait)
            wait = (wait * 2).coerceAtMost(60_000L)
        }
    }

    private fun act(c: Context, msg: JSONObject) {
        when (msg.optString("type")) {
            "search" -> msg.optString("q").trim().takeIf { it.isNotEmpty() }?.let { q ->
                val named = msg.optString("app").trim()
                val pkg = if (named.isNotEmpty()) findApp(c, named)?.`package` else ShowNameService.onScreen(c)
                if (pkg != null && searchInApp(c, pkg, q)) Log.i(TAG, "search '$q' in $pkg") else search(c, q)
            }
            "open" -> msg.optString("app").trim().takeIf { it.isNotEmpty() }?.let { name ->
                val launch = findApp(c, name)
                Log.i(TAG, "open '$name' → ${launch?.`package` ?: "no match, searching"}")
                if (launch != null) c.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) else search(c, name)
            }
        }
    }

    private fun search(c: Context, q: String) {
        Log.i(TAG, "search '$q'")
        c.startActivity(
            Intent(c, TvActivity::class.java)
                .putExtra(TvActivity.EXTRA_SEARCH, q)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
        )
    }

    /** A search inside [pkg]: YouTube by its search link; any app with a search screen
     *  (ACTION_SEARCH; JioHotstar leaves DEFAULT off it, so address it by name). False = can't. */
    private fun searchInApp(c: Context, pkg: String, q: String): Boolean {
        fun go(i: Intent) = try {
            c.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)); true
        } catch (e: Exception) { false }
        if (pkg == "com.google.android.youtube.tv") {
            return go(Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://www.youtube.com/results?search_query=" + URLEncoder.encode(q, "UTF-8"))).setPackage(pkg))
        }
        if (pkg in IGNORES_WORDS) return false
        val base = Intent(Intent.ACTION_SEARCH).setPackage(pkg).putExtra(android.app.SearchManager.QUERY, q)
        val target = try { c.packageManager.queryIntentActivities(base, 0).firstOrNull()?.activityInfo } catch (e: Exception) { null } ?: return false
        return go(Intent(base).setClassName(target.packageName, target.name))
    }

    /** Apps whose search screen opens but drops the words (JioHotstar showed an old query, 2026-10-31). */
    private val IGNORES_WORDS = setOf("in.startv.hotstar")

    /** What people call an app → its name on the TV (spaces and case already gone). */
    private val ALIASES = mapOf(
        "prime" to "primevideo", "amazonprime" to "primevideo", "amazonprimevideo" to "primevideo", "amazonvideo" to "primevideo",
        "hotstar" to "jiohotstar", "disneyhotstar" to "jiohotstar", "jiocinema" to "jiohotstar",
        "zeefive" to "zee5", "sony" to "sonyliv",
    )

    /** The installed app whose name best matches what Alexa heard ("you tube" → YouTube). */
    private fun findApp(c: Context, said: String): Intent? {
        fun norm(s: String) = s.lowercase().filter { it.isLetterOrDigit() }
        val heard = norm(said).removeSuffix("app")
        val want = ALIASES[heard] ?: heard
        if (want.isEmpty()) return null
        val pm = c.packageManager
        val apps = listOf(Intent.CATEGORY_LEANBACK_LAUNCHER, Intent.CATEGORY_LAUNCHER)
            .flatMap { pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(it), 0) }
            .map { it.activityInfo.packageName to norm(it.loadLabel(pm).toString()) }
            .filter { it.first != c.packageName }
        val pkg = (apps.firstOrNull { it.second == want }
            ?: apps.firstOrNull { it.second.startsWith(want) }
            ?: apps.filter { it.second.contains(want) || (it.second.length >= 4 && want.contains(it.second)) }.minByOrNull { it.second.length })
            ?.first ?: return null
        return pm.getLeanbackLaunchIntentForPackage(pkg) ?: pm.getLaunchIntentForPackage(pkg)
    }
}
