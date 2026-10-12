package com.kirtanya.one_launcher

import android.service.notification.NotificationListenerService

/**
 * Exists so Android lets One Launcher see media sessions (Notification access).
 * It doesn't read, store or act on notifications. On the TV app it also keeps the watch
 * history ([MediaHistory]) while you watch, even when the launcher isn't on screen.
 */
class MediaListener : NotificationListenerService() {
    private var history: MediaHistory? = null

    override fun onListenerConnected() {
        super.onListenerConnected()
        if (packageName.endsWith(".tv")) history = MediaHistory(this).also { it.start() }
    }

    override fun onListenerDisconnected() {
        history?.stop()
        history = null
        super.onListenerDisconnected()
    }
}
