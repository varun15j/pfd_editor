package com.mobi.scanner

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/**
 * Receives images shared from the gallery (or any app's share sheet). It
 * has no screen of its own: it copies the images into [ShareInbox] while it
 * still may read them, then opens the app the way the launcher icon does, so
 * an app already running comes to the front instead of starting twice. The
 * app finds the share in the inbox when it resumes.
 */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val fromHistory = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        val uris = if (savedInstanceState == null && !fromHistory) ShareInbox.imageUris(intent) else emptyList()
        if (uris.isEmpty()) {
            openApp()
            return
        }
        Thread {
            val saved = ShareInbox.save(applicationContext, uris)
            runOnUiThread {
                if (saved == 0) Toast.makeText(this, "Those images could not be read.", Toast.LENGTH_LONG).show()
                openApp()
            }
        }.start()
    }

    private fun openApp() {
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
            startActivity(it)
        }
        finish()
    }
}
