package com.lumascan.lumascan

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock

/**
 * How busy the phone is, for work the camera can skip when it is short of
 * memory or CPU: reading the text of each auto-captured page to catch a
 * page taken twice (US-03.11).
 */
object DeviceLoad {
    const val CHANNEL = "lumascan/device_load"

    fun snapshot(context: Context): Map<String, Any?> {
        val activities = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo().also { activities.getMemoryInfo(it) }
        val thermal =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                (context.getSystemService(Context.POWER_SERVICE) as PowerManager).currentThermalStatus
            } else {
                null
            }
        return mapOf(
            "availableBytes" to memory.availMem,
            "totalBytes" to memory.totalMem,
            "lowMemory" to memory.lowMemory,
            "cores" to Runtime.getRuntime().availableProcessors(),
            // CPU time this app has used, and the clock, to work out its share.
            "cpuMs" to Process.getElapsedCpuTime(),
            "clockMs" to SystemClock.elapsedRealtime(),
            "thermal" to thermal,
        )
    }
}
