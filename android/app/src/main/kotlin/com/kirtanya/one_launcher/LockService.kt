package com.kirtanya.one_launcher

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * Double-tap to lock (Tiles view): Android only lets an accessibility service turn the screen
 * off without forcing the PIN later. It reads nothing on screen and handles no events — its one
 * job is the lock action, and only when the user switches it on in Accessibility settings.
 */
class LockService : AccessibilityService() {
    companion object {
        @Volatile var instance: LockService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    fun lock(): Boolean = performGlobalAction(GLOBAL_ACTION_LOCK_SCREEN)
}
