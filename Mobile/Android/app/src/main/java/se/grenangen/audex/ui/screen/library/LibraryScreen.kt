package se.grenangen.audex.ui.screen.library

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Menu
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import se.grenangen.audex.ui.component.BookGrid

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    type: LibraryType = LibraryType.ALL,
    onBookClick: (Int) -> Unit,
    onMenuClick: (() -> Unit)? = null,
    viewModel: LibraryViewModel = hiltViewModel()
) {
    val books by viewModel.books.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val error by viewModel.error.collectAsState()
    val currentBook by viewModel.currentBook.collectAsState()
    val isPlaying by viewModel.isPlaying.collectAsState()

    LaunchedEffect(type) {
        viewModel.loadBooks(type)
    }

    Scaffold(
        topBar = { 
            TopAppBar(
                title = { 
                    Text(when(type) {
                        LibraryType.ALL -> "My Library"
                        LibraryType.RECENTS -> "Recently Added"
                        LibraryType.CONTINUE -> "Continue Listening"
                        LibraryType.FAVORITES -> "Favorites"
                    }) 
                },
                navigationIcon = {
                    if (onMenuClick != null) {
                        IconButton(onClick = onMenuClick) {
                            Icon(Icons.Default.Menu, contentDescription = "Menu")
                        }
                    }
                }
            ) 
        }
    ) { padding ->
        when {
            isLoading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            error != null -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(text = error!!, color = MaterialTheme.colorScheme.error)
                        Button(onClick = { viewModel.loadBooks(type) }) {
                            Text("Retry")
                        }
                    }
                }
            }
            books.isEmpty() -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Text("No books found")
                }
            }
            else -> {
                BookGrid(
                    books = books,
                    currentBookId = currentBook?.id,
                    isPlaying = isPlaying,
                    onBookClick = onBookClick,
                    onPlayClick = { bookId ->
                        if (currentBook?.id == bookId && isPlaying) {
                            // Already playing, so we toggle in the grid
                            // However, playBook currently restarts/resumes. 
                            // Let's add a togglePlayPause to ViewModel
                            viewModel.playBook(bookId)
                        } else {
                            viewModel.playBook(bookId)
                        }
                    },
                    onFavoriteClick = { bookId ->
                        viewModel.toggleFavorite(bookId)
                    },
                    contentPadding = padding
                )
            }
        }
    }
}
