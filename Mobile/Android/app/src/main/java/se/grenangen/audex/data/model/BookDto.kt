package se.grenangen.audex.data.model

import kotlinx.serialization.Serializable

@Serializable
data class BookDto(
    val id: Int,
    val title: String,
    val customTitle: String? = null,
    val subtitle: String? = null,
    val author: String,
    val year: Int? = null,
    val readBy: String? = null,
    val durationSec: Int,
    val chapterCount: Int,
    val hasCover: Boolean,
    val description: String? = null,
    val publisher: String? = null,
    val language: String? = null,
    val isbn10: String? = null,
    val isbn13: String? = null,
    val pageCount: Int? = null,
    val rating: Double? = null,
    val ratingCount: Int? = null,
    val openLibraryUrl: String? = null,
    val addedAt: String, // DateTime in C#
    val progressSec: Int,
    val isCompleted: Boolean,
    var isFavorite: Boolean,
    val lastPlayedAt: String? = null,
    val resumeChapterId: Int? = null,
    val resumePositionSec: Int,
    val genres: List<String>? = emptyList()
) {
    val isStarted: Boolean get() = lastPlayedAt != null
}
