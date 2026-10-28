package se.grenangen.audex.data.repository

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import android.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import se.grenangen.audex.data.local.TokenManager
import se.grenangen.audex.data.model.AuthResponse
import se.grenangen.audex.data.model.LoginRequest
import se.grenangen.audex.data.remote.ApiService
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthRepository @Inject constructor(
    private val apiService: ApiService,
    private val tokenManager: TokenManager,
    private val json: Json
) {
    fun getToken(): String? = tokenManager.getToken()

    fun getUserId(): String? = tokenPayload()?.let { payload ->
        payload["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier"]?.jsonPrimitive?.content
            ?: payload["sub"]?.jsonPrimitive?.content
    }

    fun getEmail(): String? = tokenPayload()?.let { payload ->
        payload["http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"]?.jsonPrimitive?.content
            ?: payload["email"]?.jsonPrimitive?.content
    }

    private fun tokenPayload(): JsonObject? {
        val token = getToken() ?: return null
        return try {
            val parts = token.split(".")
            if (parts.size != 3) return null
            val payload = String(Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP))
            json.parseToJsonElement(payload).jsonObject
        } catch (e: Exception) {
            null
        }
    }

    suspend fun login(request: LoginRequest): Result<AuthResponse> {
        return try {
            val response = apiService.login(request)
            tokenManager.saveToken(response.token)
            Result.success(response)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun refreshToken(): Result<AuthResponse> {
        return try {
            val response = apiService.refreshToken()
            tokenManager.saveToken(response.token)
            Result.success(response)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    /**
     * Refreshes the token if it is nearing expiry. Safe to call repeatedly;
     * does nothing when not logged in or when the token is still valid.
     */
    suspend fun refreshIfNearingExpiry() {
        if (!isLoggedIn()) return
        if (!isTokenNearExpiry()) return
        refreshToken()
    }

    fun isTokenNearExpiry(): Boolean = tokenManager.isTokenNearExpiry()

    fun logout() {
        tokenManager.saveToken(null)
    }

    fun isLoggedIn(): Boolean = getToken() != null
}
