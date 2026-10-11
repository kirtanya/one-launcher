package com.kirtanya.one_launcher

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * "Now playing" for the top carousel: finds the active music session, tells Flutter whenever
 * the track or play state changes, and passes play/pause/skip back. Listens only between
 * start() and stop() (while the launcher is on screen).
 */
/** [artWidth]/[square]: the phone wants small square album art; the TV wants wide backdrops. */
class MediaWatcher(
    private val activity: Activity,
    private val artWidth: Int = 256,
    private val square: Boolean = true,
    private val push: (Map<String, Any?>) -> Unit,
) {
    private val sessions = activity.getSystemService(MediaSessionManager::class.java)
    private val component = ComponentName(activity, MediaListener::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var controller: MediaController? = null
    private var listening = false

    // Album art is re-encoded only when the track changes.
    private var artKey: String? = null
    private var artBytes: ByteArray? = null

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = send()
        override fun onMetadataChanged(metadata: MediaMetadata?) = send()
        override fun onSessionDestroyed() = refresh()
    }

    private val sessionsChanged = MediaSessionManager.OnActiveSessionsChangedListener { list -> pick(list ?: emptyList()) }

    fun granted(): Boolean {
        val enabled = Settings.Secure.getString(activity.contentResolver, "enabled_notification_listeners") ?: return false
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == component }
    }

    fun start() {
        if (listening || !granted()) return send()
        try {
            sessions.addOnActiveSessionsChangedListener(sessionsChanged, component, main)
            listening = true
            refresh()
        } catch (e: SecurityException) {
            send()
        }
    }

    fun stop() {
        if (listening) sessions.removeOnActiveSessionsChangedListener(sessionsChanged)
        listening = false
        controller?.unregisterCallback(callback)
        controller = null
    }

    private fun refresh() = try {
        pick(sessions.getActiveSessions(component))
    } catch (e: SecurityException) {
        send()
    }

    /** The playing session if there is one, else the most recent. */
    private fun pick(list: List<MediaController>) {
        val best = list.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: list.firstOrNull()
        if (best?.sessionToken != controller?.sessionToken) {
            controller?.unregisterCallback(callback)
            controller = best
            best?.registerCallback(callback, main)
        }
        send()
    }

    private fun send() = push(state())

    fun state(): Map<String, Any?> {
        if (!granted()) return mapOf("granted" to false)
        val c = controller ?: return mapOf("granted" to true, "active" to false)
        val meta = c.metadata
        val st = c.playbackState
        val playing = st?.state == PlaybackState.STATE_PLAYING
        val title = meta?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: meta?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
        val artist = meta?.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: meta?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)
            ?: meta?.getString(MediaMetadata.METADATA_KEY_DISPLAY_SUBTITLE)
        // Position right now (the session reports where it was at its last update).
        var position = st?.position ?: 0L
        if (playing && st != null && st.lastPositionUpdateTime > 0) {
            position += ((SystemClock.elapsedRealtime() - st.lastPositionUpdateTime) * st.playbackSpeed).toLong()
        }
        val pm = activity.packageManager
        val appLabel = try { pm.getApplicationLabel(pm.getApplicationInfo(c.packageName, 0)).toString() } catch (e: Exception) { c.packageName }
        return mapOf(
            "granted" to true,
            "active" to (title != null),
            "package" to c.packageName,
            "app" to appLabel,
            "title" to title,
            "artist" to artist,
            "art" to art(meta, "$title|$artist|${c.packageName}"),
            "playing" to playing,
            "position" to position,
            "duration" to (meta?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L),
            "speed" to (st?.playbackSpeed ?: 1f).toDouble(),
            "canPrev" to ((st?.actions ?: 0L) and PlaybackState.ACTION_SKIP_TO_PREVIOUS != 0L),
            "canNext" to ((st?.actions ?: 0L) and PlaybackState.ACTION_SKIP_TO_NEXT != 0L),
        )
    }

    private fun art(meta: MediaMetadata?, key: String): ByteArray? {
        if (key == artKey) return artBytes
        artKey = key
        val bmp = meta?.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: meta?.getBitmap(MediaMetadata.METADATA_KEY_ART)
            ?: meta?.getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON)
        artBytes = bmp?.let {
            if (!square) {
                // Keep the picture's shape (video stills are wide), just cap its size.
                val w = minOf(artWidth, it.width)
                val scaled = Bitmap.createScaledBitmap(it, w, maxOf(1, it.height * w / it.width), true)
                return@let ByteArrayOutputStream().also { o -> scaled.compress(Bitmap.CompressFormat.JPEG, 88, o) }.toByteArray()
            }
            val size = artWidth
            val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            // Centre-crop into a square.
            val s = minOf(it.width, it.height)
            val src = android.graphics.Rect((it.width - s) / 2, (it.height - s) / 2, (it.width + s) / 2, (it.height + s) / 2)
            Canvas(out).drawBitmap(it, src, android.graphics.Rect(0, 0, size, size), null)
            ByteArrayOutputStream().also { o -> out.compress(Bitmap.CompressFormat.PNG, 100, o) }.toByteArray()
        }
        return artBytes
    }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        val t = controller?.transportControls
        when (call.method) {
            "mediaState" -> result.success(state())
            "mediaPlayPause" -> {
                if (controller?.playbackState?.state == PlaybackState.STATE_PLAYING) t?.pause() else t?.play()
                result.success(true)
            }
            "mediaNext" -> { t?.skipToNext(); result.success(true) }
            "mediaPrev" -> { t?.skipToPrevious(); result.success(true) }
            "mediaOpen" -> {
                val c = controller
                try {
                    c?.sessionActivity?.send() ?: activity.packageManager.getLaunchIntentForPackage(c?.packageName ?: "")
                        ?.let { activity.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
                } catch (e: Exception) {
                    c?.packageName?.let { pkg -> activity.packageManager.getLaunchIntentForPackage(pkg)?.let { activity.startActivity(it) } }
                }
                result.success(true)
            }
            "openNotificationAccess" -> {
                val intent = if (Build.VERSION.SDK_INT >= 30) {
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                        .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, component.flattenToString())
                } else {
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                }
                try {
                    activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                } catch (e: Exception) {
                    activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                result.success(true)
            }
            else -> return false
        }
        return true
    }
}
