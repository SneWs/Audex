package se.grenangen.audex.ui.screen.detail

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import se.grenangen.audex.util.HtmlUtils
import se.grenangen.audex.util.TimeUtils

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BookDetailScreen(
    onBackClick: () -> Unit,
    onPlayClick: () -> Unit,
    viewModel: BookDetailViewModel = hiltViewModel()
) {
    val book by viewModel.book.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(book?.title ?: "Book Detail") },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        },
        floatingActionButton = {
            book?.let {
                FloatingActionButton(onClick = {
                    viewModel.playBook()
                    onPlayClick()
                }) {
                    Icon(Icons.Default.PlayArrow, contentDescription = "Play")
                }
            }
        }
    ) { padding ->
        when {
            isLoading -> {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            }
            book == null -> {
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Text("Failed to load book details")
                }
            }
            else -> {
                val detail = book!!
                LazyColumn(contentPadding = padding) {
                    item {
                        Column(Modifier.padding(16.dp)) {
                            Text(text = detail.author, style = MaterialTheme.typography.titleMedium)
                            Text(
                                text = "Total duration: ${TimeUtils.formatDuration(detail.durationSec)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = detail.description?.let(HtmlUtils::toPlainText).orEmpty(),
                                style = MaterialTheme.typography.bodyMedium
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Text(text = "Chapters", style = MaterialTheme.typography.titleLarge)
                        }
                    }
                    itemsIndexed(detail.chapters.orEmpty()) { index, chapter ->
                        ListItem(
                            headlineContent = { Text(chapter.title) },
                            supportingContent = { Text(TimeUtils.formatDuration(chapter.durationSec)) },
                            modifier = Modifier.clickable {
                                viewModel.playBook(index)
                                onPlayClick()
                            }
                        )
                    }
                }
            }
        }
    }
}
