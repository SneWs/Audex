package se.grenangen.audex.data.repository

import se.grenangen.audex.data.model.PlaylistDto
import se.grenangen.audex.data.remote.ApiService
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlaylistRepository @Inject constructor(
    private val apiService: ApiService
) {
    suspend fun getPlaylists(): Result<List<PlaylistDto>> =
        try {
            Result.success(apiService.getPlaylists())
        } catch (e: Exception) {
            Result.failure(e)
        }

    suspend fun getPlaylist(id: Int): Result<PlaylistDto> =
        try {
            Result.success(apiService.getPlaylist(id))
        } catch (e: Exception) {
            Result.failure(e)
        }
}
