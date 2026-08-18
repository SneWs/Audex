package se.grenangen.audex.util

import androidx.core.text.HtmlCompat

object HtmlUtils {
    fun toPlainText(html: String): String =
        HtmlCompat.fromHtml(html, HtmlCompat.FROM_HTML_MODE_COMPACT)
            .toString()
            .trim()
}
