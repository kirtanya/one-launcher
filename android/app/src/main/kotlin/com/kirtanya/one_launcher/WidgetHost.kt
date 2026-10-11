package com.kirtanya.one_launcher

import android.app.Activity
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.os.UserManager
import android.util.SizeF
import android.view.View
import android.widget.FrameLayout
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Hosts Android app widgets (like the Pixel launcher does) so the Flutter UI can show them as
 * pages in the top carousel.
 *  - listWidgetProviders / getWidgetPreview: what can be added
 *  - addWidget: allocate an id, ask the user to allow binding if needed, run the widget's own
 *    setup screen if it has one; resolves to the new id (or null if cancelled)
 *  - removeWidget: free the id
 *  - the "one_launcher/appwidget" platform view shows a widget by id
 */
class WidgetHost(private val activity: Activity) {
    companion object {
        const val HOST_ID = 1024
        const val REQ_BIND = 41
        const val REQ_CONFIGURE = 42
        const val VIEW_TYPE = "one_launcher/appwidget"
    }

    private val manager = AppWidgetManager.getInstance(activity)
    private val host = AppWidgetHost(activity.applicationContext, HOST_ID)
    private val users = activity.getSystemService(UserManager::class.java)
    private val worker = Executors.newSingleThreadExecutor()

    private class Pending(val id: Int, val result: MethodChannel.Result)
    private var pending: Pending? = null

    fun start() = try { host.startListening() } catch (e: Exception) {}
    fun stop() = try { host.stopListening() } catch (e: Exception) {}

