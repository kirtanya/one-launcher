package com.kirtanya.one_launcher

import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.widget.Toast

/**
 * App lock: a locked app that comes to the front without One Launcher having allowed it is sent
 * home. NOT an accessibility service: UPI PIN pads (Paytm's NPCI keypad) refuse to open while any
 * sideloaded accessibility service is on, whatever it listens to. Instead a small foreground
 * service (it must stay alive while another app is in front) asks Usage access which app was last
 * resumed (every [POLL_MS]), only while some app is locked, Usage access is granted and the screen
 * is on. Going home is a plain HOME intent: allowed from the background because we are the home app.
 */
class LockService : Service() {
    companion object {
        @Volatile var instance: LockService? = null
        private const val POLL_MS = 500L
        private const val LOOKBACK_MS = 10_000L
        private const val CHANNEL = "app_lock"
        private const val ID = 7301
        private val SKIP = setOf(
            "com.android.systemui",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
        )

        fun hasUsageAccess(c: Context): Boolean {
            val ops = c.getSystemService(AppOpsManager::class.java)
            return ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), c.packageName) == AppOpsManager.MODE_ALLOWED
        }

        /** False in the Play build, whose manifest leaves this service out (store/PLAY_REVIEW.md). */
        private fun declared(c: Context) =
            try { c.packageManager.getServiceInfo(ComponentName(c, LockService::class.java), 0); true } catch (_: Exception) { false }

        /** Run while apps are locked and Usage access is granted; stop otherwise. Call from the foreground. */
        fun sync(c: Context) {
            AppLockGuard.load(c)
            val want = AppLockGuard.locked.isNotEmpty() && hasUsageAccess(c) && declared(c)
            val i = Intent(c, LockService::class.java)
            if (want && instance == null) {
                try { c.startForegroundService(i) } catch (_: Exception) {} // not allowed from the background
            } else if (!want && instance != null) {
                c.stopService(i)
            }
        }
    }

    private var lastKickPkg: String? = null
    private var lastKickAt = 0L
    private val main = Handler(Looper.getMainLooper())
    // Screen off ends allowances (AppLockGuard.relockOnScreenOff): the app still in front is sent
    // home when it resumes after unlock, as its resume is a new event.
    private val screenOff = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) = AppLockGuard.screenOff()
    }
    private var handled = 0L // timestamp of the newest resume already looked at
    private val tick = object : Runnable {
        override fun run() {
            poll()
            if (instance != null) main.postDelayed(this, POLL_MS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (instance == null) {
            startForeground()
            instance = this
            AppLockGuard.load(this)
            handled = System.currentTimeMillis()
            registerReceiver(screenOff, IntentFilter(Intent.ACTION_SCREEN_OFF))
            main.post(tick)
        }
        return START_STICKY
    }

    private fun startForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "App lock", NotificationManager.IMPORTANCE_MIN).apply {
            description = "Shown while App lock keeps locked apps closed. You can turn this notification off."
            setShowBadge(false)
        })
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val n = Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setContentTitle("App lock is on")
            .setContentIntent(open)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_SECRET)
            .build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(ID, n)
    }

    override fun onDestroy() {
        if (instance != null) try { unregisterReceiver(screenOff) } catch (_: Exception) {}
        instance = null
        main.removeCallbacks(tick)
        super.onDestroy()
    }

    /**
     * The newest app resumed in the last [LOOKBACK_MS] that wasn't handled yet; skipped while the
     * screen is off. Looks back (not just since the previous tick): usage events can be recorded
     * a little after they happen, and a plain since→now window would miss those.
     */
    private fun poll() {
        val now = System.currentTimeMillis()
        if (!getSystemService(PowerManager::class.java).isInteractive) {
            handled = now
            return
        }
        if (AppLockGuard.locked.isEmpty() || !hasUsageAccess(this)) { stopSelf(); return }
        val events = getSystemService(UsageStatsManager::class.java).queryEvents(now - LOOKBACK_MS, now + 1000)
        val e = UsageEvents.Event()
        var front: String? = null
        var at = handled
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.ACTIVITY_RESUMED && e.timeStamp > at) {
                front = e.packageName
                at = e.timeStamp
            }
        }
        handled = at
        front?.let(::onFront)
    }

    /** [pkg] came to the front (a resumed activity). */
    private fun onFront(pkg: String) {
        val locked = AppLockGuard.locked
        if (pkg in SKIP || pkg == imePackage()) return

        if (pkg == packageName) { // back on our launcher
            AppLockGuard.endAllowancesExcept(null)
            return
        }
        if (pkg in locked) {
            if (AppLockGuard.isAllowed(pkg)) return
            val now = SystemClock.elapsedRealtime()
            if (pkg == lastKickPkg && now - lastKickAt < 1500) return
            lastKickPkg = pkg
            lastKickAt = now
            startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).setPackage(packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            Toast.makeText(this, "App not supported", Toast.LENGTH_SHORT).show()
            return
        }
        // A different real app: the user is away from whatever was allowed.
        if (packageManager.getLaunchIntentForPackage(pkg) != null) AppLockGuard.endAllowancesExcept(pkg)
    }

    private fun imePackage(): String? =
        Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            ?.substringBefore('/')
}
