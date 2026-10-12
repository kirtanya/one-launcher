package com.kirtanya.one_launcher

import android.app.SearchManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * One Launcher TV's bridge to Android (channel "one_launcher/tv").
 * TV apps announce themselves with LEANBACK_LAUNCHER and a 16:9 banner; phone-style apps
 * that only have LAUNCHER are listed too (they open fine, just with their icon).
 */
class TvActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private val worker = Executors.newSingleThreadExecutor()
    private val images = Executors.newFixedThreadPool(3) // artwork downloads in parallel
    private val main = Handler(Looper.getMainLooper())
    private val content by lazy { TvContent(this) }
    // What's playing / paused right now (needs Notification access, like the phone's Now playing).
    private val media by lazy { MediaWatcher(this, artWidth = 960, square = false) { state -> if (::channel.isInitialized) channel.invokeMethod("mediaChanged", state) } }

    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (::channel.isInitialized) channel.invokeMethod("appsChanged", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "one_launcher/tv")
        channel.setMethodCallHandler { call, result ->
            if (media.handle(call, result)) return@setMethodCallHandler
            when (call.method) {
                "getWatchNext" -> worker.execute {
                    val list = content.watchNext()
                    main.post { result.success(list) }
                }
                "getChannels" -> worker.execute {
                    val list = content.channels()
                    main.post { result.success(list) }
                }
                "getImage" -> {
                    val uri = call.argument<String>("uri")!!
                    val w = call.argument<Int>("width") ?: 480
                    images.execute {
                        val bytes = content.image(uri, w)
                        main.post { result.success(bytes) }
                    }
                }
                "openProgram" -> result.success(content.open(call.argument<String>("intent"), call.argument<String>("package")))
                "getApps" -> worker.execute {
                    val apps = loadApps()
                    main.post { result.success(apps) }
                }
                "getArt" -> {
                    val pkg = call.argument<String>("package")!!
                    worker.execute {
                        val art = loadArt(pkg)
                        main.post { result.success(art) }
                    }
                }
                "getBackdrop" -> {
                    val pkg = call.argument<String>("package")!!
                    images.execute {
                        val bytes = loadBackdrop(pkg)
                        main.post { result.success(bytes) }
                    }
                }
                // Apps that take a search ("Search in JioHotstar…"); only ones with a home-screen entry.
                "searchTargets" -> {
                    val launchable = loadApps().map { it["package"] }.toSet()
                    val pkgs = packageManager.queryIntentActivities(Intent(Intent.ACTION_SEARCH), 0)
                        .map { it.activityInfo.packageName }.distinct().filter { it in launchable && it != packageName }
                    result.success(pkgs)
                }
                "searchIn" -> {
                    val q = call.argument<String>("query") ?: ""
                    result.success(open(Intent(Intent.ACTION_SEARCH).setPackage(call.argument<String>("package")).putExtra(SearchManager.QUERY, q)))
                }
                // A link (e.g. a YouTube trailer); opened in that app if it's installed.
                "openUri" -> {
                    val i = Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("uri")))
                    val pkg = call.argument<String>("package")
                    result.success((pkg != null && open(Intent(i).setPackage(pkg))) || open(i))
                }
                // Google TV's own search: shows films & shows from every streaming app.
                "searchEverywhere" -> {
                    val q = call.argument<String>("query") ?: ""
                    result.success(
                        open(Intent("android.search.action.GLOBAL_SEARCH").putExtra(SearchManager.QUERY, q)) ||
                            open(Intent(Intent.ACTION_ASSIST).putExtra(SearchManager.QUERY, q)),
                    )
                }
                "launch" -> result.success(launch(call.argument<String>("package")!!))
                "appInfo" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:" + call.argument<String>("package")))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "uninstall" -> {
                    startActivity(Intent(Intent.ACTION_DELETE)
                        .setData(Uri.parse("package:" + call.argument<String>("package")))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "getHistory" -> result.success(MediaHistory.read(this))
                "setHistoryEnabled" -> {
                    MediaHistory.setEnabled(this, call.argument<Boolean>("on") ?: true)
                    result.success(true)
                }
                "clearHistory" -> {
                    MediaHistory.clear(this)
                    result.success(true)
                }
                "removeHistory" -> {
                    MediaHistory.remove(this, call.argument<String>("key")!!)
                    result.success(true)
                }
                "openAction" -> result.success(openAction(call.argument<String>("id")!!))
                "openSettings" -> result.success(open(Intent(Settings.ACTION_SETTINGS)))
                "openHomeSettings" -> result.success(open(Intent(Settings.ACTION_HOME_SETTINGS)) || open(Intent(Settings.ACTION_SETTINGS)))
                "openInputs" -> result.success(open(Intent("com.android.tv.action.VIEW_INPUTS")) || open(Intent(Settings.ACTION_SETTINGS)))
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        registerReceiver(packageReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addDataScheme("package")
        })
    }

    override fun onStart() {
        super.onStart()
        media.start()
    }

    override fun onStop() {
        media.stop()
        super.onStop()
    }

    // Back from an app: "Continue watching" may have changed.
    override fun onResume() {
        super.onResume()
        if (::channel.isInitialized) channel.invokeMethod("resumed", null)
    }

    override fun onDestroy() {
        unregisterReceiver(packageReceiver)
        super.onDestroy()
    }

    // Home pressed on the remote while we're already showing.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME) && ::channel.isInitialized) channel.invokeMethod("homePressed", null)
    }

    private fun loadApps(): List<Map<String, Any>> {
        val pm = packageManager
        val seen = HashSet<String>()
        val out = mutableListOf<Map<String, Any>>()
        // TV apps first, so their entry (tv = true) wins over a phone-style one.
        for ((category, tv) in listOf(Intent.CATEGORY_LEANBACK_LAUNCHER to true, Intent.CATEGORY_LAUNCHER to false)) {
            for (ri in pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(category), 0)) {
                val ai = ri.activityInfo
                val pkg = ai.packageName
                if (pkg == packageName || !seen.add(pkg)) continue
                val app = ai.applicationInfo
                out += mapOf(
                    "package" to pkg,
                    "label" to ri.loadLabel(pm).toString(),
                    "system" to ((app.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                    "category" to (if (Build.VERSION.SDK_INT >= 26) app.category else -1),
                    "installed" to (try { pm.getPackageInfo(pkg, 0).firstInstallTime } catch (e: Exception) { 0L }),
                    "tv" to tv,
                    "banner" to (ai.banner != 0 || app.banner != 0),
                )
            }
        }
        return out
    }

    /** The app's TV banner (320×180) if it has one, else its icon (192×192). */
    private fun loadArt(pkg: String): ByteArray? = try {
        val pm = packageManager
        val ri = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER).setPackage(pkg), 0).firstOrNull()
        val banner = ri?.activityInfo?.loadBanner(pm) ?: pm.getApplicationInfo(pkg, 0).loadBanner(pm)
        val d = banner ?: pm.getApplicationIcon(pkg)
        val (w, h) = if (banner != null) 320 to 180 else 192 to 192
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, w, h)
        d.draw(Canvas(bmp))
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    } catch (e: Exception) {
        null
    }

    /**
     * The app's banner as a soft, out-of-focus wash for the home backdrop: shrunk to 128×72 and
     * blurred here once, so the TV only has to stretch a smooth picture (no live blur per frame).
     */
    private fun loadBackdrop(pkg: String): ByteArray? = try {
        val pm = packageManager
        val ri = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER).setPackage(pkg), 0).firstOrNull()
        val d = ri?.activityInfo?.loadBanner(pm) ?: pm.getApplicationInfo(pkg, 0).loadBanner(pm)
        d?.let {
            val w = 128
            val h = 72
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            it.setBounds(0, 0, w, h)
            it.draw(Canvas(bmp))
            repeat(3) { boxBlur(bmp, 5) } // three box blurs ≈ a gaussian
            ByteArrayOutputStream().also { o -> bmp.compress(Bitmap.CompressFormat.PNG, 100, o) }.toByteArray()
        }
    } catch (e: Exception) {
        null
    }

    private fun boxBlur(bmp: Bitmap, r: Int) {
        val w = bmp.width
        val h = bmp.height
        val src = IntArray(w * h).also { bmp.getPixels(it, 0, w, 0, 0, w, h) }
        val tmp = IntArray(w * h)
        fun pass(from: IntArray, to: IntArray, horizontal: Boolean) {
            val (len, lines) = if (horizontal) w to h else h to w
            for (line in 0 until lines) {
                for (i in 0 until len) {
                    var a = 0; var rr = 0; var g = 0; var b = 0; var n = 0
                    for (k in -r..r) {
                        val j = (i + k).coerceIn(0, len - 1)
                        val p = if (horizontal) from[line * w + j] else from[j * w + line]
                        a += p ushr 24; rr += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; b += p and 0xFF; n++
                    }
                    val out = ((a / n) shl 24) or ((rr / n) shl 16) or ((g / n) shl 8) or (b / n)
                    if (horizontal) to[line * w + i] = out else to[i * w + line] = out
                }
            }
        }
        pass(src, tmp, true)
        pass(tmp, src, false)
        bmp.setPixels(src, 0, w, 0, 0, w, h)
    }

    private fun launch(pkg: String): Boolean {
        val i = packageManager.getLeanbackLaunchIntentForPackage(pkg) ?: packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return open(i)
    }

    /** Quick actions: each tries the TV's own screen first, then a general one, then Settings. */
    private fun openAction(id: String): Boolean {
        fun c(cls: String) = Intent().setClassName("com.android.tv.settings", "com.android.tv.settings.$cls")
        val candidates = when (id) {
            "t:inputs" -> listOf(Intent("com.android.tv.action.VIEW_INPUTS"))
            "t:assistant" -> listOf(Intent(Intent.ACTION_ASSIST), Intent("android.search.action.GLOBAL_SEARCH"))
            "t:wifi" -> listOf(Intent(Settings.ACTION_WIFI_SETTINGS))
            "t:bluetooth" -> listOf(c("accessories.AddAccessoryActivity"), Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
            "t:sound" -> listOf(Intent(Settings.ACTION_SOUND_SETTINGS), c("device.displaysound.DisplaySoundActivity"))
            "t:energy" -> listOf(c("device.eco.EnergyModesActivity"))
            "t:captions" -> listOf(Intent(Settings.ACTION_CAPTIONING_SETTINGS))
            "t:language" -> listOf(Intent(Settings.ACTION_LOCALE_SETTINGS))
            "t:storage" -> listOf(Intent(Settings.ACTION_INTERNAL_STORAGE_SETTINGS))
            "t:datetime" -> listOf(Intent(Settings.ACTION_DATE_SETTINGS))
            "t:accessibility" -> listOf(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
            "t:playstore" -> listOfNotNull(packageManager.getLeanbackLaunchIntentForPackage("com.android.vending"))
            else -> emptyList()
        }
        return candidates.any { open(it) } || open(Intent(Settings.ACTION_SETTINGS))
    }

    private fun open(i: Intent): Boolean = try {
        startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }
}
