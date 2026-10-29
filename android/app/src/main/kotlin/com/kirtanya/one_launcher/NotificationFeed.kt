package com.kirtanya.one_launcher

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Icon
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * The launcher's own notification centre (lib/notifications/): every notification on the phone,
 * read through [MediaListener] (Notification access), handed to Flutter to show in One's own
 * design — and acted on from there: open, its buttons (reply too), dismiss, snooze. Read on the
 * phone only, never stored or sent anywhere.
 *
 * Channel "one_launcher/notifications": list, open, action, dismiss, dismissAll, snooze,
 * hasAccess; it calls "changed" when notifications come or go.
 */
object NotificationFeed {
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private var pending = false

    fun attach(engine: FlutterEngine, context: Context) {
        val ch = MethodChannel(engine.dartExecutor.binaryMessenger, "one_launcher/notifications")
        channel = ch
        MediaListener.onAny = { changed() }
        ch.setMethodCallHandler { call, result ->
            val l = MediaListener.instance
            when (call.method) {
                "hasAccess" -> result.success(l != null)
                "list" -> result.success(if (l == null) emptyList<Any>() else list(l, context))
                "open" -> result.success(find(l, call.argument("key"))?.let { open(it, context) } ?: false)
                "action" -> result.success(find(l, call.argument("key"))?.let { action(it, context, call.argument<Int>("index") ?: 0, call.argument("reply")) } ?: false)
                "dismiss" -> result.success(run { l?.cancelNotification(call.argument<String>("key")); l != null })
                "dismissAll" -> result.success(run { l?.cancelAllNotifications(); l != null })
                "snooze" -> result.success(run {
                    l?.snoozeNotification(call.argument<String>("key"), (call.argument<Number>("ms") ?: 3_600_000).toLong())
                    l != null
                })
                else -> result.notImplemented()
            }
        }
    }

    /** Notifications came or went: tell Flutter once per frame-ish burst. */
    private fun changed() {
        if (pending) return
        pending = true
        main.postDelayed({
            pending = false
            channel?.invokeMethod("changed", null)
        }, 120)
    }

    private fun find(l: MediaListener?, key: String?): StatusBarNotification? =
        if (l == null || key == null) null else try { l.activeNotifications.firstOrNull { it.key == key } } catch (e: Exception) { null }

