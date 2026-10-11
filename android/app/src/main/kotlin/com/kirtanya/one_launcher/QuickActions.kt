package com.kirtanya.one_launcher

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.LauncherApps
import android.content.pm.ShortcutInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.UserManager
import android.provider.AlarmClock
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * Quick-action chips: built-in actions (timer, flashlight, camera…) and apps' own shortcuts
 * (the actions apps show when you long-press their icon, e.g. Paytm "Scan any QR").
 * App shortcuts are only shared with the default home app.
 */
class QuickActions(private val activity: Activity, private val push: (String, Any?) -> Unit) {
    private val launcherApps = activity.getSystemService(LauncherApps::class.java)
    private val users = activity.getSystemService(UserManager::class.java)
    private val cameras = activity.getSystemService(CameraManager::class.java)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var torchCamera: String? = null
    private var torchOn = false
    private val torchCallback = object : CameraManager.TorchCallback() {
        override fun onTorchModeChanged(cameraId: String, enabled: Boolean) {
            if (cameraId == torchCamera) {
                torchOn = enabled
                push("torchChanged", enabled)
            }
        }
    }

    init {
        torchCamera = try {
            cameras.cameraIdList.firstOrNull { cameras.getCameraCharacteristics(it).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true }
        } catch (e: Exception) { null }
        if (torchCamera != null) cameras.registerTorchCallback(torchCallback, main)
    }

    fun dispose() = try { cameras.unregisterTorchCallback(torchCallback) } catch (e: Exception) {}

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "quickAction" -> result.success(run(call.argument<String>("id")!!))
            "torchState" -> result.success(mapOf("available" to (torchCamera != null), "on" to torchOn))
            "listShortcuts" -> worker.execute {
                val data = shortcuts()
                main.post { result.success(data) }
            }
            "shortcutIcon" -> {
                val id = call.argument<String>("id")!!
                worker.execute {
                    val bytes = shortcutIcon(id)
                    main.post { result.success(bytes) }
                }
            }
            else -> return false
        }
        return true
    }

    // ---- Built-in actions --------------------------------------------------------------

    private fun run(id: String): Boolean = try {
        when {
            id.startsWith("s:") -> startShortcut(id)
            id == "b:torch" -> {
                val cam = torchCamera ?: return false
                cameras.setTorchMode(cam, !torchOn)
                true
            }
            else -> {
                val intent = when (id) {
                    "b:timer" -> Intent(AlarmClock.ACTION_SET_TIMER)
                    "b:alarm" -> Intent(AlarmClock.ACTION_SHOW_ALARMS)
                    "b:camera" -> Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
                    "b:calculator" -> Intent.makeMainSelectorActivity(Intent.ACTION_MAIN, Intent.CATEGORY_APP_CALCULATOR)
                    "b:internet" -> if (Build.VERSION.SDK_INT >= 29) Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY) else Intent(Settings.ACTION_WIRELESS_SETTINGS)
                    "b:bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                    "b:note" -> Intent("com.google.android.gms.actions.CREATE_NOTE").setType("text/plain")
                    else -> null
                } ?: return false
                activity.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            }
        }
    } catch (e: Exception) {
        false // no app on this phone handles it
    }

    // ---- App shortcuts ("s:<package>|<shortcutId>|<profile serial>") ---------------------

    private fun allowed() = try { launcherApps.hasShortcutHostPermission() } catch (e: Exception) { false }

    private fun shortcuts(): Map<String, Any> {
        if (!allowed()) return mapOf("allowed" to false)
        val pm = activity.packageManager
        val me = Process.myUserHandle()
        val out = mutableListOf<Map<String, Any>>()
        for (user in launcherApps.profiles) {
            val serial = users.getSerialNumberForUser(user)
            val packages = launcherApps.getActivityList(null, user).map { it.componentName.packageName }.distinct()
            for (pkg in packages) {
                if (pkg == activity.packageName) continue
                val list = query(pkg, user, null) ?: continue
                val app = try { pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString() } catch (e: Exception) { pkg }
                for (s in list) {
                    if (!s.isEnabled) continue
                    out += mapOf(
                        "id" to "s:$pkg|${s.id}|$serial",
                        "package" to (if (user != me) "$pkg@$serial" else pkg),
                        "app" to app,
                        "label" to (s.shortLabel?.toString() ?: s.longLabel?.toString() ?: s.id),
                        "work" to (user != me),
                    )
                }
            }
        }
        return mapOf("allowed" to true, "shortcuts" to out.sortedWith(compareBy({ (it["app"] as String).lowercase() }, { it["label"] as String })))
    }

    private fun query(pkg: String, user: android.os.UserHandle, ids: List<String>?): List<ShortcutInfo>? = try {
        val q = LauncherApps.ShortcutQuery()
            .setPackage(pkg)
            .setQueryFlags(LauncherApps.ShortcutQuery.FLAG_MATCH_MANIFEST or LauncherApps.ShortcutQuery.FLAG_MATCH_DYNAMIC or LauncherApps.ShortcutQuery.FLAG_MATCH_PINNED)
        if (ids != null) q.setShortcutIds(ids)
        launcherApps.getShortcuts(q, user)
    } catch (e: Exception) {
        null
    }

    private fun parse(id: String): Triple<String, String, android.os.UserHandle>? {
        val parts = id.removePrefix("s:").split('|')
        if (parts.size < 3) return null
        val user = users.getUserForSerialNumber(parts[2].toLongOrNull() ?: return null) ?: Process.myUserHandle()
        return Triple(parts[0], parts[1], user)
    }

    private fun startShortcut(id: String): Boolean {
        if (!allowed()) return false
        val (pkg, sid, user) = parse(id) ?: return false
        launcherApps.startShortcut(pkg, sid, null, null, user)
        return true
    }

    private fun shortcutIcon(id: String): ByteArray? = try {
        val (pkg, sid, user) = parse(id) ?: throw IllegalArgumentException()
        val info = query(pkg, user, listOf(sid))?.firstOrNull() ?: throw IllegalStateException()
        val d = launcherApps.getShortcutIconDrawable(info, activity.resources.displayMetrics.densityDpi)
            ?: activity.packageManager.getApplicationIcon(pkg)
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, size, size)
        d.draw(Canvas(bmp))
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    } catch (e: Exception) {
        null
    }
}
