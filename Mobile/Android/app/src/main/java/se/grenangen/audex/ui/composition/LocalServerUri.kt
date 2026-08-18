package se.grenangen.audex.ui.composition

import androidx.compose.runtime.staticCompositionLocalOf

val LocalServerUri = staticCompositionLocalOf<String> {
    error("No Server URI provided")
}
