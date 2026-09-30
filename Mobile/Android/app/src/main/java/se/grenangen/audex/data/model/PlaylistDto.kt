package se.grenangen.audex.data.model

import kotlinx.serialization.Serializable

@Serializable
data class PlaylistDto(
    val id: Int,
    val name: String,
    val createdAt: String,
    val updatedAt: String,
    val books: List<BookDto> = emptyList()
)
