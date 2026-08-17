package se.grenangen.audex.data.model

import kotlinx.serialization.Serializable

@Serializable
data class ProgressDto(
    val bookId: Int,
    val chapterId: Int,
    val positionSec: Int
)
