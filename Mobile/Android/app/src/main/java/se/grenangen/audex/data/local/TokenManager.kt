package se.grenangen.audex.data.local

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TokenManager @Inject constructor(
    @ApplicationContext private val context: Context
) : TokenProvider {
    private val prefs = context.getSharedPreferences("audex_auth", Context.MODE_PRIVATE)

    override fun getToken(): String? = prefs.getString("token", null)

    fun saveToken(token: String?) {
        prefs.edit().putString("token", token).apply()
    }
}
