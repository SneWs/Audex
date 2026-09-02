import AVFoundation
import Foundation
import MediaPlayer
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
final class PlaybackController {
    var currentBook: BookDetail?
    var isPlaying = false
    var currentPosition: TimeInterval = 0
    var currentDuration: TimeInterval = 0
    var currentChapterIndex = 0
    var isNowPlayingPresented = false
    var sleepEndsAt: Date?
    var sleepRemaining: TimeInterval?

    var rate: Float {
        didSet {
            if isPlaying { player.rate = rate }
            session.settings.playbackRate = rate
            updateNowPlaying()
        }
    }

    var chapters: [Chapter] { currentBook?.sortedChapters ?? [] }
    var currentChapter: Chapter? {
        chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex] : nil
    }
    var hasMultipleChapters: Bool { chapters.count > 1 }

    static let speedOptions: [Float] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

    private let player = AVPlayer()
    private let session: AppSession
    private let downloads: DownloadManager
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObserver: NSKeyValueObservation?
    private var lastSync = Date.distantPast
    private var sleepTask: Task<Void, Never>?
    private var coverArtwork: MPMediaItemArtwork?
    private var commandsConfigured = false
    #if os(iOS) || os(tvOS) || os(visionOS)
    private let nowPlayingSession: MPNowPlayingSession
    #endif

    init(session: AppSession, downloads: DownloadManager) {
        self.session = session
        self.downloads = downloads
        self.rate = session.settings.playbackRate
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        #if os(iOS) || os(tvOS) || os(visionOS)
        let nowPlaying = MPNowPlayingSession(players: [player])
        nowPlaying.automaticallyPublishesNowPlayingInfo = true
        nowPlayingSession = nowPlaying
        #endif
        configureObservers()
        configureRemoteCommands()
    }

    func play(bookID: Int, chapterIndex: Int? = nil) async {
        if currentBook?.id == bookID, chapterIndex == nil {
            togglePlayPause()
            return
        }
        do {
            let detail = try await session.api.book(id: bookID)
            play(detail: detail, chapterIndex: chapterIndex)
        } catch {
            // Detail load failed; keep current playback.
        }
    }

    func play(detail: BookDetail, chapterIndex: Int? = nil, position: TimeInterval? = nil) {
        currentBook = detail
        coverArtwork = nil
        Task { await loadArtwork() }

        let startIndex: Int
        let startPosition: TimeInterval
        if let chapterIndex, chapters.indices.contains(chapterIndex) {
            startIndex = chapterIndex
            startPosition = position ?? 0
        } else if !detail.isCompleted,
                  let resumeID = detail.resumeChapterId,
                  let resumeIndex = chapters.firstIndex(where: { $0.id == resumeID }) {
            startIndex = resumeIndex
            startPosition = position ?? TimeInterval(detail.resumePositionSec)
        } else {
            startIndex = 0
            startPosition = 0
        }
        loadChapter(startIndex, position: startPosition, shouldPlay: true)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard player.currentItem != nil else { return }
        activateSession()
        player.play()
        player.rate = rate
        isPlaying = true
        updateNowPlaying()
        becomeNowPlayingApp()
    }

    func pause() {
        player.pause()
        isPlaying = false
        updateNowPlaying()
        Task { await syncProgress() }
    }

    func seek(to time: TimeInterval) {
        let clamped = max(0, min(time, currentDuration > 0 ? currentDuration : time))
        currentPosition = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        updateNowPlaying()
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentPosition + seconds)
    }

    func skipToNextChapter() {
        guard currentChapterIndex + 1 < chapters.count else { return }
        loadChapter(currentChapterIndex + 1, position: 0, shouldPlay: true)
        Task { await syncProgress() }
    }

    func skipToPreviousChapter() {
        if currentPosition > 3 {
            seek(to: 0)
            return
        }
        guard currentChapterIndex > 0 else {
            seek(to: 0)
            return
        }
        loadChapter(currentChapterIndex - 1, position: 0, shouldPlay: true)
        Task { await syncProgress() }
    }

    func startSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        let duration = TimeInterval(minutes * 60)
        let end = Date().addingTimeInterval(duration)
        sleepEndsAt = end
        sleepRemaining = duration
        sleepTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = max(0, end.timeIntervalSinceNow)
                self.sleepRemaining = remaining
                if remaining == 0 {
                    self.pause()
                    self.clearSleepTimer()
                    return
                }
                try? await Task.sleep(for: .milliseconds(min(1000, remaining * 1000)))
            }
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        clearSleepTimer()
    }

    private func clearSleepTimer() {
        sleepTask = nil
        sleepEndsAt = nil
        sleepRemaining = nil
    }

    private func loadChapter(_ index: Int, position: TimeInterval, shouldPlay: Bool) {
        guard let book = currentBook, chapters.indices.contains(index) else { return }
        currentChapterIndex = index
        let chapter = chapters[index]
        currentDuration = TimeInterval(chapter.durationSec)
        currentPosition = position

        let item = playerItem(for: book, chapter: chapter)
        player.replaceCurrentItem(with: item)
        applyItemMetadata(item, book: book, chapter: chapter)
        activateSession()

        let seekTime = CMTime(seconds: max(0, position), preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            if shouldPlay {
                self.player.play()
                self.player.rate = self.rate
                self.isPlaying = true
            }
            self.updateNowPlaying()
            self.becomeNowPlayingApp()
        }
    }

    private func playerItem(for book: BookDetail, chapter: Chapter) -> AVPlayerItem {
        if let local = downloads.localFile(for: book, chapter: chapter) {
            return AVPlayerItem(url: local)
        }
        let remote = session.api.audioURL(chapterID: chapter.id) ?? URL(string: "about:blank")!
        var headers = ["User-Agent": "Audex-iOS"]
        if let token = session.api.token {
            headers["Authorization"] = "Bearer \(token)"
        }
        let asset = AVURLAsset(url: remote, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        return AVPlayerItem(asset: asset)
    }

    private func configureObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                self?.handleTime(time)
            }
        }

        statusObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor [weak self] in
                self?.isPlaying = playing
                self?.updateNowPlaying()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let endedItem = notification.object as? AVPlayerItem
            MainActor.assumeIsolated {
                self?.handleItemEnded(endedItem)
            }
        }
    }

    private func handleTime(_ time: CMTime) {
        guard time.isNumeric else { return }
        currentPosition = time.seconds
        if let duration = player.currentItem?.duration, duration.isNumeric, duration.seconds > 0 {
            currentDuration = duration.seconds
        }
        if isPlaying, Date().timeIntervalSince(lastSync) > 10 {
            lastSync = Date()
            Task { await syncProgress() }
        }
        updateNowPlayingElapsed()
    }

    private func handleItemEnded(_ item: AVPlayerItem?) {
        guard let item, item == player.currentItem else { return }
        if currentChapterIndex + 1 < chapters.count {
            loadChapter(currentChapterIndex + 1, position: 0, shouldPlay: true)
            Task { await syncProgress() }
        } else {
            isPlaying = false
            player.pause()
            Task { await syncProgress() }
            updateNowPlaying()
        }
    }

    private func syncProgress() async {
        guard let book = currentBook,
              let chapter = currentChapter,
              let userID = session.userID else { return }
        let update = ProgressUpdate(
            bookId: book.id,
            chapterId: chapter.id,
            positionSec: Int(currentPosition.rounded(.towardZero))
        )
        try? await session.api.updateProgress(userID: userID, update: update)
    }

    private func activateSession() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [])
        try? audio.setActive(true)
        #endif
        #if os(iOS)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        #endif
    }

    private func becomeNowPlayingApp() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        nowPlayingSession.becomeActiveIfPossible { _ in }
        #endif
    }

    private func applyItemMetadata(_ item: AVPlayerItem, book: BookDetail, chapter: Chapter) {
        #if os(iOS) || os(tvOS) || os(visionOS)
        item.nowPlayingInfo = nowPlayingDictionary(book: book, chapter: chapter)
        #endif
    }

    private func configureRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        #if os(iOS) || os(tvOS) || os(visionOS)
        let center = nowPlayingSession.remoteCommandCenter
        #else
        let center = MPRemoteCommandCenter.shared()
        #endif
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]
        center.changePlaybackPositionCommand.isEnabled = true

        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToNextChapter() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skipToPreviousChapter() }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] event in
            let seconds = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.skip(by: seconds) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] event in
            let seconds = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            Task { @MainActor in self?.skip(by: -seconds) }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func loadArtwork() async {
        guard let book = currentBook, book.hasCover, let url = session.api.coverURL(for: book.id) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            #if os(macOS)
            guard let image = NSImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            #else
            guard let image = UIImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            #endif
            coverArtwork = artwork
            updateNowPlaying()
        } catch {
            return
        }
    }

    private func nowPlayingDictionary(book: BookDetail? = nil, chapter: Chapter? = nil) -> [String: Any] {
        let book = book ?? currentBook
        let chapter = chapter ?? currentChapter
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapter?.title ?? book?.displayTitle ?? "Audex",
            MPMediaItemPropertyAlbumTitle: book?.displayTitle ?? "",
            MPMediaItemPropertyArtist: book?.artistLine ?? "",
            MPMediaItemPropertyPlaybackDuration: currentDuration > 0 ? currentDuration : TimeInterval(chapter?.durationSec ?? 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if let coverArtwork {
            info[MPMediaItemPropertyArtwork] = coverArtwork
        }
        return info
    }

    private func updateNowPlaying() {
        let info = nowPlayingDictionary()
        #if os(iOS) || os(tvOS) || os(visionOS)
        player.currentItem?.nowPlayingInfo = info
        nowPlayingSession.nowPlayingInfoCenter.nowPlayingInfo = info
        nowPlayingSession.nowPlayingInfoCenter.playbackState = isPlaying ? .playing : .paused
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    private func updateNowPlayingElapsed() {
        updateNowPlaying()
    }
}
