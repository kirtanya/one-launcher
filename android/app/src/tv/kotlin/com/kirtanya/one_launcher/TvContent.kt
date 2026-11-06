package com.kirtanya.one_launcher

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.media.tv.TvContract
import android.net.Uri
import android.os.Build
import java.io.File

/**
 * Shows and films from the streaming apps, where Android lets a launcher see them.
 *
 * Apps publish "Continue watching" (Watch Next) and their own rows (preview channels) to the
 * TV's content provider. Android only shows other apps' entries to the TV's *system* launcher
 * (ACCESS_ALL_EPG_DATA is a system permission), so on most TVs these come back empty and the
 * home screen simply leaves those rows out. Where a TV does allow it, they appear.
 */
class TvContent(private val activity: Activity) {
    private companion object {
        const val MAX_CACHE = 40L * 1024 * 1024
    }

    private val resolver get() = activity.contentResolver

    fun watchNext(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < 26) return emptyList()
        return query(TvContract.WatchNextPrograms.CONTENT_URI) { c ->
            program(c) + mapOf(
                "lastWatched" to c.long("last_engagement_time_utc_millis"),
                "type" to c.int("watch_next_type"), // 0 continue, 1 next episode, 2 new, 3 watchlist
            )
        }.sortedByDescending { it["lastWatched"] as Long? ?: 0L }.take(20)
    }

    /** Preview channels ("rows" the apps publish), each with its programs. */
    fun channels(): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < 26) return emptyList()
        val channels = query(TvContract.Channels.CONTENT_URI) { c ->
            if (c.str("type") != TvContract.Channels.TYPE_PREVIEW || c.int("browsable") == 0) null
            else mapOf("id" to c.long("_id"), "name" to c.str("display_name"), "package" to c.str("package_name"))
        }
        if (channels.isEmpty()) return emptyList()
        val programs = query(TvContract.PreviewPrograms.CONTENT_URI) { c ->
            if (c.int("browsable") == 0) null else program(c) + mapOf("channel" to c.long("channel_id"), "weight" to c.int("weight"))
        }.groupBy { it["channel"] }
        return channels.mapNotNull { ch ->
            val list = programs[ch["id"]]?.sortedByDescending { it["weight"] as Int? ?: 0 } ?: return@mapNotNull null
            ch + mapOf("programs" to list.take(20))
        }
    }

    private fun program(c: Cursor): Map<String, Any?> = mapOf(
        "id" to c.long("_id").toString(),
        "package" to c.str("package_name"),
        "title" to c.str("title"),
        "episodeTitle" to c.str("episode_title"),
        "season" to c.str("season_display_number"),
        "episode" to c.str("episode_display_number"),
        "description" to (c.str("short_description") ?: c.str("long_description")),
        "poster" to c.str("poster_art_uri"),
        "thumbnail" to c.str("thumbnail_uri"),
        "position" to c.long("last_playback_position_millis"),
        "duration" to c.long("duration_millis"),
        "intent" to c.str("intent_uri"),
    )

    /** Opens a program in its app (the deep link the app published). */
    fun open(intentUri: String?, pkg: String?): Boolean {
        val intent = try {
            intentUri?.let { Intent.parseUri(it, Intent.URI_INTENT_SCHEME) }
        } catch (e: Exception) {
            null
        } ?: pkg?.let { activity.packageManager.getLeanbackLaunchIntentForPackage(it) ?: activity.packageManager.getLaunchIntentForPackage(it) }
        return try {
            activity.startActivity(intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) ?: return false)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Artwork from a program (https, content:// or android.resource://), at most [maxWidth] wide, as JPEG.
     * Kept in cacheDir/art (keyed by sha1(uri + width), ~40 MB, oldest deleted first) so a cold start
     * doesn't fetch and re-encode every backdrop again.
     */
    fun image(uri: String, maxWidth: Int): ByteArray? {
        val dir = File(activity.cacheDir, "art")
        val file = File(dir, sha1("$uri|$maxWidth"))
        try {
            if (file.isFile) {
                file.setLastModified(System.currentTimeMillis())
                return file.readBytes()
            }
        } catch (e: Exception) {
        }
        // Full-screen pictures (Customise → Picture quality) show their JPEG edges at 88; 92 doesn't.
        val bytes = ArtFetch.loadJpeg(activity, uri, maxWidth, 92) ?: return null
        try {
            dir.mkdirs()
            val tmp = File(dir, file.name + ".tmp")
            tmp.writeBytes(bytes)
            if (!tmp.renameTo(file)) tmp.delete()
            trim(dir)
        } catch (e: Exception) {
        }
        return bytes
    }

    private fun sha1(s: String) = java.security.MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    @Synchronized
    private fun trim(dir: File) {
        val files = dir.listFiles() ?: return
        var total = files.sumOf { it.length() }
        if (total <= MAX_CACHE) return
        for (f in files.sortedBy { it.lastModified() }) {
            if (total <= MAX_CACHE * 3 / 4) break
            total -= f.length()
            f.delete()
        }
    }

    private fun <T> query(uri: Uri, map: (Cursor) -> T?): List<T> = try {
        resolver.query(uri, null, null, null, null)?.use { c ->
            buildList { while (c.moveToNext()) map(c)?.let { add(it) } }
        } ?: emptyList()
    } catch (e: Exception) {
        emptyList() // no permission / no TV provider on this device
    }

    private fun Cursor.str(col: String): String? = getColumnIndex(col).let { if (it < 0 || isNull(it)) null else getString(it) }
    private fun Cursor.long(col: String): Long? = getColumnIndex(col).let { if (it < 0 || isNull(it)) null else getLong(it) }
    private fun Cursor.int(col: String): Int? = getColumnIndex(col).let { if (it < 0 || isNull(it)) null else getInt(it) }
}
