package com.kirtanya.one_launcher

import android.app.Notification
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Notification access: lets One Launcher see media sessions, count each app's clearable
 * notifications for the badges on Start tiles, and feed the launcher's own notification centre
 * ([NotificationFeed]) — all on the phone, nothing is stored or sent. On the TV app it also keeps
 * the watch history ([MediaHistory]) while you watch, even when the launcher isn't on screen.
 */
class MediaListener : NotificationListenerService() {
    companion object {
        @Volatile var instance: MediaListener? = null

        /** Called with fresh counts (app id → count) whenever notifications come or go. */
        @Volatile var onCounts: ((Map<String, Int>) -> Unit)? = null

        /** Called (on this service's thread) whenever any notification comes or goes. */
        @Volatile var onAny: (() -> Unit)? = null
    }

    private var history: MediaHistory? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
        if (packageName.endsWith(".tv")) history = MediaHistory(this).also { it.start() }
        // The phone remote's Now playing card: this service runs whenever the TV is on (the home
        // screen may not have been opened since an update), so the TV answers from here too.
        if (packageName.endsWith(".tv")) NowPlayingServer.start(this)
        publish()
    }

    override fun onListenerDisconnected() {
        instance = null
        history?.stop()
        history = null
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        publish()
        onAny?.invoke()
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        publish()
        onAny?.invoke()
    }

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
