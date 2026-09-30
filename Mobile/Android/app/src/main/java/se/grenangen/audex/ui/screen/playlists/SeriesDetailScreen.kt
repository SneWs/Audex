package se.grenangen.audex.ui.screen.playlists

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import se.grenangen.audex.ui.component.BookGrid

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SeriesDetailScreen(
    onBackClick: () -> Unit,
    onBookClick: (Int) -> Unit,
    viewModel: SeriesDetailViewModel = hiltViewModel()
) {
    val playlist by viewModel.playlist.collectAsState()
    val books by viewModel.books.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    val currentBook by viewModel.currentBook.collectAsState()
    val isPlaying by viewModel.isPlaying.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(playlist?.name ?: "Series") },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        when {
            isLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
            error != null -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(error!!, color = MaterialTheme.colorScheme.error)
                    Text(
                        "Tap to retry",
                        modifier = Modifier
                            .padding(top = 8.dp)
                            .clickable { viewModel.loadSeries() }
                    )
                }
            }
            books.isEmpty() -> Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text("No books in this series")
            }
            else -> BookGrid(
                books = books,
                currentBookId = currentBook?.id,
                isPlaying = isPlaying,
                onBookClick = onBookClick,
                onPlayClick = { bookId -> viewModel.playBook(bookId) },
                onFavoriteClick = { bookId -> viewModel.toggleFavorite(bookId) },
                onCompleteClick = { bookId -> viewModel.completeBook(bookId) },
                contentPadding = padding,
                state = rememberLazyGridState()
            )
        }
    }
}
