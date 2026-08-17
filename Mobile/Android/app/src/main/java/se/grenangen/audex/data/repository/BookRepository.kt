package se.grenangen.audex.data.repository

import se.grenangen.audex.data.model.BookDetailDto
import se.grenangen.audex.data.model.BookDto
import se.grenangen.audex.data.model.ProgressDto
import se.grenangen.audex.data.remote.ApiService
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BookRepository @Inject constructor(
    private val apiService: ApiService
) {
    suspend fun getBooks(): Result<List<BookDto>> {
        return try {
            Result.success(apiService.getBooks())
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun getBook(id: Int): Result<BookDetailDto> {
        return try {
            Result.success(apiService.getBook(id))
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun updateProgress(userId: String, progress: ProgressDto): Result<Unit> {
        return try {
            apiService.updateProgress(userId, progress)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun toggleFavorite(id: Int, isFavorite: Boolean): Result<Unit> {
        return try {
            if (isFavorite) {
                apiService.favoriteBook(id)
            } else {
                apiService.unfavoriteBook(id)
            }
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
