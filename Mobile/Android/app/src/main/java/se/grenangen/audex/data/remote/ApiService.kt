package se.grenangen.audex.data.remote

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.request.*
import io.ktor.http.*
import se.grenangen.audex.data.model.*
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ApiService @Inject constructor(
    private val client: HttpClient
) {
    suspend fun login(request: LoginRequest): AuthResponse =
        client.post("login") {
            contentType(ContentType.Application.Json)
            setBody(request)
        }.body()

    suspend fun getBooks(): List<BookDto> =
        client.get("books").body()

    suspend fun getBook(id: Int): BookDetailDto =
        client.get("books/$id").body()

    suspend fun updateProgress(userId: String, progress: ProgressDto) =
        client.post("users/$userId/progress") {
            contentType(ContentType.Application.Json)
            setBody(progress)
        }

    suspend fun favoriteBook(id: Int) =
        client.put("books/$id/favorite")

    suspend fun unfavoriteBook(id: Int) =
        client.delete("books/$id/favorite")
}
