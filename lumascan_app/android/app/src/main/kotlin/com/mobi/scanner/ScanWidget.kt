package com.mobi.scanner

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home-screen widget (improvement.md #16): Scan opens the camera and
 * Import opens the photo picker, each by starting [MainActivity] with a
 * launch action that it hands to Dart on [CHANNEL].
 */
class ScanWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        const val CHANNEL = "lumascan/launch"
        const val ACTION_LAUNCH = "com.mobi.scanner.LAUNCH"
        const val EXTRA_ACTION = "lumascan.launch_action"

        private fun views(context: Context) = RemoteViews(context.packageName, R.layout.scan_widget).apply {
            setOnClickPendingIntent(R.id.widget_scan, launch(context, "scan", 1))
            setOnClickPendingIntent(R.id.widget_import, launch(context, "import", 2))
        }

        private fun launch(context: Context, action: String, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(ACTION_LAUNCH)
                .putExtra(EXTRA_ACTION, action)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        /** The launch action [intent] carries, if it came from the widget. */
        fun actionOf(intent: Intent?): String? =
            if (intent?.action == ACTION_LAUNCH) intent.getStringExtra(EXTRA_ACTION) else null
    }
}
