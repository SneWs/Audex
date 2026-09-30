package se.grenangen.audex.ui.screen.playlists

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import se.grenangen.audex.data.model.BookDto
import se.grenangen.audex.data.model.PlaylistDto
import se.grenangen.audex.data.repository.BookRepository
import se.grenangen.audex.data.repository.PlaylistRepository
import se.grenangen.audex.playback.PlaybackManager
import javax.inject.Inject

@HiltViewModel
class SeriesDetailViewModel @Inject constructor(
    private val playlistRepository: PlaylistRepository,
    private val bookRepository: BookRepository,
    private val playbackManager: PlaybackManager,
    savedStateHandle: SavedStateHandle
) : ViewModel() {
    private val playlistId: Int = checkNotNull(savedStateHandle["playlistId"])

    private val _playlist = MutableStateFlow<PlaylistDto?>(null)
    val playlist = _playlist.asStateFlow()

    private val _books = MutableStateFlow<List<BookDto>>(emptyList())
    val books = _books.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    val currentBook = playbackManager.currentBook
    val isPlaying = playbackManager.isPlaying

    init {
        loadSeries()
    }

    fun loadSeries() {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            playlistRepository.getPlaylist(playlistId)
                .onSuccess {
                    _playlist.value = it
                    _books.value = it.books
                }
                .onFailure { _error.value = it.message ?: "Failed to load series" }
            _isLoading.value = false
        }
    }

    fun playBook(bookId: Int) {
        if (currentBook.value?.id == bookId) {
            playbackManager.togglePlayPause()
        } else {
            viewModelScope.launch {
                bookRepository.getBook(bookId).onSuccess { bookDetail ->
                    playbackManager.playBook(bookDetail)
                }
            }
        }
    }

    fun toggleFavorite(bookId: Int) {
        viewModelScope.launch {
            val book = _books.value.find { it.id == bookId } ?: return@launch
            val newFavoriteState = !book.isFavorite
            _books.value = _books.value.map {
                if (it.id == bookId) it.copy(isFavorite = newFavoriteState) else it
            }

            bookRepository.toggleFavorite(bookId, newFavoriteState).onFailure {
                _books.value = _books.value.map {
                    if (it.id == bookId) it.copy(isFavorite = !newFavoriteState) else it
                }
            }
        }
    }

    fun completeBook(bookId: Int) {
        viewModelScope.launch {
            _books.value = _books.value.map {
                if (it.id == bookId) it.copy(isCompleted = true, progressSec = it.durationSec) else it
            }

            bookRepository.completeBook(bookId).onFailure {
                loadSeries()
            }
        }
    }
}
