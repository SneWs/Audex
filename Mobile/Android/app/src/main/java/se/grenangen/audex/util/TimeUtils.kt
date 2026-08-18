package se.grenangen.audex.util

import java.util.Locale

object TimeUtils {
    fun formatDuration(seconds: Int): String {
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return String.format(Locale.getDefault(), "%d:%02d:%02d", h, m, s)
    }

    fun formatDurationMs(ms: Long): String {
        return formatDuration((ms / 1000).toInt())
    }

    fun formatShortDuration(seconds: Int): String {
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        return if (h > 0) {
            String.format(Locale.getDefault(), "%dh %dm", h, m)
        } else {
            String.format(Locale.getDefault(), "%dm", m)
        }
    }
}
