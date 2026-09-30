package se.grenangen.audex.ui.screen.playlists

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import se.grenangen.audex.data.model.PlaylistDto
import se.grenangen.audex.data.repository.PlaylistRepository
import javax.inject.Inject

@HiltViewModel
class PlaylistsViewModel @Inject constructor(
    private val playlistRepository: PlaylistRepository
) : ViewModel() {
    private val _playlists = MutableStateFlow<List<PlaylistDto>>(emptyList())
    val playlists = _playlists.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    fun loadPlaylists() {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            playlistRepository.getPlaylists()
                .onSuccess { _playlists.value = it }
                .onFailure { _error.value = it.message ?: "Failed to load playlists" }
            _isLoading.value = false
        }
    }
}
