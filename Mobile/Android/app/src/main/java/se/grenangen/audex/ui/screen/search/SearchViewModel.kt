package se.grenangen.audex.ui.screen.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import se.grenangen.audex.data.model.BookDto
import se.grenangen.audex.data.repository.BookRepository
import se.grenangen.audex.playback.PlaybackManager
import javax.inject.Inject

@HiltViewModel
class SearchViewModel @Inject constructor(
    private val bookRepository: BookRepository,
    private val playbackManager: PlaybackManager
) : ViewModel() {

    private val _query = MutableStateFlow("")
    val query = _query.asStateFlow()

    private val _books = MutableStateFlow<List<BookDto>>(emptyList())
    
    val searchResults = combine(_query, _books) { query, books ->
        if (query.isBlank()) {
            emptyList()
        } else {
            books.filter { 
                it.title.contains(query, ignoreCase = true) || 
                it.author.contains(query, ignoreCase = true) 
            }
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val currentBook = playbackManager.currentBook
    val isPlaying = playbackManager.isPlaying

    init {
        loadAllBooks()
    }

    private fun loadAllBooks() {
        viewModelScope.launch {
            val result = bookRepository.getBooks()
            result.onSuccess { _books.value = it }
        }
    }

    fun onQueryChange(newQuery: String) {
        _query.value = newQuery
    }

    fun playBook(bookId: Int) {
        if (currentBook.value?.id == bookId) {
            playbackManager.togglePlayPause()
        } else {
            viewModelScope.launch {
                val result = bookRepository.getBook(bookId)
                result.onSuccess { bookDetail ->
                    playbackManager.playBook(bookDetail)
                }
            }
        }
    }
}
