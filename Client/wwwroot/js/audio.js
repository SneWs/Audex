window.getDuration = function (id) {
    const el = document.getElementById(id);
    const d = el ? el.duration : 0;
    return isFinite(d) ? d : 0;
};

window.getCurrentTime = function (id) {
    const el = document.getElementById(id);
    return el ? el.currentTime : 0;
};

window.loadAndPlay = function (id) {
    const el = document.getElementById(id);
    if (!el) return;
    el.load();
    const p = el.play();
    if (p && typeof p.catch === "function") {
        p.catch(function () { /* autoplay may require a user gesture; ignore */ });
    }
};

window.loadPlaySeek = function (id, seconds) {
    const el = document.getElementById(id);
    if (!el) return;
    if (seconds > 0) {
        const doSeek = function () {
            try { el.currentTime = seconds; } catch (e) { /* ignore */ }
            el.removeEventListener("loadedmetadata", doSeek);
        };
        el.addEventListener("loadedmetadata", doSeek);
    }
    el.load();
    const p = el.play();
    if (p && typeof p.catch === "function") {
        p.catch(function () { /* autoplay may require a user gesture; ignore */ });
    }
};

// ── Media Session API ──────────────────────────────────────────────

window.setMediaSessionMetadata = function (title, chapter, bookTitle) {
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

window.setMediaSessionHandlers = function (dotNetRef) {
    if (!('mediaSession' in navigator)) return;

    function getPlayer() { return document.getElementById('globalPlayer'); }

    // Keep playbackState in sync — use event delegation since the element may not exist yet
    document.addEventListener('play', function (e) {
        if (e.target.id === 'globalPlayer') navigator.mediaSession.playbackState = 'playing';
    }, true);
    document.addEventListener('pause', function (e) {
        if (e.target.id === 'globalPlayer') navigator.mediaSession.playbackState = 'paused';
    }, true);

    navigator.mediaSession.setActionHandler('play', function () {
        var el = getPlayer();
        if (el) {
            el.play();
            navigator.mediaSession.playbackState = 'playing';
        }
    });
    navigator.mediaSession.setActionHandler('pause', function () {
        var el = getPlayer();
        if (el) {
            el.pause();
            navigator.mediaSession.playbackState = 'paused';
        }
    });
    navigator.mediaSession.setActionHandler('previoustrack', function () {
        dotNetRef.invokeMethodAsync('MediaPrevious');
    });
    navigator.mediaSession.setActionHandler('nexttrack', function () {
        dotNetRef.invokeMethodAsync('MediaNext');
    });
    navigator.mediaSession.setActionHandler('seekbackward', function (details) {
        var el = getPlayer();
        if (el) el.currentTime = Math.max(el.currentTime - (details.seekOffset || 10), 0);
    });
    navigator.mediaSession.setActionHandler('seekforward', function (details) {
        var el = getPlayer();
        if (el) el.currentTime = Math.min(el.currentTime + (details.seekOffset || 10), el.duration || 0);
    });
};

window.clearMediaSession = function () {
    if (!('mediaSession' in navigator)) return;
    navigator.mediaSession.metadata = null;
    navigator.mediaSession.setActionHandler('play', null);
    navigator.mediaSession.setActionHandler('pause', null);
    navigator.mediaSession.setActionHandler('previoustrack', null);
    navigator.mediaSession.setActionHandler('nexttrack', null);
    navigator.mediaSession.setActionHandler('seekbackward', null);
    navigator.mediaSession.setActionHandler('seekforward', null);
};
