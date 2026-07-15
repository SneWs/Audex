window.getDuration = function (id) {
    var el = document.getElementById(id);
    var d = el ? el.duration : 0;
    return isFinite(d) ? d : 0;
};

window.getCurrentTime = function (id) {
    var el = document.getElementById(id);
    return el ? el.currentTime : 0;
};

window.pauseAudio = function (id) {
    var el = document.getElementById(id);
    if (!el) return;
    el.pause();
};

// ── Audio player management ────────────────────────────────────────

var _audioRef = null;       // current <audio> element reference
var _dotNetRef = null;      // Blazor DotNetObjectReference
var _lastSavedTime = 0;     // timestamp of last progress save

function _updatePositionState() {
    if (!('mediaSession' in navigator) || !_audioRef) return;
    if (!isFinite(_audioRef.duration) || _audioRef.duration <= 0) return;
    try {
        navigator.mediaSession.setPositionState({
            duration: _audioRef.duration,
            playbackRate: _audioRef.playbackRate || 1,
            position: _audioRef.currentTime
        });
    } catch (e) { /* ignore – some browsers reject edge-case values */ }
}

window.initAudioPlayer = function (dotNetRef) {
    _dotNetRef = dotNetRef;
    _setupMediaSessionHandlers();
};

window.loadPlaySeek = function (id, src, seconds) {
    var el = document.getElementById(id);
    if (!el) return;
    _audioRef = el;

    // Set source via JS so Safari doesn't race with Blazor's src binding
    el.src = src;

    // Wire native DOM events directly (not through Blazor)
    el.onpause = function () {
        if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'paused';
        _updatePositionState();
        if (_dotNetRef) _dotNetRef.invokeMethodAsync('OnJsPause');
    };
    el.onplay = function () {
        if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
        _updatePositionState();
        if (_dotNetRef) _dotNetRef.invokeMethodAsync('OnJsPlay');
    };
    el.onended = function () {
        if (_dotNetRef) _dotNetRef.invokeMethodAsync('OnJsEnded');
    };
    el.ontimeupdate = function () {
        _updatePositionState();
        var now = Date.now();
        if (now - _lastSavedTime > 10000) {
            _lastSavedTime = now;
            if (_dotNetRef) _dotNetRef.invokeMethodAsync('OnJsTimeUpdate');
        }
    };
    el.onloadedmetadata = function () {
        _updatePositionState();
    };

    if (seconds > 0) {
        var doSeek = function () {
            try { el.currentTime = seconds; } catch (e) { /* ignore */ }
            el.removeEventListener('loadedmetadata', doSeek);
        };
        el.addEventListener('loadedmetadata', doSeek);
    }

    el.load();
    var p = el.play();
    if (p && typeof p.then === 'function') {
        p.catch(function () { /* autoplay blocked; user gesture required */ });
    }
};

window.updateMediaSession = function (title, chapter, bookTitle) {
    if (!('mediaSession' in navigator)) return;

    navigator.mediaSession.metadata = new MediaMetadata({
        title: chapter || title,
        artist: bookTitle || '',
        album: 'Audex',
        artwork: [
            { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
            { src: '/icon-512.png', sizes: '512x512', type: 'image/png' }
        ]
    });
};

window.clearMediaSession = function () {
    if (!('mediaSession' in navigator)) return;
    navigator.mediaSession.metadata = null;
    navigator.mediaSession.playbackState = 'none';
};

window.disposeAudioPlayer = function () {
    if (_audioRef) {
        _audioRef.onpause = null;
        _audioRef.onplay = null;
        _audioRef.onended = null;
        _audioRef.ontimeupdate = null;
        _audioRef.onloadedmetadata = null;
        _audioRef = null;
    }
    _dotNetRef = null;
    window.clearMediaSession();
};

// ── Media Session handlers (registered once) ───────────────────────

function _setupMediaSessionHandlers() {
    if (!('mediaSession' in navigator)) return;

    navigator.mediaSession.setActionHandler('play', function () {
        if (_audioRef) _audioRef.play();
    });

    navigator.mediaSession.setActionHandler('pause', function () {
        if (_audioRef) _audioRef.pause();
    });

    navigator.mediaSession.setActionHandler('stop', function () {
        if (_audioRef) {
            _audioRef.pause();
            _audioRef.currentTime = 0;
        }
    });

    navigator.mediaSession.setActionHandler('previoustrack', function () {
        if (_dotNetRef) _dotNetRef.invokeMethodAsync('MediaPrevious');
    });

    navigator.mediaSession.setActionHandler('nexttrack', function () {
        if (_dotNetRef) _dotNetRef.invokeMethodAsync('MediaNext');
    });

    navigator.mediaSession.setActionHandler('seekbackward', function (details) {
        if (_audioRef) {
            _audioRef.currentTime = Math.max(_audioRef.currentTime - (details.seekOffset || 10), 0);
            _updatePositionState();
        }
    });

    navigator.mediaSession.setActionHandler('seekforward', function (details) {
        if (_audioRef) {
            _audioRef.currentTime = Math.min(_audioRef.currentTime + (details.seekOffset || 10), _audioRef.duration || 0);
            _updatePositionState();
        }
    });

    navigator.mediaSession.setActionHandler('seekto', function (details) {
        if (_audioRef) {
            _audioRef.currentTime = details.seekTime;
            _updatePositionState();
        }
    });
}
