package se.grenangen.audex.ui.screen.player

import android.content.res.Configuration
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import se.grenangen.audex.ui.component.SleepTimerDialog
import se.grenangen.audex.ui.composition.LocalServerUri
import se.grenangen.audex.util.TimeUtils

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen(
    onBackClick: () -> Unit,
    viewModel: PlayerViewModel = hiltViewModel()
) {
    val book by viewModel.currentBook.collectAsState()
    val isPlaying by viewModel.isPlaying.collectAsState()
    val currentPosition by viewModel.currentPosition.collectAsState()
    val currentDuration by viewModel.currentDuration.collectAsState()
    val currentChapterIndex by viewModel.currentChapterIndex.collectAsState()
    val sleepTimerEndTime by viewModel.sleepTimerEndTime.collectAsState()
    val sleepTimerRemainingMillis by viewModel.sleepTimerRemainingMillis.collectAsState()
    var showSleepTimerDialog by remember { mutableStateOf(false) }
    val hasMultipleChapters = book?.chapters.orEmpty().size > 1
    val hasCover = book?.hasCover == true
    val serverUri = LocalServerUri.current
    val coverUrl = if (hasCover) "${serverUri}books/${book?.id}/cover" else null
    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    val scrollState = rememberScrollState()

    LaunchedEffect(isLandscape, scrollState.maxValue) {
        if (isLandscape) {
            scrollState.scrollTo(scrollState.maxValue)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Now Playing") },
                navigationIcon = {
                    IconButton(onClick = onBackClick) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                }
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            if (coverUrl != null) {
                AsyncImage(
                    model = coverUrl,
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop
                )
            }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        MaterialTheme.colorScheme.surface.copy(
                            alpha = if (coverUrl != null) 0.84f else 1f
                        )
                    )
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(scrollState)
                        .padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(text = book?.title ?: "No Book Playing", style = MaterialTheme.typography.headlineSmall)
                    Text(text = book?.author ?: "", style = MaterialTheme.typography.titleMedium)
                    if (coverUrl != null && !isLandscape) {
                        Spacer(modifier = Modifier.height(32.dp))
                        AsyncImage(
                            model = coverUrl,
                            contentDescription = "Cover for ${book?.title}",
                            modifier = Modifier
                                .size(192.dp)
                                .shadow(12.dp, RoundedCornerShape(24.dp))
                                .clip(RoundedCornerShape(24.dp)),
                            contentScale = ContentScale.Crop
                        )
                        Spacer(modifier = Modifier.height(32.dp))
                    } else {
                        Spacer(modifier = Modifier.height(32.dp))
                    }
                    Slider(
                        value = currentPosition.toFloat(),
                        onValueChange = { viewModel.seekTo(it.toLong()) },
                        valueRange = 0f..currentDuration.toFloat().coerceAtLeast(1f),
                        modifier = Modifier.fillMaxWidth()
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text(text = TimeUtils.formatDurationMs(currentPosition))
                        Text(text = TimeUtils.formatDurationMs(currentDuration))
                    }
                    Spacer(modifier = Modifier.height(24.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        if (hasMultipleChapters) {
                            IconButton(
                                onClick = viewModel::skipToPreviousChapter,
                                enabled = currentChapterIndex > 0,
                                modifier = Modifier.size(64.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.SkipPrevious,
                                    contentDescription = "Previous chapter",
                                    modifier = Modifier.size(40.dp)
                                )
                            }
                        }
                        IconButton(
                            onClick = viewModel::togglePlayPause,
                            modifier = Modifier.size(80.dp)
                        ) {
                            Icon(
                                imageVector = if (isPlaying) Icons.Default.Pause else Icons.Default.PlayArrow,
                                contentDescription = if (isPlaying) "Pause" else "Play",
                                modifier = Modifier.size(64.dp)
                            )
                        }
                        if (hasMultipleChapters) {
                            IconButton(
                                onClick = viewModel::skipToNextChapter,
                                enabled = currentChapterIndex < book?.chapters.orEmpty().lastIndex,
                                modifier = Modifier.size(64.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.SkipNext,
                                    contentDescription = "Next chapter",
                                    modifier = Modifier.size(40.dp)
                                )
                            }
                        }
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            IconButton(
                                onClick = { showSleepTimerDialog = true },
                                modifier = Modifier.size(64.dp)
                            ) {
                                Icon(
                                    imageVector = Icons.Default.Timer,
                                    contentDescription = sleepTimerEndTime?.let { "Sleep timer active" }
                                        ?: "Set sleep timer",
                                    modifier = Modifier.size(32.dp)
                                )
                            }
                            sleepTimerRemainingMillis?.let { remainingMillis ->
                                Text(
                                    text = TimeUtils.formatShortDuration(
                                        ((remainingMillis + 999L) / 1_000L).toInt()
                                    ),
                                    style = MaterialTheme.typography.labelSmall
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    if (showSleepTimerDialog) {
        SleepTimerDialog(
            hasActiveTimer = sleepTimerEndTime != null,
            onStartTimer = {
                viewModel.startSleepTimer(it)
                showSleepTimerDialog = false
            },
            onCancelTimer = {
                viewModel.cancelSleepTimer()
                showSleepTimerDialog = false
            },
            onDismiss = { showSleepTimerDialog = false }
        )
    }
}