    private fun list(l: MediaListener, context: Context): List<Map<String, Any?>> {
        val ranking = try { l.currentRanking } catch (e: Exception) { null }
        val users = context.getSystemService(UserManager::class.java)
        val me = Process.myUserHandle()
        val pm = context.packageManager
        val labels = mutableMapOf<String, String>()
        return try {
            l.activeNotifications.filter { it.packageName != context.packageName }.map { sbn ->
                val n = sbn.notification
                val x = n.extras
                val rank = NotificationListenerService.Ranking()
                val ranked = ranking?.getRanking(sbn.key, rank) == true
                val label = labels.getOrPut(sbn.packageName) {
                    try { pm.getApplicationLabel(pm.getApplicationInfo(sbn.packageName, 0)).toString() } catch (e: Exception) { sbn.packageName }
                }
                val template = x.getString(Notification.EXTRA_TEMPLATE) ?: ""
                mapOf(
                    "key" to sbn.key,
                    "package" to sbn.packageName,
                    "app" to label,
                    "work" to (sbn.user != me),
                    "profile" to if (sbn.user == me) null else users.getSerialNumberForUser(sbn.user).toString(),
                    "title" to x.getCharSequence(Notification.EXTRA_TITLE_BIG)?.toString().orEmpty().ifEmpty { x.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty() },
                    "text" to x.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty(),
                    "bigText" to x.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
                    "subText" to x.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString(),
                    "lines" to x.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.map { it.toString() },
                    "messages" to messages(x),
                    "conversation" to x.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString(),
                    "time" to (if (n.`when` > 0) n.`when` else sbn.postTime),
                    "category" to n.category,
                    "template" to template.substringAfterLast('$'),
                    "ongoing" to sbn.isOngoing,
                    "clearable" to sbn.isClearable,
                    "summary" to ((n.flags and Notification.FLAG_GROUP_SUMMARY) != 0),
                    "group" to sbn.groupKey,
                    "importance" to if (ranked) rank.importance else 3,
                    "silent" to (ranked && rank.isAmbient),
                    "conversationRank" to (ranked && android.os.Build.VERSION.SDK_INT >= 30 && rank.isConversation),
                    "color" to n.color,
                    "progress" to x.getInt(Notification.EXTRA_PROGRESS, -1).takeIf { x.getInt(Notification.EXTRA_PROGRESS_MAX, 0) > 0 }
                        ?.let { it * 100 / x.getInt(Notification.EXTRA_PROGRESS_MAX, 1) },
                    "indeterminate" to x.getBoolean(Notification.EXTRA_PROGRESS_INDETERMINATE, false),
                    "picture" to bitmap(context, x.get(Notification.EXTRA_PICTURE), 720),
                    "largeIcon" to bitmap(context, n.getLargeIcon() ?: x.get(Notification.EXTRA_LARGE_ICON), 144),
                    "actions" to (n.actions ?: emptyArray()).mapIndexed { i, a ->
                        mapOf("index" to i, "title" to a.title?.toString().orEmpty(), "reply" to (a.remoteInputs?.isNotEmpty() == true))
                    },
                    "canOpen" to (n.contentIntent != null),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** MessagingStyle: the messages, oldest first (sender, text, time). */
    private fun messages(x: Bundle): List<Map<String, Any?>>? {
        val raw = x.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return null
        return raw.mapNotNull { (it as? Bundle) }.map { b ->
            val person = b.getParcelable<android.app.Person>("sender_person")
            mapOf(
                "sender" to (person?.name?.toString() ?: b.getCharSequence("sender")?.toString()),
                "text" to b.getCharSequence("text")?.toString().orEmpty(),
                "time" to b.getLong("time"),
            )
        }
    }

    /** A bitmap / icon as PNG bytes, at most [max] px wide (null if none). */
    private fun bitmap(context: Context, any: Any?, max: Int): ByteArray? = try {
        val bmp: Bitmap? = when (any) {
            is Bitmap -> any
            is Icon -> any.loadDrawable(context)?.let { d ->
                val w = d.intrinsicWidth.coerceIn(1, max)
                val h = (d.intrinsicHeight * w / d.intrinsicWidth.coerceAtLeast(1)).coerceAtLeast(1)
                Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { b -> d.setBounds(0, 0, w, h); d.draw(Canvas(b)) }
            }
            else -> null
        }
        bmp?.let {
            val scaled = if (it.width > max) Bitmap.createScaledBitmap(it, max, it.height * max / it.width, true) else it
            ByteArrayOutputStream().also { o -> scaled.compress(Bitmap.CompressFormat.PNG, 90, o) }.toByteArray()
        }
    } catch (e: Exception) {
        null
    }

    private fun open(sbn: StatusBarNotification, context: Context): Boolean = try {
        sbn.notification.contentIntent?.send(context, 0, null)
        if ((sbn.notification.flags and Notification.FLAG_AUTO_CANCEL) != 0) MediaListener.instance?.cancelNotification(sbn.key)
        true
    } catch (e: PendingIntent.CanceledException) {
        false
    }

    /** Presses button [index]; with [reply], fills its text box (a reply action) first. */
    private fun action(sbn: StatusBarNotification, context: Context, index: Int, reply: String?): Boolean = try {
        val a = sbn.notification.actions?.getOrNull(index) ?: return false
        val inputs = a.remoteInputs
        if (reply != null && inputs != null && inputs.isNotEmpty()) {
            val intent = Intent()
            val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, reply) } }
            RemoteInput.addResultsToIntent(inputs, intent, results)
            a.actionIntent.send(context, 0, intent)
        } else {
            a.actionIntent.send()
        }
        true
    } catch (e: Exception) {
        false
    }
}
