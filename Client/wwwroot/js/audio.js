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
