package com.kirtanya.one_launcher

import android.service.notification.NotificationListenerService

/**
 * Exists only so Android lets One Launcher see the active music session (Notification access).
 * It doesn't read, store or act on notifications.
 */
class MediaListener : NotificationListenerService()
