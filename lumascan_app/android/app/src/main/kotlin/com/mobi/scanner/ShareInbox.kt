package com.mobi.scanner

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File

/**
 * Images shared into the app from another app's share sheet, such as the
 * gallery. Each share is saved as one folder under [dir], which Dart reads
 * through the `lumascan/share_inbox` channel and imports as pages.
 *
 * A share is copied into a folder whose name starts with a dot and renamed
 * once every image is in, so Dart never picks up a half-copied share.
 */
object ShareInbox {
    const val CHANNEL = "lumascan/share_inbox"

    /** Most images taken from one share; the photo import screen shows each one. */
    private const val MAX_IMAGES = 100
    private const val TAG = "ShareInbox"

    fun dir(context: Context): File = File(context.filesDir, "share_inbox")

    /** The image URIs in a SEND or SEND_MULTIPLE [intent], in the order sent. */
    fun imageUris(intent: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> streamExtra(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> streamListExtra(intent)?.let { uris.addAll(it) }
        }
        // Some apps put the images in the clip data only.
        if (uris.isEmpty()) {
            intent.clipData?.let { clip -> for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { uris.add(it) } }
        }
        return uris.distinct().take(MAX_IMAGES)
    }

    /**
     * Copies [uris] into a new inbox folder and returns how many were saved.
     * Only `content:` URIs from other apps are read: a `file:` URI or one of
     * this app's own providers could point at the app's private files.
     */
    fun save(context: Context, uris: List<Uri>): Int {
        val resolver = context.contentResolver
        val batch = System.currentTimeMillis().toString()
        val incoming = File(dir(context), ".incoming-$batch").apply { mkdirs() }
        var saved = 0
        for (uri in uris) {
            if (uri.scheme != "content" || uri.authority?.startsWith(context.packageName) != false) continue
            val type = resolver.getType(uri)
            if (type != null && !type.startsWith("image/")) continue
            val ext = type?.let { MimeTypeMap.getSingleton().getExtensionFromMimeType(it) } ?: "jpg"
            val target = File(incoming, "%03d.%s".format(saved + 1, ext))
            try {
                resolver.openInputStream(uri)?.use { input -> target.outputStream().use { input.copyTo(it) } } ?: continue
                saved++
            } catch (e: Exception) {
                Log.w(TAG, "Could not read a shared image: ${e.message}")
                target.delete()
            }
        }
        if (saved == 0 || !incoming.renameTo(File(dir(context), batch))) {
            incoming.deleteRecursively()
            return 0
        }
        return saved
    }

    @Suppress("DEPRECATION")
    private fun streamExtra(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun streamListExtra(intent: Intent): List<Uri>? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
}
