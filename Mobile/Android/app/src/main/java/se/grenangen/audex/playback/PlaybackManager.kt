package se.grenangen.audex.playback

import android.content.ComponentName
import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import se.grenangen.audex.data.local.SettingsManager
import se.grenangen.audex.data.model.BookDetailDto
import se.grenangen.audex.data.model.ProgressDto
import se.grenangen.audex.data.repository.AuthRepository
import se.grenangen.audex.data.repository.BookRepository
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlaybackManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val bookRepository: BookRepository,
    private val authRepository: AuthRepository,
    private val settingsManager: SettingsManager
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var lastSyncTime = 0L
    private val SYNC_INTERVAL_MS = 10000L // Sync every 10 seconds

    private var controllerFuture: ListenableFuture<MediaController>? = null
    private val controller: MediaController?
        get() = if (controllerFuture?.isDone == true) controllerFuture?.get() else null

    private val _currentBook = MutableStateFlow<BookDetailDto?>(null)
    val currentBook = _currentBook.asStateFlow()

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying = _isPlaying.asStateFlow()

    private val _currentPosition = MutableStateFlow(0L)
    val currentPosition = _currentPosition.asStateFlow()

    private val _currentDuration = MutableStateFlow(0L)
    val currentDuration = _currentDuration.asStateFlow()

    private val _currentChapterIndex = MutableStateFlow(0)
    val currentChapterIndex = _currentChapterIndex.asStateFlow()

    private val _sleepTimerEndTime = MutableStateFlow<Long?>(null)
    val sleepTimerEndTime = _sleepTimerEndTime.asStateFlow()
    private val _sleepTimerRemainingMillis = MutableStateFlow<Long?>(null)
    val sleepTimerRemainingMillis = _sleepTimerRemainingMillis.asStateFlow()
    private var sleepTimerJob: Job? = null

    init {
        val sessionToken = SessionToken(context, ComponentName(context, PlaybackService::class.java))
        controllerFuture = MediaController.Builder(context, sessionToken).buildAsync()
        controllerFuture?.addListener({
            setupController()
        }, MoreExecutors.directExecutor())

        startProgressTimer()
    }

    private fun setupController() {
        val c = controller ?: return
        c.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                _isPlaying.value = isPlaying
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                if (playbackState == Player.STATE_READY) {
                    _currentDuration.value = c.duration
                }
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                _currentChapterIndex.value = c.currentMediaItemIndex
                _currentPosition.value = 0L
            }
        })
    }

    private fun startProgressTimer() {
        scope.launch {
            while (true) {
                controller?.let {
                    if (it.isPlaying) {
                        _currentPosition.value = it.currentPosition
                        val now = System.currentTimeMillis()
                        if (now - lastSyncTime > SYNC_INTERVAL_MS) {
                            syncProgress(it)
                            lastSyncTime = now
                        }
                    }
                }
                delay(1000)
            }
        }
    }

    private suspend fun syncProgress(player: Player) {
        val book = _currentBook.value ?: return
        val userId = authRepository.getUserId() ?: return
        val currentMediaItem = player.currentMediaItem ?: return
        val chapterId = currentMediaItem.mediaId.toIntOrNull() ?: return
        val positionSec = (player.currentPosition / 1000).toInt()

        bookRepository.updateProgress(
            userId = userId,
            progress = ProgressDto(
                bookId = book.id,
                chapterId = chapterId,
                positionSec = positionSec
            )
        )
    }

    fun playBook(book: BookDetailDto, chapterIndex: Int? = null, positionMs: Long? = null) {
        val c = controller ?: return

        _currentBook.value = book

        val mediaItems = book.chapters.orEmpty().map { chapter ->
            val metadata = MediaMetadata.Builder()
                .setTitle(chapter.title)
                .setArtist(book.author)
                .setAlbumTitle(book.title)
                .build()

            MediaItem.Builder()
                .setMediaId(chapter.id.toString())
                .setUri("${settingsManager.getServerUri()}chapters/${chapter.id}/audio")
                .setMediaMetadata(metadata)
                .build()
        }

        val targetChapterIndex = chapterIndex ?: book.chapters?.indexOfFirst { it.id == book.resumeChapterId }?.coerceAtLeast(0) ?: 0
        val targetPositionMs = positionMs ?: (book.resumePositionSec * 1000L)

        _currentChapterIndex.value = targetChapterIndex
        c.setMediaItems(mediaItems, targetChapterIndex, targetPositionMs)
        c.prepare()
        c.play()
    }

    fun togglePlayPause() {
        val c = controller ?: return
        if (c.isPlaying) c.pause() else c.play()
    }

    fun seekTo(positionMs: Long) {
        controller?.seekTo(positionMs)
    }

    fun skipToPreviousChapter() {
        controller?.takeIf { it.hasPreviousMediaItem() }?.seekToPreviousMediaItem()
    }

    fun skipToNextChapter() {
        controller?.takeIf { it.hasNextMediaItem() }?.seekToNextMediaItem()
    }

    fun startSleepTimer(minutes: Int) {
        sleepTimerJob?.cancel()
        val durationMs = minutes * 60_000L
        val endTime = System.currentTimeMillis() + durationMs
        _sleepTimerEndTime.value = endTime
        _sleepTimerRemainingMillis.value = durationMs
        sleepTimerJob = scope.launch {
            while (true) {
                val remainingMs = (endTime - System.currentTimeMillis()).coerceAtLeast(0L)
                _sleepTimerRemainingMillis.value = remainingMs
                if (remainingMs == 0L) {
                    controller?.pause()
                    _sleepTimerEndTime.value = null
                    _sleepTimerRemainingMillis.value = null
                    break
                }
                delay(minOf(1_000L, remainingMs))
            }
        }
    }

    fun cancelSleepTimer() {
        sleepTimerJob?.cancel()
        sleepTimerJob = null
        _sleepTimerEndTime.value = null
        _sleepTimerRemainingMillis.value = null
    }
}
