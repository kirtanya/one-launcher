package com.kirtanya.one_launcher

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * One Stream (the user's own streaming app, com.kirtanya.reel): search, Continue watching and
 * watchlist read straight from its ContentProvider, on this device — nothing goes to a cloud.
 * Its provider checks the caller's package + signing certificate itself (SecurityException if not us).
 * Not installed / refused → [available] is false and every query is empty (features hide).
 * Used by both the phone (MainActivity) and the TV (TvActivity).
 */
class OneStream(private val context: Context) {
    companion object {
        const val PACKAGE = "com.kirtanya.reel"
        const val AUTHORITY = "com.kirtanya.reel.launcher"
    }

    // Queries run off the main thread; search goes to the network inside One Stream (a few seconds).
    // Cached (grows as needed): a waiting call never starves the query it waits on.
    private val pool = Executors.newCachedThreadPool()
    private val main = Handler(Looper.getMainLooper())

    fun installed(): Boolean = try {
        context.packageManager.getPackageInfo(PACKAGE, 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    private fun resolves(): Boolean = try {
        context.packageManager.resolveContentProvider(AUTHORITY, 0) != null
    } catch (e: Exception) {
        false
    }

    /** Installed, its provider resolves, and it answers us (/info; a SecurityException = not for us). */
    fun available(): Boolean = installed() && resolves() && rowsOf("/info", emptyMap()) != null

    /** Rows of /path?params as column → value maps; empty on any failure (incl. SecurityException). */
    fun query(path: String, params: Map<String, String>): List<Map<String, Any?>> =
        if (resolves()) rowsOf(path, params) ?: emptyList() else emptyList()

    // null = refused or failed.
    private fun rowsOf(path: String, params: Map<String, String>): List<Map<String, Any?>>? {
        val uri = Uri.Builder().scheme("content").authority(AUTHORITY).path(path).apply {
            params.forEach { (k, v) -> appendQueryParameter(k, v) }
        }.build()
        return try {
            context.contentResolver.query(uri, null, null, null, null)?.use(::rows)
        } catch (e: Exception) {
            null
        }
    }

    private fun rows(c: Cursor): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        while (c.moveToNext()) {
            val row = HashMap<String, Any?>()
            for (i in 0 until c.columnCount) {
                row[c.getColumnName(i)] = when (c.getType(i)) {
                    Cursor.FIELD_TYPE_INTEGER -> c.getLong(i)
                    Cursor.FIELD_TYPE_FLOAT -> c.getDouble(i)
                    Cursor.FIELD_TYPE_STRING -> c.getString(i)
                    else -> null
                }
            }
            out.add(row)
        }
        return out
    }

    /** Opens a onestream:// link in One Stream itself. */
    fun open(link: String): Boolean = try {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(link)).setPackage(PACKAGE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (e: Exception) {
        false
    }

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "oneStreamAvailable" -> pool.execute {
                val ok = available()
                main.post { result.success(ok) }
            }
            // {path, params, timeoutMs}: a slow search answers empty rather than hanging the UI.
            "oneStream" -> {
                val path = call.argument<String>("path") ?: "/info"
                val params = (call.argument<Map<String, Any?>>("params") ?: emptyMap())
                    .mapNotNull { (k, v) -> v?.let { k to it.toString() } }.toMap()
                val timeout = (call.argument<Number>("timeoutMs") ?: 8000).toLong()
                pool.execute {
                    val task = pool.submit<List<Map<String, Any?>>> { query(path, params) }
                    val rows = try {
                        task.get(timeout, TimeUnit.MILLISECONDS)
                    } catch (e: Exception) {
                        task.cancel(true)
                        emptyList()
                    }
                    main.post { result.success(rows) }
                }
            }
            "oneStreamOpen" -> result.success(open(call.argument<String>("link") ?: ""))
            else -> return false
        }
        return true
    }
}
