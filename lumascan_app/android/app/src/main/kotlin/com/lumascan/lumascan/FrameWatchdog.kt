package com.lumascan.lumascan

import android.content.Intent

/**
 * Rules for the first-frame watchdog in [MainActivity] (UX-10).
 *
 * A Flutter window that never gets a frame stays on the splash or a black
 * screen while the app looks alive. Two causes were seen on the CPH2661:
 * the engine not drawing into a recreated surface, and a debug launch
 * intent with `start-paused` being reused after its debug session ended.
 */
object FrameWatchdog {
    /** Intent extra the Flutter tool adds to every debug launch. */
    const val START_PAUSED = "start-paused"

    /** How often to ask Dart for a frame while none has been shown. */
    const val NUDGE_EVERY_MS = 1_500L

    /** How long without a frame before the app is cold-restarted. */
    const val RESTART_AFTER_MS = 10_000L

    /** At most one automatic restart in this window, so a hang can't loop. */
    const val MIN_RESTART_GAP_MS = 120_000L

    enum class Step { NUDGE, RESTART, GIVE_UP }

    /**
     * True when [intent] still carries the Flutter tool's `start-paused` flag
     * but this start did not come from the tool: the activity is restored
     * after its process died, or reopened from Recents. No debugger will
     * resume Dart then, so the flag must be dropped.
     */
    fun isReusedDebugLaunch(intent: Intent, restoringState: Boolean): Boolean =
        isReusedDebugLaunch(
            startPaused = intent.getBooleanExtra(START_PAUSED, false),
            restoringState = restoringState,
            launchedFromHistory = intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0,
        )

    fun isReusedDebugLaunch(startPaused: Boolean, restoringState: Boolean, launchedFromHistory: Boolean): Boolean =
        startPaused && (restoringState || launchedFromHistory)

    /**
     * What to do after waiting [waitedMs] for a frame. A live debug session
     * ([debugSession]) may be paused at a breakpoint, so it is only nudged.
     */
    fun next(waitedMs: Long, debugSession: Boolean, lastRestartAt: Long, now: Long): Step = when {
        debugSession || waitedMs < RESTART_AFTER_MS -> Step.NUDGE
        now - lastRestartAt < MIN_RESTART_GAP_MS -> Step.GIVE_UP
        else -> Step.RESTART
    }
}
