package se.grenangen.audex.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = AudexPrimary,
    secondary = AudexSecondaryDark,
    background = AudexDarkBackground,
    surface = AudexDarkSurface,
    surfaceVariant = AudexDarkSurface,
    onPrimary = AudexDarkOnSurface,
    onSecondary = AudexDarkOnSurface,
    onBackground = AudexDarkOnSurface,
    onSurface = AudexDarkOnSurface,
    onSurfaceVariant = AudexDarkOnSurfaceVariant
)

private val LightColorScheme = lightColorScheme(
    primary = AudexPrimary,
    secondary = AudexSecondaryLight,
    background = AudexLightBackground,
    surface = AudexLightSurface,
    surfaceVariant = AudexLightSurfaceVariant,
    onPrimary = Color.White,
    onSecondary = Color.White,
    onBackground = AudexLightOnSurface,
    onSurface = AudexLightOnSurface,
    onSurfaceVariant = AudexLightOnSurfaceVariant
)

@Composable
fun AudexTheme(
    darkTheme: Boolean,
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content
    )
}
