package se.grenangen.audex.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.ktor.client.*
import io.ktor.client.engine.okhttp.*
import io.ktor.client.call.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import se.grenangen.audex.data.local.SettingsManager
import se.grenangen.audex.data.local.TokenManager
import se.grenangen.audex.data.model.AuthResponse
import se.grenangen.audex.util.AuthEvent
import se.grenangen.audex.util.AuthEventBus
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    @Provides
    @Singleton
    fun provideJson(): Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    @Provides
    @Singleton
    fun provideOkHttpClient(tokenManager: TokenManager): OkHttpClient {
        return OkHttpClient.Builder()
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
            .addInterceptor { chain ->
                val requestBuilder = chain.request().newBuilder()
                tokenManager.getToken()?.let { token ->
                    requestBuilder.header("Authorization", "Bearer $token")
                }
                chain.proceed(requestBuilder.build())
            }
            .build()
    }

    @Provides
    @Singleton
    fun provideHttpClient(
        json: Json,
        tokenManager: TokenManager,
        settingsManager: SettingsManager,
        okHttpClient: okhttp3.OkHttpClient,
        authEventBus: AuthEventBus
    ): HttpClient {
        return HttpClient(OkHttp) {
            engine {
                preconfigured = okHttpClient
            }
            expectSuccess = true
            install(ContentNegotiation) {
                json(json)
            }
            install(Logging) {
                logger = object : Logger {
                    override fun log(message: String) {
                        android.util.Log.d("Ktor", message)
                    }
                }
                level = LogLevel.HEADERS
            }
        }.also { client ->
            client.plugin(HttpSend).intercept { request ->
                val path = request.url.encodedPath
                val isAuthRequest = path.endsWith("/login") || path.endsWith("/register")
                val isRefreshRequest = path.endsWith("/refresh")

                if (!isAuthRequest) {
                    if (!isRefreshRequest && tokenManager.isTokenNearExpiry()) {
                        try {
                            val refreshResponse = client.post("refresh")
                            if (refreshResponse.status == HttpStatusCode.OK) {
                                val authResponse = refreshResponse.body<AuthResponse>()
                                tokenManager.saveToken(authResponse.token)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("NetworkModule", "Failed to refresh token", e)
                        }
                    }

                    tokenManager.getToken()?.let { token ->
                        request.headers[HttpHeaders.Authorization] = "Bearer $token"
                    }
                }

                val serverUri = settingsManager.getServerUri()
                if (serverUri != null && (request.url.host.isEmpty() || request.url.host == "localhost")) {
                    val baseUrl = Url(serverUri)
                    val requestPath = request.url.encodedPath.removePrefix("/")
                    
                    request.url.takeFrom(baseUrl)
                    
                    val basePath = baseUrl.encodedPath.removeSuffix("/")
                    request.url.encodedPath = if (basePath.isEmpty()) "/$requestPath" else "$basePath/$requestPath"
                }

                val response = execute(request)
                
                if (response.response.status == HttpStatusCode.Unauthorized && !isAuthRequest) {
                    tokenManager.saveToken(null)
                    authEventBus.tryEmit(AuthEvent.SessionExpired("Session expired. Please log in again."))
                }

                response
            }
        }
    }
}
