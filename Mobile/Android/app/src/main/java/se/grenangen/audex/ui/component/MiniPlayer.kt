package se.grenangen.audex.ui.component

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import se.grenangen.audex.playback.PlaybackManager
import se.grenangen.audex.ui.composition.LocalServerUri
import se.grenangen.audex.util.TimeUtils

@Composable
fun MiniPlayer(
    playbackManager: PlaybackManager,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    val book by playbackManager.currentBook.collectAsState()
    val isPlaying by playbackManager.isPlaying.collectAsState()
    val position by playbackManager.currentPosition.collectAsState()
    val duration by playbackManager.currentDuration.collectAsState()
    val currentChapterIndex by playbackManager.currentChapterIndex.collectAsState()
    val sleepTimerEndTime by playbackManager.sleepTimerEndTime.collectAsState()
    val sleepTimerRemainingMillis by playbackManager.sleepTimerRemainingMillis.collectAsState()
    val serverUri = LocalServerUri.current
    var showSleepTimerDialog by remember { mutableStateOf(false) }

    if (book == null) return
    val hasMultipleChapters = book?.chapters.orEmpty().size > 1

    Surface(
        modifier = modifier
            .fillMaxWidth()
            .height(76.dp)
            .clickable(onClick = onClick),
        tonalElevation = 8.dp,
        shadowElevation = 8.dp
    ) {
        Column {
            LinearProgressIndicator(
                progress = { if (duration > 0) position.toFloat() / duration else 0f },
                modifier = Modifier.fillMaxWidth().height(2.dp),
                color = MaterialTheme.colorScheme.primary,
                trackColor = MaterialTheme.colorScheme.surfaceVariant
            )
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal))
                    .padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                AsyncImage(
                    model = "${serverUri}books/${book?.id}/cover",
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    contentScale = ContentScale.Crop
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = book?.title ?: "",
                        style = MaterialTheme.typography.titleSmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                    Text(
                        text = "${book?.author ?: ""} • ${TimeUtils.formatDurationMs(position)}",
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                if (hasMultipleChapters) {
                    IconButton(
                        onClick = playbackManager::skipToPreviousChapter,
                        enabled = currentChapterIndex > 0
                    ) {
                        Icon(
                            imageVector = Icons.Default.SkipPrevious,
                            contentDescription = "Previous chapter"
                        )
                    }
                    IconButton(
                        onClick = playbackManager::skipToNextChapter,
                        enabled = currentChapterIndex < book?.chapters.orEmpty().lastIndex
                    ) {
                        Icon(
                            imageVector = Icons.Default.SkipNext,
                            contentDescription = "Next chapter"
                        )
                    }
                }
                IconButton(onClick = { playbackManager.togglePlayPause() }) {
                    Icon(
                        imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                        contentDescription = if (isPlaying) "Pause" else "Play"
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    IconButton(onClick = { showSleepTimerDialog = true }) {
                        Icon(
                            imageVector = Icons.Default.Timer,
                            contentDescription = sleepTimerEndTime?.let { "Sleep timer active" } ?: "Set sleep timer"
                        )
                    }
                    sleepTimerRemainingMillis?.let { remainingMillis ->
                        Text(
                            text = TimeUtils.formatShortDuration(((remainingMillis + 999L) / 1_000L).toInt()),
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                }
            }
        }
    }

    if (showSleepTimerDialog) {
        SleepTimerDialog(
            hasActiveTimer = sleepTimerEndTime != null,
            onStartTimer = {
                playbackManager.startSleepTimer(it)
                showSleepTimerDialog = false
            },
            onCancelTimer = {
                playbackManager.cancelSleepTimer()
                showSleepTimerDialog = false
            },
            onDismiss = { showSleepTimerDialog = false }
        )
    }
}
