package com.kirtanya.one_launcher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

/**
 * Double-tap to lock (Tiles view) and App lock. Android only lets an accessibility service turn
 * the screen off without forcing the PIN later, and only a service can see which app came to the
 * front: a locked app that appears without One Launcher having allowed it sends the user home.
 * It reads no screen content — only which package a window belongs to.
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
            try {
                val label = packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0))
                Toast.makeText(this, "$label is locked — open it from One Launcher", Toast.LENGTH_SHORT).show()
            } catch (_: Exception) {}
            return
        }
        // A different real app: the user is away from whatever was allowed.
        if (packageManager.getLaunchIntentForPackage(pkg) != null) AppLockGuard.endAllowancesExcept(pkg)
    }

    private fun imePackage(): String? =
        Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
            ?.substringBefore('/')

    override fun onInterrupt() {}

    fun lock(): Boolean = performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
}
