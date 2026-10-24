package com.kirtanya.one_launcher

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaMetadata
import android.net.Uri
import android.os.Build
import android.util.Log
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * Artwork from other apps, however they hand it over.
 *
 * Some apps (YouTube) put the picture itself in their media session; most streaming apps
 * (Hotstar, Prime Video, Netflix) only give a link to it: an https address on their image
 * server, or a content:// / android.resource:// uri. Their image servers can also redirect
 * (often http → https, which Java won't follow by itself) or refuse requests that don't look
 * like they come from a browser or player. This loads all of those.
 */
object ArtFetch {
    private const val TAG = "OneArt"
    private val pool = Executors.newFixedThreadPool(2)

    /** Runs [block] off the main thread (network / decoding). */
    fun async(block: () -> Unit) = pool.execute(block)

    /** The picture a media session carries itself, if any. */
    fun bitmapOf(meta: MediaMetadata?): Bitmap? = meta?.run {
        getBitmap(MediaMetadata.METADATA_KEY_ART) ?: getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART)
            ?: getBitmap(MediaMetadata.METADATA_KEY_DISPLAY_ICON) ?: description?.iconBitmap
    }

    /** The link a media session gives instead of a picture, if any. */
    fun uriOf(meta: MediaMetadata?): String? = meta?.run {
        listOf(MediaMetadata.METADATA_KEY_ART_URI, MediaMetadata.METADATA_KEY_ALBUM_ART_URI, MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI)
            .firstNotNullOfOrNull { k -> getString(k)?.takeIf { it.isNotBlank() } }
            ?: description?.iconUri?.toString()?.takeIf { it.isNotBlank() }
    }

    /** Downloads / opens [uri] and decodes it, at most [maxWidth] wide. Call off the main thread. */
    fun load(context: Context, uri: String, maxWidth: Int): Bitmap? = try {
        val raw = open(context, Uri.parse(uri))?.use { it.readBytes() }
        raw?.let { decode(it, maxWidth) }.also { if (it == null) Log.w(TAG, "no picture from $uri (${raw?.size ?: 0} bytes)") }
    } catch (e: Throwable) {
        Log.w(TAG, "couldn't load $uri: $e")
        null
    }

    /** Decodes JPEG / PNG / WebP (BitmapFactory), then anything else the system knows (HEIF, AVIF…). */
    fun decode(raw: ByteArray, maxWidth: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(raw, 0, raw.size, bounds)
        if (bounds.outWidth > 0) {
            var sample = 1
            while (bounds.outWidth / (sample * 2) >= maxWidth) sample *= 2
            BitmapFactory.decodeByteArray(raw, 0, raw.size, BitmapFactory.Options().apply { inSampleSize = sample })?.let { return fit(it, maxWidth) }
        }
        if (Build.VERSION.SDK_INT >= 28) {
            return try {
                ImageDecoder.decodeBitmap(ImageDecoder.createSource(ByteBuffer.wrap(raw))) { d, info, _ ->
                    d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    if (info.size.width > maxWidth) d.setTargetSize(maxWidth, maxOf(1, info.size.height * maxWidth / info.size.width))
                }
            } catch (e: Exception) {
                null
            }
        }
        return null
    }

    /** Scales [bmp] down to [maxWidth] (never up), keeping its shape. */
    fun fit(bmp: Bitmap, maxWidth: Int): Bitmap {
        val w = minOf(maxWidth, bmp.width)
        return if (w == bmp.width) bmp else Bitmap.createScaledBitmap(bmp, w, maxOf(1, bmp.height * w / bmp.width), true)
    }

    private fun open(context: Context, uri: Uri): InputStream? = when (uri.scheme?.lowercase()) {
        "http", "https" -> http(uri.toString())
        null -> null
        else -> context.contentResolver.openInputStream(uri) // content://, android.resource://, file://
    }

    /** GET with redirects followed by hand (including http ↔ https) and player-like headers. */
    private fun http(start: String): InputStream? {
        var url = start
        repeat(6) {
            val c = (URL(url).openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 6000
                readTimeout = 10000
                setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android ${Build.VERSION.RELEASE}; Android TV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36")
                setRequestProperty("Accept", "image/webp,image/jpeg,image/png,image/*;q=0.8,*/*;q=0.5")
            }
            when (val code = c.responseCode) {
                in 200..299 -> return c.inputStream
                301, 302, 303, 307, 308 -> {
                    val next = c.getHeaderField("Location") ?: return null.also { c.disconnect() }
                    url = URL(URL(url), next).toString()
                    c.disconnect()
                }
                else -> {
                    Log.w(TAG, "HTTP $code for $url")
                    c.disconnect()
                    return null
                }
            }
        }
        return null
    }
}
