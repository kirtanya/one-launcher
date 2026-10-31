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
private const val REQUEST_CLEAR_CACHE = 7101
private const val REQUEST_LISTEN = 7102

class TvActivity : FlutterActivity() {
    companion object {
        const val EXTRA_SEARCH = "com.kirtanya.one_launcher.SEARCH"
    }

    private lateinit var channel: MethodChannel
    private var listening: MethodChannel.Result? = null // Search's mic: waiting for the words
    private val worker = Executors.newSingleThreadExecutor()
    private val images = Executors.newFixedThreadPool(3) // artwork downloads in parallel
    private val net = Executors.newFixedThreadPool(4) // catalog / details requests (artwork keeps its own threads)
    private val main = Handler(Looper.getMainLooper())
    private val content by lazy { TvContent(this) }

    // The Real view's sounds (res/raw): short mechanical clicks, played on the TV itself since
    // TVs usually have system sounds off. Loaded once, quiet, as UI sounds.
    private val sounds by lazy {
        val pool = android.media.SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .build()
        val ids = mapOf(
            "tick" to pool.load(this, R.raw.real_tick, 1),
            "clunk" to pool.load(this, R.raw.real_clunk, 1),
            "thunk" to pool.load(this, R.raw.real_thunk, 1),
        )
        pool to ids
    }
    private val oneStream by lazy { OneStream(this) }
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
            if (oneStream.handle(call, result)) return@setMethodCallHandler
            when (call.method) {
                "sound" -> {
                    val (pool, ids) = sounds
                    ids[call.argument<String>("name")]?.let { pool.play(it, .45f, .45f, 1, 0, 1f) }
                    result.success(null)
                }
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
                // Tiles: the app's own icon (not the banner) and its main colour ("each app's colour").
                "getIcon" -> {
                    val pkg = call.argument<String>("package")!!
                    images.execute {
                        val bytes = loadIcon(pkg)
                        main.post { result.success(bytes) }
                    }
                }
                "getIconColour" -> {
                    val pkg = call.argument<String>("package")!!
                    images.execute {
                        val c = iconColour(pkg)
                        main.post { result.success(c) }
                    }
                }
                // Network for the shows & films catalog (Stremio addons) through Android's own stack —
                // the same one the streaming apps use (Flutter's sockets failed on some TVs).
                // With a "body" it's a POST (YouTube's search).
                "httpGet" -> {
                    val url = call.argument<String>("url")!!
                    val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                    val body = call.argument<String>("body")
                    net.execute {
                        val res = try {
                            (java.net.URL(url).openConnection() as java.net.HttpURLConnection).run {
                                connectTimeout = 8000
                                readTimeout = 12000
                                headers.forEach { (k, v) -> setRequestProperty(k, v) }
                                if (body != null) {
                                    requestMethod = "POST"
                                    doOutput = true
                                    outputStream.use { it.write(body.toByteArray()) }
                                }
                                val code = responseCode
                                val body = (if (code in 200..299) inputStream else errorStream)?.bufferedReader()?.use { it.readText() } ?: ""
                                mapOf("status" to code, "body" to body)
                            }
                        } catch (e: Exception) {
                            mapOf("status" to -1, "body" to (e.message ?: e.javaClass.simpleName))
                        }
                        main.post { result.success(res) }
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
                    result.success(searchIn(call.argument<String>("package")!!, q))
                }
                // A link (e.g. a YouTube trailer); opened in that app if it's installed.
                "openUri" -> {
                    val i = Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("uri")))
                    val pkg = call.argument<String>("package")
                    result.success((pkg != null && open(Intent(i).setPackage(pkg))) || open(i))
                }
                // A show's page: "Watch on …" (WatchHub's official links) and "Open in Nuvio".
                "openLink" -> {
                    val pkg = call.argument<String>("package")
                    result.success(openLink(call.argument<String>("uri"), pkg) || openLink(call.argument<String>("fallback"), pkg))
                }
                "linkHandlers" -> result.success(linkHandlers(call.argument<String>("uri")!!))
                // Where the shows & films catalog is saved.
                "filesDir" -> result.success(filesDir.absolutePath)
                // Google TV's own search: shows films & shows from every streaming app.
                // Search's mic: the TV's speech recogniser → the words ("" if cancelled), or null
                // when the TV has none (Search then opens the Assistant instead).
                "listen" -> {
                    val intent = Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                        .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_WEB_SEARCH)
                        .putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "Search")
                    // Straight to the Google app's voice input (the remote's own voice path): with two
                    // handlers Android asks which one, and Speech Services' newer builds crash on
                    // 32-bit TVs (SIGILL in their on-device model).
                    val katniss = Intent(intent).setPackage("com.google.android.katniss")
                    listening?.success("")
                    listening = result
                    try {
                        startActivityForResult(katniss, REQUEST_LISTEN)
                    } catch (e: Exception) {
                        try {
                            startActivityForResult(intent, REQUEST_LISTEN)
                        } catch (e2: Exception) {
                            listening = null
                            result.success(null)
                        }
                    }
                }
                "searchEverywhere" -> {
                    val q = call.argument<String>("query") ?: ""
                    ShowNameService.googleUntil = android.os.SystemClock.uptimeMillis() + 15_000 // ours to Google: stay there
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
                "showNames" -> result.success(ShowNameService.read(this))
                "takeSearch" -> result.success(pendingSearch.also { pendingSearch = null })
                "log" -> {
                    android.util.Log.i("OneShow", call.argument<String>("message") ?: "")
                    result.success(null)
                }
                "openAccessibility" -> result.success(open(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) || open(Intent(Settings.ACTION_SETTINGS)))
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

    /** Words from the phone's voice search (BrightnessActivity), until the TV home takes them. */
    private var pendingSearch: String? = null

    // Cold start: the channel exists before Dart listens on it, so the words wait for "takeSearch".
    private fun takeSearch(intent: Intent?, cold: Boolean = false) {
        val q = intent?.getStringExtra(EXTRA_SEARCH) ?: return
        intent.removeExtra(EXTRA_SEARCH)
        if (::channel.isInitialized && !cold) channel.invokeMethod("searchFor", q) else pendingSearch = q
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        NowPlayingServer.start(this) // the phone remote's Now playing card
        AlexaRelay.start(this) // "Alexa, ask One TV to search …"
        takeSearch(intent, cold = true)
        ShowNameService.onChange = { if (::channel.isInitialized) channel.invokeMethod("showNamesChanged", null) }
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
        ShowNameService.onChange = null
        unregisterReceiver(packageReceiver)
        super.onDestroy()
    }

    // Home pressed on the remote while we're already showing.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME) && ::channel.isInitialized) channel.invokeMethod("homePressed", null)
        takeSearch(intent)
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

    private fun iconBitmap(pkg: String, size: Int): Bitmap? = try {
        val d = packageManager.getApplicationIcon(pkg)
        Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { b ->
            d.setBounds(0, 0, size, size)
            d.draw(Canvas(b))
        }
    } catch (e: Exception) {
        null
    }

    private fun loadIcon(pkg: String): ByteArray? = iconBitmap(pkg, 192)?.let { b ->
        ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    /** The icon's main colour: the average of its colourful pixels (greys and see-through skipped). */
    private fun iconColour(pkg: String): Int? {
        val b = iconBitmap(pkg, 48) ?: return null
        var r = 0L; var g = 0L; var bl = 0L; var n = 0
        val hsv = FloatArray(3)
        for (y in 0 until 48) for (x in 0 until 48) {
            val p = b.getPixel(x, y)
            if ((p ushr 24) < 200) continue
            android.graphics.Color.colorToHSV(p, hsv)
            if (hsv[1] < .25f || hsv[2] < .2f) continue
            r += (p shr 16) and 0xFF; g += (p shr 8) and 0xFF; bl += p and 0xFF; n++
        }
        if (n < 20) return null
        return (0xFF shl 24) or ((r / n).toInt() shl 16) or ((g / n).toInt() shl 8) or (bl / n).toInt()
    }

    private fun launch(pkg: String): Boolean {
        val i = packageManager.getLeanbackLaunchIntentForPackage(pkg) ?: packageManager.getLaunchIntentForPackage(pkg) ?: return false
        return open(i)
    }

    /** Quick actions: each tries the TV's own screen first, then a general one, then Settings. */
    private fun openAction(id: String): Boolean {
        if (id == "t:boost") return boost()
        fun c(cls: String) = Intent().setClassName("com.android.tv.settings", "com.android.tv.settings.$cls")
        val candidates = when (id) {
            "t:inputs" -> listOf(Intent("com.android.tv.action.VIEW_INPUTS"))
            // Google TV voice search (GLOBAL_SEARCH with no words starts listening).
            "t:assistant" -> listOf(Intent("android.search.action.GLOBAL_SEARCH"), Intent(Intent.ACTION_ASSIST))
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

    /**
     * "Speed up" — what an app may really do to make the TV quicker (Android 14 no longer lets an
     * app stop other apps, so that alone did nothing):
     *  1. One Stream's engine stops if nothing is playing (it keeps a foreground service otherwise);
     *  2. our own caches and memory are freed (the Flutter side drops its images too);
     *  3. every app's cache is cleared through Android's own "Clear app cache?" screen — the user
     *     confirms with the remote (needs All files access, granted once);
     *  4. older Android only: other apps' background processes are stopped.
     * Then it says how much memory and storage are free.
     */
    private fun boost(): Boolean {
        val am = getSystemService(android.app.ActivityManager::class.java)
        fun freeMb(): Long = android.app.ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }.availMem / (1024 * 1024)
        fun freeGb(): String = "%.1f".format(android.os.StatFs(filesDir.path).availableBytes / 1e9)
        val before = freeMb()
        // All apps' caches: Android's own confirmation screen, when we're allowed to open it.
        val clearCaches = Build.VERSION.SDK_INT >= 30 && android.os.Environment.isExternalStorageManager()
        if (clearCaches) {
            try {
                @Suppress("DEPRECATION")
                startActivityForResult(Intent(android.os.storage.StorageManager.ACTION_CLEAR_APP_CACHE), REQUEST_CLEAR_CACHE)
            } catch (_: Exception) {
            }
        }
        Thread {
            // One Stream says what it did: "One Stream stopped", or why not ("A download is running").
            val stream = try {
                contentResolver.call(Uri.parse("content://com.kirtanya.reel.launcher"), "stop_engine", null, null)?.getString("message")
            } catch (_: Exception) {
                null // One Stream missing or older: nothing to stop
            }
            if (Build.VERSION.SDK_INT < 34) {
                val pkgs = (loadApps().mapNotNull { it["package"] as? String }).toSet() - packageName
                for (p in pkgs) {
                    try {
                        am.killBackgroundProcesses(p)
                    } catch (_: Exception) {
                    }
                }
            }
            cacheDir.listFiles()?.forEach { it.deleteRecursively() }
            System.gc()
            Thread.sleep(1500) // Android takes a moment to hand the memory back
            val freed = (freeMb() - before).coerceAtLeast(0)
            runOnUiThread {
                val head = if (freed > 20) "Freed $freed MB" else "Cleaned up"
                android.widget.Toast.makeText(
                    this,
                    "$head · ${freeMb()} MB memory · ${freeGb()} GB storage free" + (stream?.let { "\n$it" } ?: "") +
                        if (clearCaches) "" else "\nAllow All files access to also clear every app's cache",
                    android.widget.Toast.LENGTH_LONG,
                ).show()
            }
        }.start()
        return true
    }

    /**
     * A link from the internet (WatchHub) or our own stremio:///detail/… → a plain "view this"
     * intent: only its address, the app it names (or [pkg]) and its text extras survive — never a
     * named screen, selector, flags or permission grants. Local addresses (file:, content:…) are refused.
     */
    private fun linkIntent(uri: String, pkg: String?): Intent? = try {
        // Some links leave off the closing "end"; Android won't read them without it.
        val fixed = if (uri.startsWith("intent:") && uri.contains("#Intent;") && !uri.endsWith(";end")) uri.trimEnd(';') + ";end" else uri
        val parsed = if (fixed.startsWith("intent:")) Intent.parseUri(fixed, Intent.URI_INTENT_SCHEME) else Intent(Intent.ACTION_VIEW, Uri.parse(fixed))
        val data = parsed.data
        val scheme = data?.scheme?.lowercase()
        if (data == null || scheme == null || scheme in setOf("file", "content", "android.resource", "javascript", "data")) {
            null
        } else {
            Intent(Intent.ACTION_VIEW, data).apply {
                addCategory(Intent.CATEGORY_BROWSABLE)
                (parsed.`package` ?: pkg)?.let { setPackage(it) }
                copyTextExtras(parsed, this)
            }
        }
    } catch (e: Exception) {
        null
    }

    @Suppress("DEPRECATION") // Bundle.get: any type; only text is copied
    private fun copyTextExtras(from: Intent, to: Intent) {
        val ex = from.extras ?: return
        for (k in ex.keySet()) (ex.get(k) as? String)?.let { to.putExtra(k, it) }
    }

    private fun openLink(uri: String?, pkg: String?): Boolean {
        val i = linkIntent(uri ?: return false, pkg) ?: return false
        if (open(Intent(i))) return true
        // Some TV apps take their links without the "browsable" mark; only try that inside a named app.
        return i.`package` != null && open(i.apply { removeCategory(Intent.CATEGORY_BROWSABLE) })
    }

    /** An app's own search for [q]. Some (JioHotstar) leave the DEFAULT category off their search
     *  screen, so a plain request to the package matches nothing (-91): address that screen by
     *  name then. Clear-top delivers it even when the app is already open on something else. */
    private fun searchIn(pkg: String, q: String): Boolean {
        val base = Intent(Intent.ACTION_SEARCH).setPackage(pkg).putExtra(SearchManager.QUERY, q)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        if (open(Intent(base))) return true
        val target = try {
            packageManager.queryIntentActivities(base, 0).firstOrNull()?.activityInfo
        } catch (_: Exception) {
            null
        } ?: return false
        return open(Intent(base).setClassName(target.packageName, target.name))
    }

    /** Installed apps that open [uri] (e.g. stremio:///detail/… → Nuvio): package + name. */
    private fun linkHandlers(uri: String): List<Map<String, String>> = try {
        val pm = packageManager
        pm.queryIntentActivities(Intent(Intent.ACTION_VIEW, Uri.parse(uri)), 0)
            .map { it.activityInfo }
            .filter { it.packageName != packageName }
            .distinctBy { it.packageName }
            .map { mapOf("package" to it.packageName, "label" to it.applicationInfo.loadLabel(pm).toString()) }
    } catch (e: Exception) {
        emptyList()
    }

    private fun open(i: Intent): Boolean = try {
        startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_LISTEN) {
            val words = data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            listening?.success(if (resultCode == RESULT_OK) words ?: "" else "")
            listening = null
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }
}
