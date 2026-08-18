package se.grenangen.audex.ui.screen.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import se.grenangen.audex.data.model.BookDto
import se.grenangen.audex.data.repository.BookRepository
import se.grenangen.audex.playback.PlaybackManager
import javax.inject.Inject

enum class LibraryType {
    ALL, RECENTS, CONTINUE, FAVORITES
}

@HiltViewModel
class LibraryViewModel @Inject constructor(
    private val bookRepository: BookRepository,
    private val playbackManager: PlaybackManager
) : ViewModel() {

    private val _books = MutableStateFlow<List<BookDto>>(emptyList())
    val books = _books.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()

    val currentBook = playbackManager.currentBook
    val isPlaying = playbackManager.isPlaying

    fun loadBooks(type: LibraryType = LibraryType.ALL) {
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            val result = bookRepository.getBooks()
            _isLoading.value = false
            result.onSuccess { allBooks ->
                _books.value = when (type) {
                    LibraryType.ALL -> allBooks.sortedBy { it.title }
                    LibraryType.RECENTS -> allBooks.sortedByDescending { it.addedAt }.take(20)
                    LibraryType.CONTINUE -> allBooks.filter { it.isStarted && !it.isCompleted }
                        .sortedByDescending { it.lastPlayedAt }
                    LibraryType.FAVORITES -> allBooks.filter { it.isFavorite }.sortedBy { it.title }
                }
                android.util.Log.d("LibraryViewModel", "Loaded ${_books.value.size} books for type $type")
            }.onFailure { e ->
                _error.value = e.message ?: "Failed to load books"
                android.util.Log.e("LibraryViewModel", "Error loading books", e)
            }
        }
    }

    fun playBook(bookId: Int) {
        if (currentBook.value?.id == bookId) {
            playbackManager.togglePlayPause()
        } else {
            viewModelScope.launch {
                val result = bookRepository.getBook(bookId)
                result.onSuccess { bookDetail ->
                    playbackManager.playBook(bookDetail)
                }.onFailure { e ->
                    android.util.Log.e("LibraryViewModel", "Error loading book details for playback", e)
                }
            }
        }
    }

    fun toggleFavorite(bookId: Int) {
        viewModelScope.launch {
            val book = _books.value.find { it.id == bookId } ?: return@launch
            val newFavoriteState = !book.isFavorite
            
            // Optimistic update
            _books.value = _books.value.map {
                if (it.id == bookId) it.copy(isFavorite = newFavoriteState) else it
            }

            val result = bookRepository.toggleFavorite(bookId, newFavoriteState)
            result.onFailure {
                // Revert on failure
                _books.value = _books.value.map {
                    if (it.id == bookId) it.copy(isFavorite = !newFavoriteState) else it
                }
            }
        }
    }
}
