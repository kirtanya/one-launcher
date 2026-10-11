package com.kirtanya.one_launcher

import android.annotation.SuppressLint
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
    private lateinit var channel: MethodChannel
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "one_launcher/apps")
        channel.setMethodCallHandler { call, result ->
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
                "launch" -> result.success(launch(call.argument<String>("package")!!))
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

    override fun onDestroy() {
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

    private fun launch(id: String): Boolean {
        val (info, user) = activityFor(id)
        info ?: return false
        // Work apps paused → ask Android to turn them back on (it shows its own prompt).
        if (user != Process.myUserHandle() && userManager.isQuietModeEnabled(user)) {
            if (Build.VERSION.SDK_INT >= 28) userManager.requestQuietModeEnabled(false, user)
            return false
        }
        return try {
            launcherApps.startMainActivity(info.componentName, user, null, null)
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

    @SuppressLint("WrongConstant")
    private fun expandNotifications(): Boolean = try {
        val service = getSystemService("statusbar")
        Class.forName("android.app.StatusBarManager").getMethod("expandNotificationsPanel").invoke(service)
        true
    } catch (e: Exception) {
        false
    }
}
