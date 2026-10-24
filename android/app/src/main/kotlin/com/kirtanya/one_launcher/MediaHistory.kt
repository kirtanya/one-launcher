package com.kirtanya.one_launcher

import android.content.ComponentName
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSession
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * One Launcher TV's own watch history: whatever plays in any app (title, artwork, app, how far
 * you got) is remembered on the TV, so "Continue watching" survives the app closing.
 *
 * Runs inside [MediaListener] (the Notification-access service), which Android keeps alive
 * while you watch, so it records even when the launcher isn't on screen. TV app only; nothing
 * leaves the device.
 */
class MediaHistory(private val context: Context) {
    private val sessions = context.getSystemService(MediaSessionManager::class.java)
    private val component = ComponentName(context, MediaListener::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val watched = mutableMapOf<MediaSession.Token, MediaController>()
    private val lastSave = mutableMapOf<String, Long>()

    private val changed = MediaSessionManager.OnActiveSessionsChangedListener { list -> track(list ?: emptyList()) }

    fun start() = try {
        sessions.addOnActiveSessionsChangedListener(changed, component, main)
        track(sessions.getActiveSessions(component))
    } catch (e: SecurityException) {
        // Notification access not granted yet: nothing to record.
    }

    fun stop() {
        try { sessions.removeOnActiveSessionsChangedListener(changed) } catch (e: Exception) {}
        for ((token, c) in watched) callbacks.remove(token)?.let(c::unregisterCallback)
        watched.clear()
    }

    private val callbacks = mutableMapOf<MediaSession.Token, MediaController.Callback>()

    private fun track(list: List<MediaController>) {
        val live = list.map { it.sessionToken }.toSet()
        for (token in watched.keys.toList() - live) {
            watched.remove(token)?.let { c -> callbacks.remove(token)?.let(c::unregisterCallback) }
        }
        for (c in list) {
            if (c.packageName == context.packageName || c.sessionToken in watched) continue
            val cb = object : MediaController.Callback() {
                override fun onMetadataChanged(metadata: MediaMetadata?) = record(c, force = true)
                override fun onPlaybackStateChanged(state: PlaybackState?) = record(c, force = state?.state != PlaybackState.STATE_PLAYING)
            }
            c.registerCallback(cb, main)
            watched[c.sessionToken] = c
            callbacks[c.sessionToken] = cb
            record(c, force = true)
        }
    }

    /** Save this session's item (at most every 15 s while playing; always on pause / change). */
    private fun record(c: MediaController, force: Boolean) {
        if (!enabled(context)) return // Customise → Remote & behaviour → Remember what I watch
        val meta = c.metadata ?: return
        val title = meta.getString(MediaMetadata.METADATA_KEY_TITLE) ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE) ?: return
        if (title.isBlank()) return
        val key = "${c.packageName}|$title"
        val now = System.currentTimeMillis()
        if (!force && now - (lastSave[key] ?: 0L) < 15_000) return
        lastSave[key] = now

        val st = c.playbackState
        var position = st?.position ?: 0L
        if (st?.state == PlaybackState.STATE_PLAYING && st.lastPositionUpdateTime > 0) {
            position += ((SystemClock.elapsedRealtime() - st.lastPositionUpdateTime) * st.playbackSpeed).toLong()
        }
        val subtitle = meta.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: meta.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
            ?: meta.getString(MediaMetadata.METADATA_KEY_ALBUM)
        val pm = context.packageManager
        val app = try { pm.getApplicationLabel(pm.getApplicationInfo(c.packageName, 0)).toString() } catch (e: Exception) { c.packageName }
        val art = saveArt(key, meta)

        val items = load(context)
        val all = (0 until items.length()).map { items.getJSONObject(it) }
        val prevArt = all.firstOrNull { it.optString("key") == key }?.optString("art")?.takeIf { it.isNotEmpty() }
        val old = all.filter { it.optString("key") != key }
        val item = JSONObject()
            .put("key", key)
            .put("package", c.packageName)
            .put("app", app)
            .put("title", title)
            .put("subtitle", subtitle ?: JSONObject.NULL)
            .put("position", position.coerceAtLeast(0))
            .put("duration", meta.getLong(MediaMetadata.METADATA_KEY_DURATION))
            .put("at", now)
            .put("art", art ?: prevArt ?: JSONObject.NULL)
        val next = JSONArray().put(item)
        old.take(MAX - 1).forEach { next.put(it) }
        prefs(context).edit().putString(KEY, next.toString()).apply()
    }

    private val fetching = mutableSetOf<String>()

    /**
     * Artwork to a small JPEG (once per item); returns its path. When the app only gives a link
     * (Hotstar, Prime Video, Netflix…), it downloads in the background and the item gets its
     * picture a moment later.
     */
    private fun saveArt(key: String, meta: MediaMetadata): String? {
        val file = File(File(context.filesDir, "history").apply { mkdirs() }, "${key.hashCode().toUInt()}.jpg")
        if (file.exists()) return file.path
        ArtFetch.bitmapOf(meta)?.let { return write(file, it) }
        val uri = ArtFetch.uriOf(meta) ?: return null
        if (!fetching.add(key)) return null
        ArtFetch.async {
            val path = ArtFetch.load(context, uri, 960)?.let { write(file, it) }
            main.post {
                fetching.remove(key)
                if (path != null) setArt(key, path)
            }
        }
        return null
    }

    private fun write(file: File, bmp: Bitmap): String? = try {
        file.outputStream().use { ArtFetch.fit(bmp, 960).compress(Bitmap.CompressFormat.JPEG, 85, it) }
        file.path
    } catch (e: Exception) {
        null
    }

    /** Gives a saved item its downloaded picture. */
    private fun setArt(key: String, path: String) {
        val items = load(context)
        for (i in 0 until items.length()) {
            val o = items.getJSONObject(i)
            if (o.optString("key") == key) o.put("art", path)
        }
        prefs(context).edit().putString(KEY, items.toString()).apply()
    }

    companion object {
        private const val KEY = "items"
        private const val MAX = 20

        private fun prefs(c: Context) = c.getSharedPreferences("one_watch_history", Context.MODE_PRIVATE)
        private fun load(c: Context) = try { JSONArray(prefs(c).getString(KEY, "[]")) } catch (e: Exception) { JSONArray() }

        /** Newest first, as maps for Flutter. */
        fun read(c: Context): List<Map<String, Any?>> {
            val a = load(c)
            return (0 until a.length()).map { i ->
                val o = a.getJSONObject(i)
                o.keys().asSequence().associateWith { k -> o.get(k).takeUnless { it == JSONObject.NULL } }
            }
        }

        fun enabled(c: Context) = prefs(c).getBoolean("enabled", true)
        fun setEnabled(c: Context, on: Boolean) = prefs(c).edit().putBoolean("enabled", on).apply()

        fun clear(c: Context) {
            prefs(c).edit().remove(KEY).apply()
            File(c.filesDir, "history").listFiles()?.forEach { it.delete() }
        }

        fun remove(c: Context, key: String) {
            val a = load(c)
            val keep = JSONArray()
            for (i in 0 until a.length()) a.getJSONObject(i).let { o ->
                if (o.optString("key") != key) keep.put(o) else o.optString("art").takeIf { it.isNotEmpty() }?.let { File(it).delete() }
            }
            prefs(c).edit().putString(KEY, keep.toString()).apply()
        }
    }
}
