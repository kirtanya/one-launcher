package com.kirtanya.one_launcher

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.os.Build
import android.provider.DocumentsContract
import java.io.File
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Save / open settings backups with Android's own file picker (Storage Access Framework):
 * the user chooses where the file goes (Downloads, Drive…), so no storage permission is needed.
 */
class BackupFiles(private val activity: Activity) {
    companion object {
        const val REQ_SAVE = 51
        const val REQ_OPEN = 52
        const val REQ_PHOTO = 53
        const val DOWNLOADS = "content://com.android.externalstorage.documents/document/primary%3ADownload"
    }

    private var pending: MethodChannel.Result? = null
    private var text: String? = null

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "saveBackup" -> {
                pending?.success(null)
                pending = result
                text = call.argument<String>("text")
                activity.startActivityForResult(
                    Intent(Intent.ACTION_CREATE_DOCUMENT)
                        .addCategory(Intent.CATEGORY_OPENABLE)
                        .setType("application/json")
                        .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name")),
                    REQ_SAVE,
                )
            }
            "openBackup" -> {
                pending?.success(null)
                pending = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("*/*") // some file apps label .json as text or octet-stream
                    .putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                // Open straight in Downloads, where backups are saved by default.
                if (call.argument<Boolean>("downloads") == true && Build.VERSION.SDK_INT >= 26) {
                    intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, Uri.parse(DOWNLOADS))
                }
                activity.startActivityForResult(intent, REQ_OPEN)
            }
            // Launcher background photo: Android's photo picker (no permission needed).
            "pickPhoto" -> {
                pending?.success(null)
                pending = result
                val intent = if (Build.VERSION.SDK_INT >= 33) {
                    Intent(MediaStore.ACTION_PICK_IMAGES)
                } else {
                    Intent(Intent.ACTION_GET_CONTENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*")
                }
                activity.startActivityForResult(intent, REQ_PHOTO)
            }
            "installState" -> result.success(installState())
            else -> return false
        }
        return true
    }

    /**
     * Is this the first launch of this install? A marker in the no-backup folder (never included
     * in Android's backups, wiped on uninstall) tells a fresh install — even one whose settings
     * Android restored from the cloud — apart from a normal launch.
     */
    private fun installState(): Map<String, Any> {
        val marker = File(activity.noBackupFilesDir, "installed")
        val first = !marker.exists()
        if (first) marker.writeText(System.currentTimeMillis().toString())
        return mapOf("firstRun" to first)
    }

    /**
     * Copies the picked photo into app storage, scaled down to at most 2560 px on its long side
     * (a phone screen needs no more; keeps memory and drawing cheap). A new file name each time
     * so Flutter doesn't show a cached old image. Returns the file path.
     */
    private fun copyPhoto(uri: Uri, result: MethodChannel.Result) {
        val main = Handler(Looper.getMainLooper())
        Thread {
            try {
                val bmp: Bitmap = if (Build.VERSION.SDK_INT >= 28) {
                    ImageDecoder.decodeBitmap(ImageDecoder.createSource(activity.contentResolver, uri)) { d, info, _ ->
                        val long = maxOf(info.size.width, info.size.height)
                        if (long > 2560) d.setTargetSampleSize(Math.ceil(long / 2560.0).toInt())
                        d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    }
                } else {
                    @Suppress("DEPRECATION")
                    MediaStore.Images.Media.getBitmap(activity.contentResolver, uri)
                }
                val dir = File(activity.filesDir, "wallpaper").apply { mkdirs() }
                dir.listFiles()?.forEach { it.delete() }
                val out = File(dir, "photo-${System.currentTimeMillis()}.jpg")
                out.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 92, it) }
                main.post { result.success(out.absolutePath) }
            } catch (e: Exception) {
                main.post { result.error("photo", e.message, null) }
            }
        }.start()
    }

    /** Save → true/false; open → file text or null. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQ_PHOTO) {
            val result = pending ?: return true
            pending = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) result.success(null) else copyPhoto(uri, result)
            return true
        }
        if (requestCode != REQ_SAVE && requestCode != REQ_OPEN) return false
        val result = pending ?: return true
        pending = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(if (requestCode == REQ_SAVE) false else null)
            return true
        }
        try {
            if (requestCode == REQ_SAVE) {
                activity.contentResolver.openOutputStream(uri, "wt")?.use { it.write((text ?: "").toByteArray()) }
                result.success(true)
            } else {
                val s = activity.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
                result.success(s)
            }
        } catch (e: Exception) {
            result.error("backup", e.message, null)
        }
        text = null
        return true
    }
}
