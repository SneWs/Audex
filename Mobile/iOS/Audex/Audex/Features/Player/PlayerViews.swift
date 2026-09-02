import SwiftUI

struct MiniPlayerBar: View {
    @Environment(PlaybackController.self) private var playback
    #if os(iOS)
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    #endif
    @State private var showSleepTimer = false

    private var isInlineAccessory: Bool {
        #if os(iOS)
        placement == .inline
        #else
        false
        #endif
    }

    var body: some View {
        if let book = playback.currentBook {
            Group {
                if isInlineAccessory {
                    compactBar(book)
                } else {
                    expandedBar(book)
                }
            }
            .sheet(isPresented: $showSleepTimer) {
                SleepTimerSheet()
                    #if os(iOS)
                    .presentationDetents([.medium])
                    #endif
            }
            #if os(macOS)
            .frame(maxWidth: .infinity)
            .background(AudexColor.surface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AudexColor.primary.opacity(0.35))
                    .frame(height: 1)
            }
            #endif
        }
    }

    private func compactBar(_ book: BookDetail) -> some View {
        HStack(spacing: 10) {
            CoverImage(bookID: book.id, hasCover: book.hasCover, cornerRadius: 4)
                .frame(width: 28, height: 28)
            Text(book.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            playback.isNowPlayingPresented = true
        }
    }

    private func expandedBar(_ book: BookDetail) -> some View {
        VStack(spacing: 0) {
            ProgressView(value: playback.currentDuration > 0 ? playback.currentPosition / playback.currentDuration : 0)
                .tint(AudexColor.primary)
            HStack(spacing: 12) {
                Button {
                    playback.isNowPlayingPresented = true
                } label: {
                    HStack(spacing: 12) {
                        CoverImage(bookID: book.id, hasCover: book.hasCover, cornerRadius: 6)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.displayTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(book.author) · \(DurationFormat.clock(playback.currentPosition))")
                                .font(.caption)
                                .foregroundStyle(AudexColor.onSurfaceVariant)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(.plain)

                if playback.hasMultipleChapters {
                    Button {
                        playback.skipToPreviousChapter()
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(playback.currentChapterIndex == 0)
                    Button {
                        playback.skipToNextChapter()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .disabled(playback.currentChapterIndex >= playback.chapters.count - 1)
                }

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                }

                Button {
                    showSleepTimer = true
                } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "timer")
                        if let remaining = playback.sleepRemaining {
                            Text(DurationFormat.short(remaining))
                                .font(.caption2)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

struct NowPlayingView: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showSleepTimer = false
    @State private var showChapters = false
    @State private var isEditingSeek = false
    @State private var seekValue: Double = 0

    var body: some View {
        NavigationStack {
            ZStack {
                background
                VStack(spacing: 20) {
                    if let book = playback.currentBook {
                        Text(book.displayTitle)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text(book.artistLine)
                            .font(.headline)
                            .foregroundStyle(AudexColor.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                        if let chapter = playback.currentChapter {
                            Text("\(chapter.title) (\(playback.currentChapterIndex + 1)/\(playback.chapters.count))")
                                .font(.subheadline)
                                .foregroundStyle(AudexColor.onSurfaceVariant)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }

                        if verticalSizeClass != .compact {
                            CoverImage(bookID: book.id, hasCover: book.hasCover, cornerRadius: 24)
                                .frame(width: 220, height: 220)
                                .shadow(radius: 16, y: 8)
                                .padding(.vertical, 8)
                        }

                        slider
                        controls
                    } else {
                        ContentUnavailableView("No Book Playing", systemImage: "headphones")
                    }
                }
                .padding(24)
            }
            .navigationTitle("Now Playing")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "chevron.down") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if playback.hasMultipleChapters {
                        Button("Chapters", systemImage: "list.bullet") { showChapters = true }
                    }
                }
            }
            .sheet(isPresented: $showSleepTimer) {
                SleepTimerSheet()
                    #if os(iOS)
                    .presentationDetents([.medium])
                    #endif
            }
            .sheet(isPresented: $showChapters) {
                chapterList
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    #endif
            }
        }
    }

    private var background: some View {
        Group {
            if let book = playback.currentBook, book.hasCover {
                CoverImage(bookID: book.id, hasCover: true, cornerRadius: 0)
                    .blur(radius: 40)
                    .overlay(AudexColor.background.opacity(0.84))
                    .ignoresSafeArea()
            } else {
                AudexColor.background.ignoresSafeArea()
            }
        }
    }

    private var slider: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isEditingSeek ? seekValue : playback.currentPosition },
                    set: { seekValue = $0 }
                ),
                in: 0...max(playback.currentDuration, 1),
                onEditingChanged: { editing in
                    isEditingSeek = editing
                    if !editing {
                        playback.seek(to: seekValue)
                    }
                }
            )
            HStack {
                Text(DurationFormat.clock(isEditingSeek ? seekValue : playback.currentPosition))
                Spacer()
                Text(DurationFormat.clock(playback.currentDuration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(AudexColor.onSurfaceVariant)
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            HStack(spacing: 18) {
                if playback.hasMultipleChapters {
                    Button {
                        playback.skipToPreviousChapter()
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.title)
                    }
                    .disabled(playback.currentChapterIndex == 0)
                }

                Button {
                    playback.skip(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }

                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }

                Button {
                    playback.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }

                if playback.hasMultipleChapters {
                    Button {
                        playback.skipToNextChapter()
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.title)
                    }
                    .disabled(playback.currentChapterIndex >= playback.chapters.count - 1)
                }
            }

            HStack {
                Menu {
                    ForEach(PlaybackController.speedOptions, id: \.self) { speed in
                        Button {
                            playback.rate = speed
                        } label: {
                            if playback.rate == speed {
                                Label(speedLabel(speed), systemImage: "checkmark")
                            } else {
                                Text(speedLabel(speed))
                            }
                        }
                    }
                } label: {
                    Text(speedLabel(playback.rate))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AudexColor.primary.opacity(0.15), in: Capsule())
                }

                Spacer()

                Button {
                    showSleepTimer = true
                } label: {
                    HStack {
                        Image(systemName: "timer")
                        if let remaining = playback.sleepRemaining {
                            Text(DurationFormat.clock(remaining))
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
        .foregroundStyle(AudexColor.onSurface)
    }

    private var chapterList: some View {
        NavigationStack {
            List(Array(playback.chapters.enumerated()), id: \.element.id) { index, chapter in
                Button {
                    if let book = playback.currentBook {
                        playback.play(detail: book, chapterIndex: index, position: 0)
                    }
                    showChapters = false
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(chapter.title)
                            Text(DurationFormat.clock(chapter.durationSec))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if index == playback.currentChapterIndex {
                            Image(systemName: "waveform")
                                .foregroundStyle(AudexColor.primary)
                        }
                    }
                }
            }
            .navigationTitle("Chapters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showChapters = false }
                }
            }
        }
    }

    private func speedLabel(_ speed: Float) -> String {
        speed == 1 ? "1x" : String(format: "%gx", speed)
    }
}

struct SleepTimerSheet: View {
    @Environment(PlaybackController.self) private var playback
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach([15, 30, 45, 60], id: \.self) { minutes in
                    Button("\(minutes) minutes") {
                        playback.startSleepTimer(minutes: minutes)
                        dismiss()
                    }
                }
                if playback.sleepEndsAt != nil {
                    Button("Cancel timer", role: .destructive) {
                        playback.cancelSleepTimer()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Sleep timer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }
}
