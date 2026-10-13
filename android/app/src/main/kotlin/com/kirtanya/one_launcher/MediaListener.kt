package com.kirtanya.one_launcher

import android.app.Notification
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Exists so Android lets One Launcher see media sessions (Notification access). It never reads
 * notification content: it only counts each app's clearable notifications for the badges on
 * Start tiles (on-device, nothing is stored). On the TV app it also keeps the watch history
 * ([MediaHistory]) while you watch, even when the launcher isn't on screen.
 */
class MediaListener : NotificationListenerService() {
    companion object {
        @Volatile var instance: MediaListener? = null

        /** Called with fresh counts (app id → count) whenever notifications come or go. */
        @Volatile var onCounts: ((Map<String, Int>) -> Unit)? = null
    }

    private var history: MediaHistory? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        if (packageName.endsWith(".tv")) history = MediaHistory(this).also { it.start() }
        publish()
    }

    override fun onListenerDisconnected() {
        instance = null
        history?.stop()
        history = null
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) = publish()
    override fun onNotificationRemoved(sbn: StatusBarNotification?) = publish()

    /** Clearable notifications per app ("pkg", or "pkg@serial" for the work profile). */
    fun counts(): Map<String, Int> = try {
        val users = getSystemService(UserManager::class.java)
        val me = Process.myUserHandle()
        activeNotifications
            .filter { it.isClearable && !it.isOngoing && (it.notification.flags and Notification.FLAG_GROUP_SUMMARY) == 0 }
            .groupingBy { if (it.user == me) it.packageName else "${it.packageName}@${users.getSerialNumberForUser(it.user)}" }
            .eachCount()
    } catch (e: Exception) {
        emptyMap()
    }

    private fun publish() {
        val cb = onCounts ?: return
        val c = counts()
        main.post { cb(c) }
    }
}
