package com.mobi.scanner

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Saves exported files where the user picks in the system screens, so the
 * app never keeps its exports: Documents, Downloads, an SD card, Google
 * Drive or any other storage the phone offers.
 *
 * - `saveFile` (path, name, mimeType): the system "Save to" screen
 *   (ACTION_CREATE_DOCUMENT), where the user picks the folder and can change
 *   the name. Returns the name of the saved file, or null when cancelled.
 * - `saveToFolder` (paths, mimeType): the system folder picker
 *   (ACTION_OPEN_DOCUMENT_TREE), then every file is copied into the folder
 *   picked, such as one JPG per page. Returns the folder's name, or null
 *   when cancelled.
 *
 * Files are copied as streams off the main thread, so a large PDF is never
 * held in memory.
 */
class ExportSaver(private val activity: Activity) {
    private var pending: Pending? = null
    private val io = Executors.newSingleThreadExecutor()

    private class Pending(val result: MethodChannel.Result, val paths: List<String>, val mimeType: String)

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("busy", "A save screen is already open", null)
            return
        }
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        when (call.method) {
            "saveFile" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("args", "path is missing", null)
                    return
                }
                val name = call.argument<String>("name") ?: File(path).name
                pending = Pending(result, listOf(path), mimeType)
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType(mimeType)
                    .putExtra(Intent.EXTRA_TITLE, name)
                start(intent, SAVE_FILE)
            }
            "saveToFolder" -> {
                val paths = call.argument<List<String>>("paths")
                if (paths.isNullOrEmpty()) {
                    result.error("args", "paths is missing", null)
                    return
                }
                pending = Pending(result, paths, mimeType)
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    .addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                start(intent, SAVE_TO_FOLDER)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(intent: Intent, requestCode: Int) {
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(intent, requestCode)
        } catch (e: Exception) {
            finishError("no_picker", "This phone has no screen to pick where to save (${e.message})")
        }
    }

    /** True when [requestCode] was one of ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != SAVE_FILE && requestCode != SAVE_TO_FOLDER) return false
        val job = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            job.result.success(null)
            return true
        }
        io.execute {
            try {
                val saved = if (requestCode == SAVE_FILE) copyToDocument(job, uri) else copyToFolder(job, uri)
                activity.runOnUiThread { finishSuccess(saved) }
            } catch (e: Exception) {
                Log.w(TAG, "Save failed", e)
                activity.runOnUiThread { finishError("write", e.message ?: e.toString()) }
            }
        }
        return true
    }

    private fun copyToDocument(job: Pending, uri: Uri): String {
        copy(File(job.paths.first()), uri)
        return displayName(uri) ?: File(job.paths.first()).name
    }

    private fun copyToFolder(job: Pending, tree: Uri): String {
        val resolver = activity.contentResolver
        val folder = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        for (path in job.paths) {
            val file = File(path)
            // The provider gives a file with a taken name a number, so
            // nothing already in the folder is replaced.
            val target = DocumentsContract.createDocument(resolver, folder, job.mimeType, file.name)
                ?: throw IllegalStateException("Could not create ${file.name} in the folder")
            copy(file, target)
        }
        return displayName(folder) ?: "the folder"
    }

    private fun copy(file: File, target: Uri) {
        val out = activity.contentResolver.openOutputStream(target, "wt")
            ?: throw IllegalStateException("Could not write to the place picked")
        out.use { o -> file.inputStream().use { it.copyTo(o) } }
    }

    private fun displayName(uri: Uri): String? = try {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    } catch (e: Exception) {
        null
    }

    private fun finishSuccess(value: String) {
        val job = pending ?: return
        pending = null
        job.result.success(value)
    }

    private fun finishError(code: String, message: String) {
        val job = pending ?: return
        pending = null
        job.result.error(code, message, null)
    }

    companion object {
        const val CHANNEL = "lumascan/export_saver"
        private const val TAG = "ExportSaver"
        private const val SAVE_FILE = 7311
        private const val SAVE_TO_FOLDER = 7312
    }
}
