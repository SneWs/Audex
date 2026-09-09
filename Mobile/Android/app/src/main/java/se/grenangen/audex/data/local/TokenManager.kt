package se.grenangen.audex.data.local

import android.content.Context
import android.util.Base64
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TokenManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val json: Json
) : TokenProvider {
    private val prefs = context.getSharedPreferences("audex_auth", Context.MODE_PRIVATE)

    override fun getToken(): String? = prefs.getString("token", null)

    fun saveToken(token: String?) {
        prefs.edit().putString("token", token).apply()
    }

    fun isTokenNearExpiry(thresholdMinutes: Int = 5): Boolean {
        val token = getToken() ?: return false
        return try {
            val parts = token.split(".")
            if (parts.size != 3) return false
            val payload = String(Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP))
            val jsonObject = json.parseToJsonElement(payload).jsonObject
            val exp = jsonObject["exp"]?.jsonPrimitive?.long ?: return false
            val nowSeconds = System.currentTimeMillis() / 1000
            val thresholdSeconds = thresholdMinutes * 60
            exp < (nowSeconds + thresholdSeconds)
        } catch (e: Exception) {
            Log.e("TokenManager", "Error checking token expiry", e)
            false
        }
    }
}
