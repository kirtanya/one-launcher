package com.kirtanya.one_launcher

import android.Manifest
import android.annotation.SuppressLint
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ContentUris
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.provider.CalendarContract
import java.util.Calendar
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.LauncherActivityInfo
import android.content.pm.LauncherApps
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserHandle
import android.os.UserManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Bridge between the Flutter UI and Android.
 * Flutter asks for: the app list, an app's icon, opening an app, app info, uninstall,
 * and pulling down the notification shade. Android tells Flutter when Home is pressed
 * or when apps are installed / removed.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val CALENDAR_REQUEST = 7
    }

    private lateinit var channel: MethodChannel
    private val widgets by lazy { WidgetHost(this) }
    private val backups by lazy { BackupFiles(this) }
    private val quick by lazy { QuickActions(this) { method, arg -> if (::channel.isInitialized) channel.invokeMethod(method, arg) } }
    private val media by lazy { MediaWatcher(this) { state -> if (::channel.isInitialized) channel.invokeMethod("mediaChanged", state) } }
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val launcherApps by lazy { getSystemService(LauncherApps::class.java) }
    private val userManager by lazy { getSystemService(UserManager::class.java) }

    private fun appsChanged() {
        if (::channel.isInitialized) main.post { channel.invokeMethod("appsChanged", null) }
    }

    // Personal-profile installs/removals.
    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = appsChanged()
    }

    // Any profile (incl. work): installs, removals, and work apps paused/unpaused.
    private val launcherCallback = object : LauncherApps.Callback() {
        override fun onPackageRemoved(packageName: String?, user: UserHandle?) = appsChanged()
        override fun onPackageAdded(packageName: String?, user: UserHandle?) = appsChanged()
        override fun onPackageChanged(packageName: String?, user: UserHandle?) = appsChanged()
        override fun onPackagesAvailable(packageNames: Array<out String>?, user: UserHandle?, replacing: Boolean) = appsChanged()
        override fun onPackagesUnavailable(packageNames: Array<out String>?, user: UserHandle?, replacing: Boolean) = appsChanged()
    }

    private val profileReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = appsChanged()
    }

    // Transparent so the phone wallpaper shows behind the Flutter UI.
    override fun getBackgroundMode(): BackgroundMode = BackgroundMode.transparent

    // SurfaceView (not the default TextureView that transparency picks): frames go straight to
    // the compositor instead of through an extra GPU copy — the biggest win on slower phones.
    override fun getRenderMode(): RenderMode = RenderMode.surface

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "one_launcher/apps")
        // Android app widgets shown in the top carousel.
        flutterEngine.platformViewsController.registry.registerViewFactory(WidgetHost.VIEW_TYPE, widgets.factory)
        channel.setMethodCallHandler { call, result ->
            if (widgets.handle(call, result)) return@setMethodCallHandler
            if (backups.handle(call, result)) return@setMethodCallHandler
            if (media.handle(call, result)) return@setMethodCallHandler
            if (quick.handle(call, result)) return@setMethodCallHandler
            when (call.method) {
                "getApps" -> worker.execute {
                    val apps = loadApps()
                    main.post { result.success(apps) }
                }
                "getIcon" -> {
                    val pkg = call.argument<String>("package")!!
                    worker.execute {
                        val bytes = loadIcon(pkg)
                        main.post { result.success(bytes) }
                    }
                }
                "launch" -> result.success(launch(call.argument<String>("package")!!, call.argument<List<Number>>("from")))
                "appInfo" -> result.success(appInfo(call.argument<String>("package")!!))
                "uninstall" -> {
                    val (pkg, user) = resolve(call.argument<String>("package")!!)
                    startActivity(Intent(Intent.ACTION_DELETE)
                        .setData(Uri.parse("package:$pkg"))
                        .putExtra(Intent.EXTRA_USER, user) // work-profile apps uninstall from their own profile
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "openNotifications" -> result.success(expandNotifications())
                // ---- Top carousel widgets ----
                "getScreenTime" -> worker.execute {
                    val data = screenTime()
                    main.post { result.success(data) }
                }
                "openUsageAccess" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "openScreenTime" -> result.success(openScreenTime())
                "getBattery" -> result.success(battery())
                "openBatterySettings" -> {
                    startActivity(Intent(Intent.ACTION_POWER_USAGE_SUMMARY).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "getNextEvent" -> worker.execute {
                    val data = nextEvent()
                    main.post { result.success(data) }
                }
                "requestCalendar" -> {
                    requestPermissions(arrayOf(Manifest.permission.READ_CALENDAR), CALENDAR_REQUEST)
                    result.success(true)
                }
                "openEvent" -> {
                    val id = (call.argument<Number>("id"))!!.toLong()
                    startActivity(Intent(Intent.ACTION_VIEW, ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, id))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                "openWallpaperPicker" -> {
                    startActivity(Intent.createChooser(Intent(Intent.ACTION_SET_WALLPAPER), "Wallpaper"))
                    result.success(true)
                }
                "openHomeSettings" -> {
                    startActivity(Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addDataScheme("package")
        }
        registerReceiver(packageReceiver, filter)
        launcherApps.registerCallback(launcherCallback, main)
        registerReceiver(profileReceiver, IntentFilter().apply {
            addAction(Intent.ACTION_MANAGED_PROFILE_AVAILABLE)
            addAction(Intent.ACTION_MANAGED_PROFILE_UNAVAILABLE)
            addAction(Intent.ACTION_MANAGED_PROFILE_ADDED)
            addAction(Intent.ACTION_MANAGED_PROFILE_REMOVED)
        })
    }

    override fun onStart() {
        super.onStart()
        widgets.start() // widgets update only while we listen
        media.start() // now playing, only while on screen
    }

    override fun onStop() {
        widgets.stop()
        media.stop()
        super.onStop()
    }

    @Deprecated("Needed for the widget bind/configure screens")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!widgets.onActivityResult(requestCode, resultCode) && !backups.onActivityResult(requestCode, resultCode, data)) {
            @Suppress("DEPRECATION")
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    override fun onDestroy() {
        quick.dispose()
        unregisterReceiver(packageReceiver)
        unregisterReceiver(profileReceiver)
        launcherApps.unregisterCallback(launcherCallback)
        super.onDestroy()
    }

    // Home button pressed while the launcher is already open.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.hasCategory(Intent.CATEGORY_HOME) && ::channel.isInitialized) {
            channel.invokeMethod("homePressed", null)
        }
    }

    /**
     * Apps from every profile on the phone (personal + work). Work apps get the id
     * "package@serial" so the same app in both profiles stays two separate entries.
     */
    private fun loadApps(): List<Map<String, Any>> {
        val me = Process.myUserHandle()
        val out = mutableListOf<Map<String, Any>>()
        for (user in launcherApps.profiles) {
            val work = user != me
            val serial = userManager.getSerialNumberForUser(user)
            val paused = work && userManager.isQuietModeEnabled(user)
            for (info in launcherApps.getActivityList(null, user)) {
                val pkg = info.componentName.packageName
                if (!work && pkg == packageName) continue
                val app = info.applicationInfo
                out += mapOf(
                    "package" to (if (work) "$pkg@$serial" else pkg),
                    "label" to info.label.toString(),
                    "system" to ((app.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                    // Android's own app category (game, social, audio…); -1 when the app sets none.
                    "category" to (if (Build.VERSION.SDK_INT >= 26) app.category else -1),
                    "installed" to info.firstInstallTime,
                    "work" to work,
                    "paused" to paused,
                )
            }
        }
        return out.distinctBy { it["package"] }
    }

    /** "pkg" → (pkg, me); "pkg@serial" → (pkg, that profile). */
    private fun resolve(id: String): Pair<String, UserHandle> {
        val at = id.lastIndexOf('@')
        if (at < 0) return id to Process.myUserHandle()
        val user = userManager.getUserForSerialNumber(id.substring(at + 1).toLong()) ?: Process.myUserHandle()
        return id.substring(0, at) to user
    }

    private fun activityFor(id: String): Pair<LauncherActivityInfo?, UserHandle> {
        val (pkg, user) = resolve(id)
        return launcherApps.getActivityList(pkg, user).firstOrNull() to user
    }

    // Badged = work apps get the briefcase, like the system launcher.
    private fun loadIcon(id: String): ByteArray? = try {
        val (info, _) = activityFor(id)
        val d = info?.getBadgedIcon(0) ?: packageManager.getApplicationIcon(resolve(id).first)
        val size = 144
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, size, size)
        d.draw(Canvas(bmp))
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    } catch (e: Exception) {
        null
    }

    /** [from] = the tapped icon's [left, top, width, height] in screen pixels (for the open animation). */
    private fun launch(id: String, from: List<Number>? = null): Boolean {
        val (info, user) = activityFor(id)
        info ?: return false
        // Work apps paused → ask Android to turn them back on (it shows its own prompt).
        if (user != Process.myUserHandle() && userManager.isQuietModeEnabled(user)) {
            if (Build.VERSION.SDK_INT >= 28) userManager.requestQuietModeEnabled(false, user)
            return false
        }
        return try {
            // The app's window grows out of the icon that was tapped (system animation, no delay).
            val bounds = from?.takeIf { it.size == 4 }?.map { it.toInt() }
            val rect = bounds?.let { android.graphics.Rect(it[0], it[1], it[0] + it[2], it[1] + it[3]) }
            val opts = bounds?.let {
                android.app.ActivityOptions.makeScaleUpAnimation(window.decorView, it[0], it[1], it[2], it[3]).toBundle()
            }
            launcherApps.startMainActivity(info.componentName, user, rect, opts)
            true
        } catch (e: SecurityException) {
            // Apps without a real launcher screen are listed via Android's "app details"
            // stand-in, which can't be started directly; open their info page instead.
            appInfo(id)
        }
    }

    private fun appInfo(id: String): Boolean {
        val (info, user) = activityFor(id)
        if (info != null) {
            launcherApps.startAppDetailsActivity(info.componentName, user, null, null)
        } else {
            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:" + resolve(id).first))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
        return true
    }

    // ---- Top carousel: screen time, battery, next event ----------------------

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CALENDAR_REQUEST && ::channel.isInitialized) channel.invokeMethod("permissionsChanged", null)
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(AppOpsManager::class.java)
        val mode = if (Build.VERSION.SDK_INT >= 29) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION") ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Today's foreground time per app (from midnight), worked out from resume/pause events. */
    private fun screenTime(): Map<String, Any> {
        if (!hasUsageAccess()) return mapOf("granted" to false)
        val usm = getSystemService(UsageStatsManager::class.java)
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0); set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val now = System.currentTimeMillis()
        // Launchers (incl. this one) and the system UI aren't "screen time".
        val homes = packageManager.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0)
            .map { it.activityInfo.packageName }.toSet() + setOf(packageName, "com.android.systemui")
        val totals = HashMap<String, Long>()
        val resumedAt = HashMap<String, Long>()
        val events = usm.queryEvents(start, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            val pkg = e.packageName ?: continue
            when (e.eventType) {
                UsageEvents.Event.ACTIVITY_RESUMED -> resumedAt.putIfAbsent(pkg, e.timeStamp)
                UsageEvents.Event.ACTIVITY_PAUSED, UsageEvents.Event.ACTIVITY_STOPPED -> resumedAt.remove(pkg)?.let {
                    totals[pkg] = (totals[pkg] ?: 0L) + (e.timeStamp - it)
                }
            }
        }
        resumedAt.forEach { (pkg, t) -> totals[pkg] = (totals[pkg] ?: 0L) + (now - t) }
        val counted = totals.filterKeys { it !in homes }.filterValues { it > 0 }
        val top = counted.entries.sortedByDescending { it.value }.take(3).map {
            val label = try { packageManager.getApplicationLabel(packageManager.getApplicationInfo(it.key, 0)).toString() } catch (x: Exception) { it.key }
            mapOf("package" to it.key, "label" to label, "ms" to it.value)
        }
        return mapOf("granted" to true, "total" to counted.values.sum(), "top" to top)
    }

    private fun openScreenTime(): Boolean = try {
        startActivity(Intent().setClassName("com.google.android.apps.wellbeing", "com.google.android.apps.wellbeing.settings.TopLevelSettingsActivity")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        false
    }

    private fun battery(): Map<String, Any> {
        val i = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = i?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = i?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val status = i?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        val bm = getSystemService(BatteryManager::class.java)
        val remaining = if (charging && Build.VERSION.SDK_INT >= 28) bm.computeChargeTimeRemaining() else -1L
        return mapOf(
            "level" to (if (level >= 0) level * 100 / scale else -1),
            "charging" to charging,
            "full" to (status == BatteryManager.BATTERY_STATUS_FULL),
            "chargeMsLeft" to remaining,
        )
    }

    /** The next timed event in the next 2 days (falls back to an all-day one). */
    private fun nextEvent(): Map<String, Any> {
        if (checkSelfPermission(Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) return mapOf("granted" to false)
        val now = System.currentTimeMillis()
        val uri = CalendarContract.Instances.CONTENT_URI.buildUpon().also {
            ContentUris.appendId(it, now - 86_400_000L)
            ContentUris.appendId(it, now + 2 * 86_400_000L)
        }.build()
        val cols = arrayOf(
            CalendarContract.Instances.EVENT_ID, CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END, CalendarContract.Instances.ALL_DAY,
        )
        var allDay: Map<String, Any>? = null
        contentResolver.query(uri, cols, "${CalendarContract.Instances.VISIBLE} = 1 AND ${CalendarContract.Instances.END} > ?", arrayOf(now.toString()),
            "${CalendarContract.Instances.BEGIN} ASC")?.use { c ->
            while (c.moveToNext()) {
                val event = mapOf(
                    "granted" to true,
                    "id" to c.getLong(0),
                    "title" to (c.getString(1) ?: "(No title)"),
                    "begin" to c.getLong(2),
                    "end" to c.getLong(3),
                    "allDay" to (c.getInt(4) == 1),
                )
                if (c.getInt(4) == 1) { if (allDay == null) allDay = event } else return event
            }
        }
        return allDay ?: mapOf("granted" to true)
    }

    @SuppressLint("WrongConstant")
    private fun expandNotifications(): Boolean = try {
        val service = getSystemService("statusbar")
        Class.forName("android.app.StatusBarManager").getMethod("expandNotificationsPanel").invoke(service)
        true
    } catch (e: Exception) {
        false
    }
}
