package com.kirtanya.one_launcher

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors

/**
 * The phone remote's Now playing card: what's playing on this TV, over the home Wi-Fi.
 *
 * The phone first gives this TV a secret through the remote protocol's own (paired, encrypted)
 * link: `onelauncher://phone?token=…` (see BrightnessActivity → [remember]). Then it asks
 * `GET /now?t=<secret>` (title, app, position, duration, playing, an id for the picture) and,
 * when that id changes, `GET /art?t=<secret>` (a small JPEG). Anything without a known secret
 * gets 403. Read-only: controls go through the remote protocol as keys.
 */
object NowPlayingServer {
    const val PORT = 6470
    private const val PREFS = "one_phone"
    private const val MAX_TOKENS = 4 // a few phones (or reinstalls) at most

    @Volatile private var started = false
    private val pool = Executors.newFixedThreadPool(2)

    fun start(context: Context) {
        if (started) return
        started = true
        val app = context.applicationContext
        Thread({
            try {
                ServerSocket(PORT).use { server ->
                    while (true) {
                        val s = server.accept()
                        pool.execute { serve(app, s) }
                    }
                }
            } catch (e: Exception) {
                started = false // port taken or closed: tried again on the next start
            }
        }, "NowPlayingServer").apply { isDaemon = true }.start()
    }

    /** A phone's secret, sent over the remote protocol's link. */
    fun remember(context: Context, token: String) {
        if (token.length < 16) return
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = (p.getString("tokens", "") ?: "").split(',').filter { it.isNotEmpty() && it != token }.takeLast(MAX_TOKENS - 1) + token
        p.edit().putString("tokens", list.joinToString(",")).apply()
    }

    private fun known(context: Context, token: String?) =
        token != null && (context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("tokens", "") ?: "").split(',').contains(token)

    private fun serve(context: Context, s: Socket) = s.use {
        s.soTimeout = 4000
        val line = s.getInputStream().bufferedReader().readLine() ?: return@use
        val target = line.split(' ').getOrNull(1) ?: return@use
        val path = target.substringBefore('?')
        val token = target.substringAfter('?', "").split('&').firstOrNull { it.startsWith("t=") }?.substring(2)
        val out = s.getOutputStream()
        fun reply(code: Int, type: String, body: ByteArray) {
            val head = "HTTP/1.1 $code ${if (code == 200) "OK" else "No"}\r\nContent-Type: $type\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n"
            out.write(head.toByteArray())
            out.write(body)
            out.flush()
        }
        if (!known(context, token)) return@use reply(403, "text/plain", ByteArray(0))
        val now = playing(context)
        when (path) {
            "/now" -> reply(200, "application/json", (now?.json ?: JSONObject().put("active", false)).toString().toByteArray())
            "/art" -> {
                val art = now?.art ?: return@use reply(404, "text/plain", ByteArray(0))
                val bytes = ByteArrayOutputStream().also { ArtFetch.fit(art, 480).compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
                reply(200, "image/jpeg", bytes)
            }
            else -> reply(404, "text/plain", ByteArray(0))
        }
    }

    private class Now(val json: JSONObject, val art: Bitmap?)

    /** The playing (else paused) media session, like the TV home's Continue watching. */
    private fun playing(context: Context): Now? = try {
        val sessions = context.getSystemService(MediaSessionManager::class.java)
            .getActiveSessions(ComponentName(context, MediaListener::class.java))
            .filter { it.packageName != context.packageName && it.metadata != null }
        val c = sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING }
            ?: sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PAUSED }
        c?.let {
            val m = it.metadata!!
            val st = it.playbackState
            var pos = st?.position ?: 0L
            if (st?.state == PlaybackState.STATE_PLAYING && st.lastPositionUpdateTime > 0) {
                pos += ((SystemClock.elapsedRealtime() - st.lastPositionUpdateTime) * st.playbackSpeed).toLong()
            }
            val title = m.getString(MediaMetadata.METADATA_KEY_TITLE) ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: ""
            val pm = context.packageManager
            val appName = try { pm.getApplicationLabel(pm.getApplicationInfo(it.packageName, 0)).toString() } catch (e: Exception) { it.packageName }
            val art = ArtFetch.bitmapOf(m)?.takeUnless(ArtFetch::isBlank)
            Now(
                JSONObject()
                    .put("active", title.isNotBlank())
                    .put("title", title)
                    .put("subtitle", m.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: m.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE) ?: "")
                    .put("app", appName)
                    .put("package", it.packageName)
                    .put("playing", st?.state == PlaybackState.STATE_PLAYING)
                    .put("position", pos.coerceAtLeast(0))
                    .put("duration", m.getLong(MediaMetadata.METADATA_KEY_DURATION))
                    .put("artId", art?.let { b -> "${it.packageName}|$title|${b.width}x${b.height}" } ?: ""),
                art,
            )
        }
    } catch (e: Exception) {
        null // Notification access off: nothing to tell
    }
}
