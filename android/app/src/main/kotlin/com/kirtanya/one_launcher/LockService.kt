package com.kirtanya.one_launcher

import android.accessibilityservice.AccessibilityService
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

/**
 * App lock: a locked app that comes to the front without One Launcher having allowed it is sent
 * home (GLOBAL_ACTION_HOME — the one thing the service is for). It listens to NO accessibility
 * events: UPI PIN pads (Paytm's NPCI keypad) refuse to open while a sideloaded service watches
 * window changes. Instead, while some app is locked and the screen is on, it asks Usage access
 * which app was last resumed every [POLL_MS] ([updateWatching]). Only without Usage access does
 * it fall back to window events (App lock then works, payment apps may complain).
 */
class LockService : AccessibilityService() {
    companion object {
        @Volatile var instance: LockService? = null
        private const val POLL_MS = 500L
        private val SKIP = setOf(
            "com.android.systemui",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
        )
    }

    private var lastKickPkg: String? = null
    private var lastKickAt = 0L
    private val main = Handler(Looper.getMainLooper())
    private var polling = false
    private var since = 0L
    private val tick = object : Runnable {
        override fun run() {
            poll()
            if (polling) main.postDelayed(this, POLL_MS)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        AppLockGuard.load(this)
        updateWatching()
    }

    /** Locked apps: poll Usage access (window events only if it isn't granted). Nothing locked: nothing. */
    fun updateWatching() {
        val info = serviceInfo ?: return
        val locked = AppLockGuard.locked.isNotEmpty()
        val usage = hasUsageAccess()
        val want = if (locked && !usage) AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED else AccessibilityEvent.TYPE_ANNOUNCEMENT
        if (info.eventTypes != want) {
            info.eventTypes = want
            serviceInfo = info
        }
        if (locked && usage) startPolling() else stopPolling()
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(APP_OPS_SERVICE) as AppOpsManager
        return ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName) == AppOpsManager.MODE_ALLOWED
    }

    private fun startPolling() {
        if (polling) return
        polling = true
        since = System.currentTimeMillis()
        main.post(tick)
    }

    private fun stopPolling() {
        polling = false
        main.removeCallbacks(tick)
    }

    /** The app resumed last since the previous tick, if any; skipped while the screen is off. */
    private fun poll() {
        val now = System.currentTimeMillis()
        if (!(getSystemService(POWER_SERVICE) as PowerManager).isInteractive) {
            since = now
            return
        }
        if (!hasUsageAccess()) { updateWatching(); return } // access taken away: fall back
        val events = (getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager).queryEvents(since, now)
        since = now
        val e = UsageEvents.Event()
        var front: String? = null
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            if (e.eventType == UsageEvents.Event.ACTIVITY_RESUMED) front = e.packageName
        }
        front?.let(::onFront)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        stopPolling()
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        if (event.className == null) return
        onFront(event.packageName?.toString() ?: return)
    }

    /** [pkg] came to the front (a window event or a resumed activity). */
    private fun onFront(pkg: String) {
        val locked = AppLockGuard.locked
        if (locked.isEmpty()) return
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
            performGlobalAction(GLOBAL_ACTION_HOME)
            Toast.makeText(this, "App not supported", Toast.LENGTH_SHORT).show()
            return
        }
        // A different real app: the user is away from whatever was allowed.
        if (packageManager.getLaunchIntentForPackage(pkg) != null) AppLockGuard.endAllowancesExcept(pkg)
    }

    private fun imePackage(): String? =
        Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            ?.substringBefore('/')

    override fun onInterrupt() {}
}
