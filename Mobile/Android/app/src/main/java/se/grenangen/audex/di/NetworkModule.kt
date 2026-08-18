package se.grenangen.audex.di

import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import io.ktor.client.*
import io.ktor.client.engine.okhttp.*
import io.ktor.client.plugins.*
import io.ktor.client.plugins.auth.*
import io.ktor.client.plugins.auth.providers.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.logging.*
import io.ktor.client.plugins.observer.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.json.Json
import se.grenangen.audex.data.local.SettingsManager
import se.grenangen.audex.data.local.TokenManager
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
    fun provideHttpClient(json: Json, tokenManager: TokenManager, settingsManager: SettingsManager): HttpClient {
        return HttpClient(OkHttp) {
            install(ContentNegotiation) {
                json(json)
            }
            install(Logging) {
                logger = object : Logger {
                    override fun log(message: String) {
                        android.util.Log.d("Ktor", message)
                    }
                }
                level = LogLevel.ALL
            }
            install(Auth) {
                bearer {
                    loadTokens {
                        tokenManager.getToken()?.let { BearerTokens(it, "") }
                    }
                    sendWithoutRequest { request ->
                        val path = request.url.encodedPath
                        !path.endsWith("/login") && !path.endsWith("/register")
                    }
                }
            }
        }.also { client ->
            client.plugin(HttpSend).intercept { request ->
                val serverUri = settingsManager.getServerUri()
                if (serverUri != null && (request.url.host.isEmpty() || request.url.host == "localhost")) {
                    val baseUrl = Url(serverUri)
                    val requestPath = request.url.encodedPath.removePrefix("/")
                    
                    request.url.takeFrom(baseUrl)
                    
                    val basePath = baseUrl.encodedPath.removeSuffix("/")
                    request.url.encodedPath = if (basePath.isEmpty()) "/$requestPath" else "$basePath/$requestPath"
                }
                execute(request)
            }
        }
    }
}
