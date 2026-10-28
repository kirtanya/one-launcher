package com.kirtanya.one_launcher

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.service.quicksettings.TileService
import android.app.Notification
import android.graphics.drawable.Icon

/**
 * The TV remote outside the launcher (phone): a notification with play / pause, volume down /
 * up and mute while the TV is connected (Settings → TV remote → In notifications), and a Quick
 * Settings tile that opens the remote. Buttons go to the TV through [TvRemote.hardwareKey].
 */
object RemoteNotification {
    const val EXTRA_OPEN_REMOTE = "com.kirtanya.one_launcher.OPEN_REMOTE"
    const val EXTRA_KEY = "key"
    private const val CHANNEL = "tv_remote"
    private const val ID = 4701
    const val PERMISSION_REQUEST = 7302

    /** Shows (or updates) the notification for [tvName], or removes it. False = permission asked first. */
    fun update(context: Context, on: Boolean, tvName: String): Boolean {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (!on) {
            nm.cancel(ID)
            return true
        }
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            (context as? Activity)?.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION_REQUEST)
            return false
        }
        nm.createNotificationChannel(NotificationChannel(CHANNEL, "TV remote", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Play / pause and volume for your TV while it's connected"
            setShowBadge(false)
        })
        fun action(icon: Int, title: String, code: Int) = Notification.Action.Builder(
            Icon.createWithResource(context, icon),
            title,
            PendingIntent.getBroadcast(
                context,
                code,
                Intent(context, RemoteActionReceiver::class.java).putExtra(EXTRA_KEY, code),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            ),
        ).build()
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).putExtra(EXTRA_OPEN_REMOTE, true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = Notification.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(tvName)
            .setContentText("TV remote · tap to open")
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(action(android.R.drawable.ic_media_play, "Play / pause", 85))
            .addAction(action(android.R.drawable.ic_media_previous, "Vol −", 25))
            .addAction(action(android.R.drawable.ic_media_next, "Vol +", 24))
            .addAction(action(android.R.drawable.ic_lock_silent_mode, "Mute", 164))
            .setStyle(Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2))
            .build()
        nm.notify(ID, n)
        return true
    }
}

/** A notification button: its key to the TV (connecting first if the launcher was in the background). */
class RemoteActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val code = intent.getIntExtra(RemoteNotification.EXTRA_KEY, -1)
        if (code < 0) return
        (TvRemote.current ?: TvRemote(context.applicationContext) { null }).hardwareKey(code)
    }
}

/** Quick Settings → "TV remote": opens the launcher straight into the remote. */
class RemoteTileService : TileService() {
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java)
            .putExtra(RemoteNotification.EXTRA_OPEN_REMOTE, true)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 1, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }
}
