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

    fun togglePlayPause() {
        playbackManager.togglePlayPause()
    }

    fun seekTo(positionMs: Long) {
        playbackManager.seekTo(positionMs)
    }
}
