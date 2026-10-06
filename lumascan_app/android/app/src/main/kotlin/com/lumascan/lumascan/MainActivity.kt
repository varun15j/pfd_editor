package com.lumascan.lumascan

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter and watches that its window actually gets a frame (UX-10).
 *
 * While the activity is resumed and Flutter shows nothing, Dart is asked
 * for a frame every [FrameWatchdog.NUDGE_EVERY_MS]. If none arrives within
 * [FrameWatchdog.RESTART_AFTER_MS], the app is cold-restarted through
 * [RestartActivity].
 */
class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var resumed = false
    private var uiDisplayed = false
    private var debugSession = false
    private var simulateHang = false
    private var waitedMs = 0L
    private var warned = false

    private val tick = Runnable { onTick() }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before super.onCreate, which turns these extras into engine flags.
        if (FrameWatchdog.isReusedDebugLaunch(intent, savedInstanceState != null)) {
            Log.w(TAG, "Dropping start-paused: no debug session will resume Dart")
            intent.removeExtra(FrameWatchdog.START_PAUSED)
        }
        debugSession = intent.getBooleanExtra(FrameWatchdog.START_PAUSED, false)
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        simulateHang = debuggable && intent.getBooleanExtra(EXTRA_SIMULATE_HANG, false)
        super.onCreate(savedInstanceState)
        if (intent.getBooleanExtra(RestartActivity.EXTRA_RESTARTED, false)) {
            intent.removeExtra(RestartActivity.EXTRA_RESTARTED)
            Toast.makeText(this, "LumaScan restarted because the screen stopped loading.", Toast.LENGTH_LONG).show()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        startWatching()
    }

    override fun onPause() {
        resumed = false
        handler.removeCallbacks(tick)
        super.onPause()
    }

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        if (simulateHang) return
        uiDisplayed = true
        handler.removeCallbacks(tick)
    }

    override fun onFlutterUiNoLongerDisplayed() {
        super.onFlutterUiNoLongerDisplayed()
        uiDisplayed = false
        startWatching()
    }

    private fun startWatching() {
        if (!resumed || uiDisplayed) return
        waitedMs = 0
        handler.removeCallbacks(tick)
        handler.postDelayed(tick, FrameWatchdog.NUDGE_EVERY_MS)
    }

    private fun onTick() {
        if (!resumed || uiDisplayed || isFinishing) return
        waitedMs += FrameWatchdog.NUDGE_EVERY_MS
        channel?.invokeMethod("redraw", null)
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val now = System.currentTimeMillis()
        when (FrameWatchdog.next(waitedMs, debugSession, prefs.getLong(LAST_RESTART, 0), now)) {
            FrameWatchdog.Step.NUDGE -> handler.postDelayed(tick, FrameWatchdog.NUDGE_EVERY_MS)
            FrameWatchdog.Step.GIVE_UP -> {
                if (!warned) {
                    warned = true
                    Log.w(TAG, "Still no frame after ${waitedMs} ms; restarted recently, not restarting again")
                    Toast.makeText(this, "LumaScan isn't responding. Close it from Recents and open it again.", Toast.LENGTH_LONG).show()
                }
                handler.postDelayed(tick, FrameWatchdog.NUDGE_EVERY_MS)
            }
            FrameWatchdog.Step.RESTART -> {
                Log.w(TAG, "No frame after ${waitedMs} ms; cold-restarting")
                prefs.edit().putLong(LAST_RESTART, now).commit()
                startActivity(
                    Intent(this, RestartActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        .putExtra(RestartActivity.EXTRA_PID, Process.myPid()),
                )
            }
        }
    }

    companion object {
        private const val TAG = "FrameWatchdog"
        private const val CHANNEL = "lumascan/frame_watchdog"
        private const val PREFS = "frame_watchdog"
        private const val LAST_RESTART = "last_restart_at"

        /** Debug builds only: ignore frames so the restart path can be tested. */
        private const val EXTRA_SIMULATE_HANG = "lumascan.simulate_hang"
    }
}
