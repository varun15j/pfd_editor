package com.lumascan.lumascan

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Process

/**
 * Cold-restarts LumaScan from a separate process (`:restart`).
 *
 * [MainActivity] starts this when the window never gets a frame. It kills
 * the stuck main process, then opens the app again with a clean launch
 * intent, so no debug flags carry over.
 */
class RestartActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val stuckPid = intent.getIntExtra(EXTRA_PID, -1)
        if (stuckPid > 0) Process.killProcess(stuckPid)
        packageManager.getLaunchIntentForPackage(packageName)?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            it.putExtra(EXTRA_RESTARTED, true)
            startActivity(it)
        }
        finish()
        Runtime.getRuntime().exit(0)
    }

    companion object {
        const val EXTRA_PID = "lumascan.stuck_pid"
        const val EXTRA_RESTARTED = "lumascan.watchdog_restarted"
    }
}
