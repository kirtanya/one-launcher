package com.kirtanya.one_launcher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

/**
 * App lock. Only an accessibility service can see which app came to the front: a locked app that
 * appears without One Launcher having allowed it sends the user home.
 * It reads no screen content — only which package a window belongs to, and only while some app
 * is locked ([updateWatching]): with nothing locked it listens to nothing, as before App lock —
 * payment apps flag accessibility services that watch windows.
 */
class LockService : AccessibilityService() {
    companion object {
        @Volatile var instance: LockService? = null
        private val SKIP = setOf(
            "com.android.systemui",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
        )
    }

    private var lastKickPkg: String? = null
    private var lastKickAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        AppLockGuard.load(this)
        updateWatching()
    }

    /** Window events only while App lock has locked apps; otherwise none (the XML's quiet default). */
    fun updateWatching() {
        val info = serviceInfo ?: return
        val want = if (AppLockGuard.locked.isEmpty()) AccessibilityEvent.TYPE_ANNOUNCEMENT else AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        if (info.eventTypes == want) return
        info.eventTypes = want
        serviceInfo = info
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val locked = AppLockGuard.locked
        if (locked.isEmpty()) return
        val pkg = event.packageName?.toString() ?: return
        if (event.className == null) return
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
