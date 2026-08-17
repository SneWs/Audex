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
        client.post("api/login") {
            contentType(ContentType.Application.Json)
            setBody(request)
        }.body()

    suspend fun getBooks(): List<BookDto> =
        client.get("api/books").body()

    suspend fun getBook(id: Int): BookDetailDto =
        client.get("api/books/$id").body()

    suspend fun updateProgress(userId: String, progress: ProgressDto) =
        client.post("api/users/$userId/progress") {
            contentType(ContentType.Application.Json)
            setBody(progress)
        }

    suspend fun favoriteBook(id: Int) =
        client.put("api/books/$id/favorite")

    suspend fun unfavoriteBook(id: Int) =
        client.delete("api/books/$id/favorite")
}
