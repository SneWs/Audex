package se.grenangen.audex.ui.screen.detail

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import se.grenangen.audex.data.model.BookDetailDto
import se.grenangen.audex.data.repository.BookDownloadRepository
import se.grenangen.audex.data.repository.BookRepository
import se.grenangen.audex.playback.PlaybackManager
import javax.inject.Inject

@HiltViewModel
class BookDetailViewModel @Inject constructor(
    private val bookRepository: BookRepository,
    private val bookDownloadRepository: BookDownloadRepository,
    private val playbackManager: PlaybackManager,
    savedStateHandle: SavedStateHandle
) : ViewModel() {

    private val bookId: Int = checkNotNull(savedStateHandle["bookId"])

    private val _book = MutableStateFlow<BookDetailDto?>(null)
    val book = _book.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading = _isLoading.asStateFlow()

    private val _downloadState = MutableStateFlow<DownloadState>(DownloadState.Idle)
    val downloadState = _downloadState.asStateFlow()

    init {
        loadBook()
    }

    private fun loadBook() {
        viewModelScope.launch {
            _isLoading.value = true
            val result = bookRepository.getBook(bookId)
            _isLoading.value = false
            result.onSuccess {
                _book.value = it
            }.onFailure { e ->
                android.util.Log.e("BookDetailViewModel", "Error loading book $bookId", e)
            }
        }
    }

    fun playBook(chapterIndex: Int? = null) {
        _book.value?.let {
            playbackManager.playBook(it, chapterIndex)
        }
    }

    fun completeBook() {
        val book = _book.value ?: return
        viewModelScope.launch {
            _book.value = book.copy(isCompleted = true, progressSec = book.durationSec)
            val result = bookRepository.completeBook(book.id)
            result.onFailure {
                loadBook()
            }
        }
    }

    fun downloadBookForOffline() {
        val book = _book.value ?: return
        if (_downloadState.value is DownloadState.Downloading) return

        viewModelScope.launch {
            _downloadState.value = DownloadState.Downloading(0, book.chapters.orEmpty().size)
            runCatching {
                bookDownloadRepository.downloadBook(book) { downloaded, total ->
                    _downloadState.value = DownloadState.Downloading(downloaded, total)
                }
            }.onSuccess {
                _downloadState.value = DownloadState.Completed
            }.onFailure { e ->
                _downloadState.value = DownloadState.Error(e.message ?: "Failed to download book")
            }
        }
    }

    sealed interface DownloadState {
        data object Idle : DownloadState
        data class Downloading(val downloaded: Int, val total: Int) : DownloadState
        data object Completed : DownloadState
        data class Error(val message: String) : DownloadState
    }
}
