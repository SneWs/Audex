package se.grenangen.audex.ui.component

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import se.grenangen.audex.data.model.BookDto
import se.grenangen.audex.util.TimeUtils

@Composable
fun BookGrid(
    books: List<BookDto>,
    currentBookId: Int?,
    isPlaying: Boolean,
    onBookClick: (Int) -> Unit,
    onPlayClick: (Int) -> Unit,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    modifier: Modifier = Modifier
) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(150.dp),
        contentPadding = contentPadding,
        modifier = modifier.padding(8.dp)
    ) {
        items(books) { book ->
            val isThisBookPlaying = book.id == currentBookId && isPlaying
            BookItem(
                book = book, 
                isPlaying = isThisBookPlaying,
                onClick = { onBookClick(book.id) },
                onPlayClick = { onPlayClick(book.id) }
            )
        }
    }
}

@Composable
fun BookItem(
    book: BookDto, 
    isPlaying: Boolean,
    onClick: () -> Unit, 
    onPlayClick: () -> Unit
) {
    Card(
        modifier = Modifier
            .padding(8.dp)
            .clickable(onClick = onClick)
    ) {
        Column {
            Box(modifier = Modifier.height(200.dp)) {
                AsyncImage(
                    model = "https://books.grenangen.se/api/books/${book.id}/cover",
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
                
                Surface(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(8.dp),
                    shape = androidx.compose.foundation.shape.CircleShape,
                    color = MaterialTheme.colorScheme.primary,
                    contentColor = Color.White,
                    tonalElevation = 4.dp,
                    shadowElevation = 4.dp
                ) {
                    IconButton(
                        onClick = onPlayClick,
                        modifier = Modifier.size(40.dp)
                    ) {
                        Icon(
                            imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                            contentDescription = if (isPlaying) "Pause" else if (book.isStarted) "Resume" else "Play"
                        )
                    }
                }
            }
            Text(
                text = book.title,
                modifier = Modifier.padding(8.dp),
                maxLines = 2,
                style = MaterialTheme.typography.titleSmall,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
            )
            if (book.isStarted) {
                LinearProgressIndicator(
                    progress = { book.progressSec.toFloat() / book.durationSec.coerceAtLeast(1) },
                    modifier = Modifier.fillMaxWidth().height(2.dp).padding(horizontal = 8.dp),
                    color = MaterialTheme.colorScheme.primary,
                    trackColor = MaterialTheme.colorScheme.surfaceVariant
                )
                Text(
                    text = "${TimeUtils.formatDuration(book.progressSec)} / ${TimeUtils.formatDuration(book.durationSec)}",
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else {
                Text(
                    text = TimeUtils.formatDuration(book.durationSec),
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}
