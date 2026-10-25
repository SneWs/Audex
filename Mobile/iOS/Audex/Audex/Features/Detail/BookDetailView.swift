import SwiftUI

struct BookDetailView: View {
    let bookID: Int
    var initialBook: Book? = nil

    @Environment(AppSession.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadManager.self) private var downloads

    @State private var book: BookDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && book == nil {
                ProgressView("Loading audiobook…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let book {
                detailContent(book)
            } else {
                ContentUnavailableView {
                    Label("Couldn't Load Audiobook", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage ?? "Unable to load book details.")
                } actions: {
                    Button("Retry") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(book?.displayTitle ?? initialBook?.displayTitle ?? "Audiobook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let book {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await toggleFavorite(book) }
                    } label: {
                        Image(systemName: book.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(book.isFavorite ? Color.red : .primary)
                    }
                    .accessibilityLabel(book.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }
            }
        }
        .task {
            await load()
        }
    }

    @ViewBuilder
    private func detailContent(_ book: BookDetail) -> some View {
        let isThisPlaying = playback.currentBook?.id == book.id && playback.isPlaying
        let isStarted = book.isStarted && !book.isCompleted
        let downloadState = downloads.state(for: book)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 18) {
                    CoverImage(bookID: book.id, hasCover: book.hasCover, cornerRadius: 16)
                        .frame(width: 132, height: 132)
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.displayTitle)
                            .font(.title3.weight(.bold))
                            .fixedSize(horizontal: false, vertical: true)

                        if let subtitle = book.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(book.author)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AudexColor.coral)

                        if let readBy = book.readBy, !readBy.isEmpty {
                            Text("Narrated by \(readBy)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            MetaChip(icon: "clock", text: DurationFormat.short(book.durationSec))
                            MetaChip(icon: "list.number", text: "\(book.chapterCount) ch")
                            if let year = book.year {
                                MetaChip(icon: "calendar", text: String(year))
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                if isStarted {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(Int((book.progressFraction * 100).rounded()))% complete")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AudexColor.coral)
                            Spacer()
                            Text("\(DurationFormat.short(book.remainingSec)) remaining")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: book.progressFraction)
                            .tint(AudexColor.coral)

                        Button {
                            Task { await completeBook(book) }
                        } label: {
                            Label("Mark as complete", systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if book.isCompleted {
                    Label("Completed", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AudexColor.amber)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                downloadBanner(for: book, state: downloadState)

                if let genres = book.genres, !genres.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            GenreChip(text: genre)
                        }
                    }
                }

                if let description = book.description {
                    let clean = HTMLText.plain(description)
                    if !clean.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About")
                                .font(.headline)
                            Text(clean)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Chapters (\(book.sortedChapters.count))")
                        .font(.headline)

                    VStack(spacing: 0) {
                        ForEach(Array(book.sortedChapters.enumerated()), id: \.element.id) { index, chapter in
                            let isCurrentChapter = playback.currentBook?.id == book.id && playback.currentChapterIndex == index
                            Button {
                                playback.play(detail: book, chapterIndex: index, position: 0)
                                playback.isPresentingNowPlaying = true
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)")
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(isCurrentChapter ? AudexColor.coral : .secondary)
                                        .frame(width: 26, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title)
                                            .font(.subheadline.weight(isCurrentChapter ? .semibold : .regular))
                                            .foregroundStyle(isCurrentChapter ? AudexColor.coral : .primary)
                                            .multilineTextAlignment(.leading)
                                        Text(DurationFormat.clock(chapter.durationSec))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: isCurrentChapter && isThisPlaying ? "waveform" : "play.circle")
                                        .foregroundStyle(isCurrentChapter ? AudexColor.coral : .secondary)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < book.sortedChapters.count - 1 {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button {
                    Task { await downloads.download(book: book) }
                } label: {
                    Image(systemName: downloadIcon(for: downloadState))
                        .font(.headline)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .disabled(isDownloading(downloadState))
                .accessibilityLabel("Download for offline playback")

                Button {
                    if playback.currentBook?.id == book.id {
                        playback.togglePlayPause()
                    } else {
                        playback.play(detail: book)
                    }
                    playback.isPresentingNowPlaying = true
                } label: {
                    Label(
                        isThisPlaying ? "Pause" : (book.isStarted && !book.isCompleted ? "Continue Listening" : "Play Audiobook"),
                        systemImage: isThisPlaying ? "pause.fill" : "play.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(AudexColor.coral)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func downloadBanner(for book: BookDetail, state: DownloadState) -> some View {
        switch state {
        case .idle:
            EmptyView()
        case .downloading(let done, let total):
            HStack(spacing: 10) {
                ProgressView()
                Text("Downloading \(done)/\(total) chapters…")
                    .font(.footnote.weight(.medium))
                Spacer()
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .completed:
            HStack {
                Label("Available offline", systemImage: "arrow.down.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AudexColor.coral)
                Spacer()
                Button("Remove", role: .destructive) {
                    downloads.removeDownloads(for: book)
                }
                .font(.caption.weight(.semibold))
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func isDownloading(_ state: DownloadState) -> Bool {
        if case .downloading = state { return true }
        return false
    }

    private func downloadIcon(for state: DownloadState) -> String {
        switch state {
        case .completed: return "checkmark.circle.fill"
        case .downloading: return "arrow.down.circle.dotted"
        default: return "arrow.down.to.line"
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            book = try await session.api.book(id: bookID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleFavorite(_ current: BookDetail) async {
        let next = !current.isFavorite
        book?.isFavorite = next
        library.applyFavorite(bookID: current.id, isFavorite: next)
        do {
            try await session.api.setFavorite(bookID: current.id, isFavorite: next)
        } catch {
            book?.isFavorite = !next
            library.applyFavorite(bookID: current.id, isFavorite: !next)
        }
    }

    private func completeBook(_ current: BookDetail) async {
        book?.isCompleted = true
        book?.progressSec = current.durationSec
        library.applyCompleted(bookID: current.id)
        do {
            try await session.api.completeBook(id: current.id)
        } catch {
            await load()
        }
    }
}
