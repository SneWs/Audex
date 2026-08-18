package se.grenangen.audex.data.local

import android.content.Context
import android.util.Patterns
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton
import androidx.core.content.edit

@Singleton
class SettingsManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val prefs = context.getSharedPreferences("audex_settings", Context.MODE_PRIVATE)

    private val _serverUri = MutableStateFlow(prefs.getString("server_uri", null))
    val serverUri = _serverUri.asStateFlow()

    private val _darkMode = MutableStateFlow(prefs.getBoolean(DARK_MODE_KEY, true))
    val darkMode = _darkMode.asStateFlow()

    fun getServerUri(): String? = _serverUri.value

    fun setDarkMode(enabled: Boolean) {
        prefs.edit { putBoolean(DARK_MODE_KEY, enabled) }
        _darkMode.value = enabled
    }

    fun saveServerUri(uri: String) {
        val cleanUri = if (uri.endsWith("/")) uri else "$uri/"
        prefs.edit { putString("server_uri", cleanUri) }
        _serverUri.value = cleanUri
    }

    fun isValidUri(uri: String?): Boolean {
        if (uri.isNullOrBlank()) return false
        return Patterns.WEB_URL.matcher(uri).matches()
    }

    private companion object {
        const val DARK_MODE_KEY = "dark_mode"
    }
}
