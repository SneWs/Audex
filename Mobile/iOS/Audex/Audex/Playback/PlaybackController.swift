import AVFoundation
import Foundation
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class PlaybackController {
    static let speedOptions: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private let session: AppSession
    private let downloads: DownloadManager
    private let library: LibraryStore

    private let player = AVPlayer()
    #if os(iOS)
    private var nowPlayingSession: MPNowPlayingSession?
    #endif
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var sleepTimerTask: Task<Void, Never>?
    private var lastSyncDate: Date = .distantPast
    private var artworkImage: MPMediaItemArtwork?
    private var artworkBookID: Int?

    var currentBook: BookDetail?
    var currentChapterIndex: Int = 0
    var isPlaying: Bool = false
    var currentPosition: Double = 0
    var currentDuration: Double = 0
    var rate: Float = 1.0 {
        didSet {
            session.settings.playbackRate = rate
            if isPlaying {
                player.rate = rate
            }
            publishNowPlaying()
        }
    }
    var sleepEndsAt: Date?
    var sleepTimerRemainingSec: Int?
    var isPresentingNowPlaying: Bool = false

    var isNowPlayingPresented: Bool {
        get { isPresentingNowPlaying }
        set { isPresentingNowPlaying = newValue }
    }

    var sleepRemaining: TimeInterval? {
        guard let remaining = sleepTimerRemainingSec else { return nil }
        return TimeInterval(remaining)
    }

    var chapters: [Chapter] {
        currentBook?.sortedChapters ?? []
    }

    init(session: AppSession, downloads: DownloadManager, library: LibraryStore) {
        self.session = session
        self.downloads = downloads
        self.library = library
        self.rate = session.settings.playbackRate
        configureAudioSession()
        installTimeObserver()
    }

    var currentChapter: Chapter? {
        let list = chapters
        guard list.indices.contains(currentChapterIndex) else {
            return nil
        }
        return list[currentChapterIndex]
    }

    var hasMultipleChapters: Bool {
        chapters.count > 1
    }

    var canSkipPreviousChapter: Bool {
        currentChapterIndex > 0
    }

    var canSkipNextChapter: Bool {
        currentChapterIndex < chapters.count - 1
    }

    func play(bookID: Int) async {
        if currentBook?.id == bookID {
            togglePlayPause()
            return
        }
        guard let detail = try? await session.api.book(id: bookID) else { return }
        play(detail: detail)
    }

    func play(detail: BookDetail, chapterIndex: Int? = nil, position: Double? = nil) {
        let sorted = detail.sortedChapters
        guard !sorted.isEmpty else { return }

        currentBook = detail
        let resolvedIndex: Int = {
            if let chapterIndex, sorted.indices.contains(chapterIndex) {
                return chapterIndex
            }
            if let resumeID = detail.resumeChapterId,
               let idx = sorted.firstIndex(where: { $0.id == resumeID }) {
                return idx
            }
            return 0
        }()

        let resolvedPosition = position ?? Double(max(0, detail.resumePositionSec))
        loadChapter(index: resolvedIndex, startAt: resolvedPosition, shouldPlay: true)
        Task { await loadArtwork(for: detail.id) }
    }

    private func loadChapter(index: Int, startAt position: Double, shouldPlay: Bool) {
        guard let book = currentBook else { return }
        let sorted = book.sortedChapters
        guard sorted.indices.contains(index) else { return }
        let chapter = sorted[index]

        currentChapterIndex = index
        currentPosition = max(0, position)
        currentDuration = Double(max(1, chapter.durationSec))

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        let item = playerItem(for: book, chapter: chapter)
        item.preferredForwardBufferDuration = 20
        player.replaceCurrentItem(with: item)
        activateSession()

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.handleChapterEnded()
            }
        }

        if position > 0 {
            let seekTime = CMTime(seconds: position, preferredTimescale: 600)
            let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if shouldPlay {
                        self.player.play()
                        self.player.rate = self.rate
                        self.isPlaying = true
                    }
                    self.publishNowPlaying()
                }
            }
        } else {
            if shouldPlay {
                player.play()
                player.rate = rate
                isPlaying = true
            }
            publishNowPlaying()
        }
    }

    private func playerItem(for book: BookDetail, chapter: Chapter) -> AVPlayerItem {
        if let localURL = downloads.existingOfflineFile(for: book, chapter: chapter) {
            return AVPlayerItem(url: localURL)
        }
        let remoteURL = session.api.chapterStreamURL(for: chapter.id, streamPath: chapter.streamUrl)
            ?? URL(fileURLWithPath: "/")
        let headers = session.api.authorizedHeaderValue()
        let asset = AVURLAsset(
            url: remoteURL,
            options: ["AVURLAssetHTTPHeaderFieldsKey": headers]
        )
        return AVPlayerItem(asset: asset)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func resume() {
        guard currentBook != nil else { return }
        activateSession()
        player.play()
        player.rate = rate
        isPlaying = true
        publishNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        publishNowPlaying()
        Task { await syncProgress(force: true) }
    }

    func setPlaybackRate(_ newRate: Float) {
        rate = newRate
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, max(currentDuration, 1)))
        currentPosition = clamped
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.publishNowPlaying()
                await self.syncProgress(force: true)
            }
        }
    }

    func skip(by delta: Double) {
        seek(to: currentPosition + delta)
    }

    func skipBy(seconds delta: Double) {
        seek(to: currentPosition + delta)
    }

    func skipToPreviousChapter() {
        guard canSkipPreviousChapter else {
            seek(to: 0)
            return
        }
        loadChapter(index: currentChapterIndex - 1, startAt: 0, shouldPlay: isPlaying)
    }

    func skipToNextChapter() {
        guard canSkipNextChapter else { return }
        loadChapter(index: currentChapterIndex + 1, startAt: 0, shouldPlay: isPlaying)
    }

    func startSleepTimer(minutes: Int) {
        cancelSleepTimer()
        let totalSeconds = max(1, minutes * 60)
        sleepTimerRemainingSec = totalSeconds
        let endDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
        sleepEndsAt = endDate

        sleepTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let remaining = Int(ceil(endDate.timeIntervalSinceNow))
                if remaining <= 0 {
                    self.sleepTimerRemainingSec = nil
                    self.sleepEndsAt = nil
                    self.pause()
                    break
                }
                self.sleepTimerRemainingSec = remaining
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemainingSec = nil
        sleepEndsAt = nil
    }

    private func handleChapterEnded() async {
        if canSkipNextChapter {
            loadChapter(index: currentChapterIndex + 1, startAt: 0, shouldPlay: true)
            await syncProgress(force: true)
        } else {
            isPlaying = false
            await syncProgress(force: true)
            await library.refresh()
        }
    }

    private func installTimeObserver() {
        let interval = CMTime(seconds: 1.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let sec = time.seconds
                if sec.isFinite && sec >= 0 {
                    self.currentPosition = sec
                }
                if let itemDuration = self.player.currentItem?.duration.seconds,
                   itemDuration.isFinite && itemDuration > 0 {
                    self.currentDuration = itemDuration
                }
                if self.isPlaying {
                    self.publishNowPlaying()
                    await self.syncProgress(force: false)
                }
            }
        }
    }

    func syncProgress(force: Bool) async {
        guard let book = currentBook,
              let chapter = currentChapter,
              let userID = session.userID else { return }

        let now = Date()
        if !force && now.timeIntervalSince(lastSyncDate) < 10 {
            return
        }
        lastSyncDate = now

        let update = ProgressUpdate(
            bookId: book.id,
            chapterId: chapter.id,
            positionSec: Int(currentPosition.rounded())
        )
        try? await session.api.updateProgress(userID: userID, progress: update)
    }

    private func configureAudioSession() {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        } catch {
            // Audio session will still fall back to default playback.
        }
        #endif
    }

    private func activateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        if nowPlayingSession == nil {
            let mpSession = MPNowPlayingSession(players: [player])
            mpSession.automaticallyPublishesNowPlayingInfo = false
            configureRemoteCommands(on: mpSession.remoteCommandCenter)
            nowPlayingSession = mpSession
        }
        nowPlayingSession?.becomeActiveIfPossible()
        #endif
    }

    private func configureRemoteCommands(on center: MPRemoteCommandCenter) {
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.resume() }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.pause() }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipBy(seconds: 30) }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipBy(seconds: -15) }
            return .success
        }

        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipToNextChapter() }
            return .success
        }

        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.skipToPreviousChapter() }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self.seek(to: posEvent.positionTime) }
            return .success
        }
    }

    private func publishNowPlaying() {
        guard let book = currentBook, let chapter = currentChapter else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapter.title,
            MPMediaItemPropertyAlbumTitle: book.displayTitle,
            MPMediaItemPropertyArtist: book.author,
            MPMediaItemPropertyPlaybackDuration: currentDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyChapterNumber: currentChapterIndex + 1,
            MPNowPlayingInfoPropertyChapterCount: book.sortedChapters.count
        ]
        if let artworkImage, artworkBookID == book.id {
            info[MPMediaItemPropertyArtwork] = artworkImage
        }
        #if os(iOS)
        nowPlayingSession?.nowPlayingInfoCenter.nowPlayingInfo = info
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for bookID: Int) async {
        #if canImport(UIKit)
        guard let url = session.api.coverURL(for: bookID) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return }
        artworkBookID = bookID
        artworkImage = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        publishNowPlaying()
        #endif
    }
}
