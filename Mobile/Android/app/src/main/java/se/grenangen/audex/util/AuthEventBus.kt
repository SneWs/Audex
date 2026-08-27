package se.grenangen.audex.util

import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AuthEventBus @Inject constructor() {
    private val _events = MutableSharedFlow<AuthEvent>(extraBufferCapacity = 1)
    val events = _events.asSharedFlow()

    suspend fun emit(event: AuthEvent) {
        _events.emit(event)
    }

    fun tryEmit(event: AuthEvent) {
        _events.tryEmit(event)
    }
}

sealed class AuthEvent {
    data class SessionExpired(val message: String) : AuthEvent()
}