    /** Returns true if it handled the call. */
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "listWidgetProviders" -> worker.execute {
                val list = providers()
                activity.runOnUiThread { result.success(list) }
            }
            "getWidgetPreview" -> {
                val provider = call.argument<String>("provider")!!
                val serial = (call.argument<Number>("serial") ?: 0).toLong()
                worker.execute {
                    val bytes = preview(provider, serial)
                    activity.runOnUiThread { result.success(bytes) }
                }
            }
            "addWidget" -> add(call.argument<String>("provider")!!, (call.argument<Number>("serial") ?: 0).toLong(), result)
            "removeWidget" -> {
                host.deleteAppWidgetId(call.argument<Number>("id")!!.toInt())
                result.success(true)
            }
            else -> return false
        }
        return true
    }

    // ---- What can be added -------------------------------------------------------------

    private fun providers(): List<Map<String, Any?>> {
        val me = Process.myUserHandle()
        val pm = activity.packageManager
        val out = mutableListOf<Map<String, Any?>>()
        for (user in users.userProfiles) {
            val serial = users.getSerialNumberForUser(user)
            for (info in manager.getInstalledProvidersForProfile(user)) {
                val pkg = info.provider.packageName
                val appLabel = try { pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString() } catch (e: Exception) { pkg }
                out += mapOf(
                    "provider" to info.provider.flattenToString(),
                    "serial" to serial,
                    "work" to (user != me),
                    "package" to (if (user != me) "$pkg@$serial" else pkg),
                    "label" to info.loadLabel(pm),
                    "app" to appLabel,
                    // Grid size the widget asks for (Android 12+), else estimated from its min size.
                    "cols" to (if (Build.VERSION.SDK_INT >= 31 && info.targetCellWidth > 0) info.targetCellWidth else cells(info.minWidth)),
                    "rows" to (if (Build.VERSION.SDK_INT >= 31 && info.targetCellHeight > 0) info.targetCellHeight else cells(info.minHeight)),
                )
            }
        }
        return out.sortedWith(compareBy({ (it["app"] as String).lowercase() }, { it["label"] as String }))
    }

    private fun cells(px: Int): Int {
        val dp = px / activity.resources.displayMetrics.density
        return ((dp + 30) / 70).toInt().coerceIn(1, 5)
    }

    private fun preview(flat: String, serial: Long): ByteArray? = try {
        val user = users.getUserForSerialNumber(serial) ?: Process.myUserHandle()
        val info = manager.getInstalledProvidersForProfile(user).firstOrNull { it.provider.flattenToString() == flat }
        val d = info?.loadPreviewImage(activity, 0) ?: info?.loadIcon(activity, 0)
        if (d == null) null else {
            val max = 360f
            val w = d.intrinsicWidth.coerceAtLeast(1)
            val h = d.intrinsicHeight.coerceAtLeast(1)
            val s = minOf(1f, max / maxOf(w, h))
            val bmp = Bitmap.createBitmap((w * s).toInt().coerceAtLeast(1), (h * s).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
            d.setBounds(0, 0, bmp.width, bmp.height)
            d.draw(Canvas(bmp))
            ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        }
    } catch (e: Exception) {
        null
    }

    // ---- Adding: bind (with the user's OK) → configure → done ----------------------------

    private fun add(flat: String, serial: Long, result: MethodChannel.Result) {
        pending?.let { cancel() }
        val provider = ComponentName.unflattenFromString(flat) ?: return result.success(null)
        val user = users.getUserForSerialNumber(serial) ?: Process.myUserHandle()
        val id = host.allocateAppWidgetId()
        pending = Pending(id, result)
        if (manager.bindAppWidgetIdIfAllowed(id, user, provider, null)) {
            configure()
        } else {
            // First time: Android asks "Allow One Launcher to create widgets…?"
            activity.startActivityForResult(
                Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, provider)
                    .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER_PROFILE, user),
                REQ_BIND,
            )
        }
    }

    private fun configure() {
        val p = pending ?: return
        val info = manager.getAppWidgetInfo(p.id)
        val optional = Build.VERSION.SDK_INT >= 28 &&
            (info?.widgetFeatures ?: 0) and AppWidgetProviderInfo.WIDGET_FEATURE_CONFIGURATION_OPTIONAL != 0
        if (info?.configure != null && !optional) {
            try {
                host.startAppWidgetConfigureActivityForResult(activity, p.id, 0, REQ_CONFIGURE, null)
                return
            } catch (e: Exception) {
                // Some setup screens can't be started by launchers; add the widget as it is.
            }
        }
        finish()
    }

    private fun finish() {
        val p = pending ?: return
        pending = null
        p.result.success(p.id)
    }

    private fun cancel() {
        val p = pending ?: return
        pending = null
        host.deleteAppWidgetId(p.id)
        p.result.success(null)
    }

    /** Called from MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        when (requestCode) {
            REQ_BIND -> if (resultCode == Activity.RESULT_OK) configure() else cancel()
            REQ_CONFIGURE -> if (resultCode == Activity.RESULT_OK) finish() else cancel()
            else -> return false
        }
        return true
    }

    // ---- Showing a widget ----------------------------------------------------------------

    val factory = object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            val id = ((args as? Map<*, *>)?.get("id") as? Number)?.toInt() ?: -1
            return WidgetPlatformView(id)
        }
    }

    private inner class WidgetPlatformView(id: Int) : PlatformView {
        private var hostView: AppWidgetHostView? = null

        // Tells the widget its real size (in dp) whenever the page changes size, so it picks
        // the right layout.
        private val frame = object : FrameLayout(activity) {
            override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
                super.onSizeChanged(w, h, oldw, oldh)
                val v = hostView ?: return
                val d = resources.displayMetrics.density
                val wd = w / d
                val hd = h / d
                if (Build.VERSION.SDK_INT >= 31) {
                    v.updateAppWidgetSize(Bundle(), listOf(SizeF(wd, hd)))
                } else {
                    @Suppress("DEPRECATION")
                    v.updateAppWidgetSize(null, wd.toInt(), hd.toInt(), wd.toInt(), hd.toInt())
                }
            }
        }

        init {
            val info = manager.getAppWidgetInfo(id)
            if (info != null) {
                hostView = host.createView(activity, id, info).also {
                    frame.addView(it, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
                }
            }
        }

        override fun getView(): View = frame
        override fun dispose() {
            frame.removeAllViews()
        }
    }
}
