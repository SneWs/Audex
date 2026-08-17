package se.grenangen.audex.data.model

import kotlinx.serialization.Serializable

@Serializable
data class AuthResponse(
    val token: String
)
