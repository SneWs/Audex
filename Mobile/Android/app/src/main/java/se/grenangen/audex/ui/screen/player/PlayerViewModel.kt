package se.grenangen.audex.ui.screen.player

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import se.grenangen.audex.playback.PlaybackManager
import javax.inject.Inject

@HiltViewModel
class PlayerViewModel @Inject constructor(
    private val playbackManager: PlaybackManager
) : ViewModel() {

    val currentBook = playbackManager.currentBook
    val isPlaying = playbackManager.isPlaying
    val currentPosition = playbackManager.currentPosition
    val currentDuration = playbackManager.currentDuration
    val currentChapterIndex = playbackManager.currentChapterIndex
    val sleepTimerEndTime = playbackManager.sleepTimerEndTime
    val sleepTimerRemainingMillis = playbackManager.sleepTimerRemainingMillis

    fun togglePlayPause() {
        playbackManager.togglePlayPause()
    }

    fun seekTo(positionMs: Long) {
        playbackManager.seekTo(positionMs)
    }

    fun skipToPreviousChapter() {
        playbackManager.skipToPreviousChapter()
    }

    fun skipToNextChapter() {
        playbackManager.skipToNextChapter()
    }

    fun startSleepTimer(minutes: Int) {
        playbackManager.startSleepTimer(minutes)
    }

    fun cancelSleepTimer() {
        playbackManager.cancelSleepTimer()
    }
}
