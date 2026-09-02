import SwiftUI

struct BookDetailView: View {
    let bookID: Int

    @Environment(AppSession.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback
    @Environment(DownloadManager.self) private var downloads

    @State private var book: BookDetail?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading && book == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, book == nil {
                ContentUnavailableView {
                    Label("Couldn't load book", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await load() } }
                }
            } else if let book {
                detail(book)
            }
        }
        .background(AudexColor.background.ignoresSafeArea())
        .navigationTitle(book?.displayTitle ?? "Book")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let book {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await toggleFavorite(book) }
                    } label: {
                        Image(systemName: book.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(book.isFavorite ? AudexColor.favorite : AudexColor.primary)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let book {
                actionBar(book)
            }
        }
        .task(id: bookID) {
            await load()
        }
    }

    private func detail(_ book: BookDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(book)

                if book.isStarted, book.durationSec > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(book.progressSec), total: Double(max(book.durationSec, 1)))
                            .tint(AudexColor.primary)
                        Text("Progress: \(DurationFormat.short(book.progressSec)) of \(DurationFormat.short(book.durationSec))")
                            .font(.caption)
                            .foregroundStyle(AudexColor.onSurfaceVariant)
                    }
                }

                downloadStatus(book)

                let description = HTMLText.plain(book.description)
                if !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(description)
                            .font(.body)
                            .foregroundStyle(AudexColor.onSurface)
                    }
                }

                metadata(book)

                let genres = book.genres ?? []
                if !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Genres")
                            .font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(genres, id: \.self) { genre in
                                GenreChip(text: genre)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Chapters")
                        .font(.headline)
                    ForEach(Array(book.sortedChapters.enumerated()), id: \.element.id) { index, chapter in
                        Button {
                            playback.play(detail: book, chapterIndex: index)
                            playback.isNowPlayingPresented = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chapter.title)
                                        .foregroundStyle(AudexColor.onSurface)
                                        .multilineTextAlignment(.leading)
                                    Text(DurationFormat.clock(chapter.durationSec))
                                        .font(.caption)
                                        .foregroundStyle(AudexColor.onSurfaceVariant)
                                }
                                Spacer()
                                Image(systemName: "play.circle")
                                    .foregroundStyle(AudexColor.primary)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if index < book.sortedChapters.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ book: BookDetail) -> some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(bookID: book.id, hasCover: book.hasCover, cornerRadius: 10)
                .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.displayTitle)
                    .font(.title2.bold())
                Text(book.author)
                    .font(.headline)
                    .foregroundStyle(AudexColor.primary)
                if let readBy = book.readBy, !readBy.isEmpty {
                    Text("Read by \(readBy)")
                        .font(.subheadline)
                        .foregroundStyle(AudexColor.onSurfaceVariant)
                }
                if let publisher = book.publisher, !publisher.isEmpty {
                    Text(book.year.map { "\(publisher) · \($0)" } ?? publisher)
                        .font(.caption)
                        .foregroundStyle(AudexColor.onSurfaceVariant)
                }
                if let rating = book.rating {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(String(format: "%.1f", rating))
                        if let count = book.ratingCount {
                            Text("(\(count))")
                                .foregroundStyle(AudexColor.onSurfaceVariant)
                        }
                    }
                    .font(.caption)
                }
                FlowLayout(spacing: 8) {
                    MetaChip(systemImage: "clock", text: DurationFormat.short(book.durationSec))
                    MetaChip(systemImage: "book", text: "\(book.chapterCount) chapters")
                    MetaChip(
                        systemImage: book.isCompleted ? "checkmark.circle" : (book.isStarted ? "chart.bar" : "circle"),
                        text: book.isCompleted ? "Finished" : (book.isStarted ? "In progress" : "Not started")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func downloadStatus(_ book: BookDetail) -> some View {
        switch downloads.state(for: book) {
        case .downloading(let completed, let total):
            Text("Downloading \(completed)/\(total) chapters")
                .font(.subheadline)
                .foregroundStyle(AudexColor.primary)
        case .completed:
            Label("Downloaded for offline playback", systemImage: "checkmark.circle")
                .font(.subheadline)
                .foregroundStyle(AudexColor.primary)
        case .error(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
        case .idle:
            EmptyView()
        }
    }

    private func metadata(_ book: BookDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.headline)
            metadataRow("Added", book.addedAt.replacingOccurrences(of: "T", with: " ").prefix(16).description)
            if let language = book.language { metadataRow("Language", language.uppercased()) }
            if let isbn = book.isbn13 ?? book.isbn10 { metadataRow("ISBN", isbn) }
            if let pages = book.pageCount { metadataRow("Pages", "\(pages)") }
            metadataRow("Duration", DurationFormat.clock(book.durationSec))
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(AudexColor.onSurfaceVariant)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    private func actionBar(_ book: BookDetail) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await downloads.download(book) }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled({
                if case .downloading = downloads.state(for: book) { return true }
                return false
            }())

            Button {
                playback.play(detail: book)
                playback.isNowPlayingPresented = true
            } label: {
                Label(book.isStarted && !book.isCompleted ? "Continue" : "Play", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            book = try await session.api.book(id: bookID)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleFavorite(_ book: BookDetail) async {
        let newValue = !book.isFavorite
        self.book?.isFavorite = newValue
        library.applyFavorite(bookID: book.id, isFavorite: newValue)
        do {
            try await session.api.setFavorite(id: book.id, isFavorite: newValue)
        } catch {
            self.book?.isFavorite = !newValue
            library.applyFavorite(bookID: book.id, isFavorite: !newValue)
        }
    }
}
