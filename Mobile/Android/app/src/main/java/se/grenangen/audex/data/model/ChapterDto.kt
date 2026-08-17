package se.grenangen.audex.data.model

import kotlinx.serialization.Serializable

@Serializable
data class ChapterDto(
    val id: Int,
    val title: String,
    val durationSec: Int,
    val trackNumber: Int
)
