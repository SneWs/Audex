import SwiftUI

struct LibraryView: View {
    let filter: LibraryFilter

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        NavigationStack {
            Group {
                if library.isLoading && library.books.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = library.errorMessage, library.books.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't load library", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            Task { await library.refresh() }
                        }
                    }
                } else {
                    let items = library.books(for: filter)
                    if items.isEmpty {
                        ContentUnavailableView(filter.emptyMessage, systemImage: "books.vertical")
                    } else {
                        BookGrid(books: items)
                    }
                }
            }
            .background(AudexColor.background.ignoresSafeArea())
            .navigationTitle(filter.title)
            .navigationDestination(for: Int.self) { bookID in
                BookDetailView(bookID: bookID)
            }
            .refreshable {
                await library.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if library.isLoading {
                        ProgressView()
                    }
                }
            }
        }
        .task {
            if library.books.isEmpty {
                await library.refresh()
            }
        }
    }
}

struct BookGrid: View {
    let books: [Book]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                ForEach(books) { book in
                    NavigationLink(value: book.id) {
                        BookCard(book: book)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}

struct BookCard: View {
    let book: Book

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback

    private var isThisPlaying: Bool {
        playback.currentBook?.id == book.id && playback.isPlaying
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CoverImage(bookID: book.id, hasCover: book.hasCover, cornerRadius: 6)
                    .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(book.displayTitle)
                            .font(.headline)
                            .foregroundStyle(AudexColor.onSurface)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            Task { await library.toggleFavorite(book) }
                        } label: {
                            Image(systemName: book.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(book.isFavorite ? AudexColor.favorite : AudexColor.onSurfaceVariant)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(AudexColor.primary)
                        .lineLimit(1)
                    if let readBy = book.readBy, !readBy.isEmpty {
                        Text("Read by \(readBy)")
                            .font(.caption)
                            .foregroundStyle(AudexColor.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 8) {
                MetaChip(systemImage: "book", text: "\(book.chapterCount) chapter\(book.chapterCount == 1 ? "" : "s")")
                MetaChip(systemImage: "clock", text: DurationFormat.short(book.durationSec))
                if book.isCompleted {
                    MetaChip(systemImage: "checkmark.circle", text: "Finished")
                }
            }

            let genres = book.genres ?? []
            if !genres.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(genres.prefix(6), id: \.self) { genre in
                        GenreChip(text: genre)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if book.isStarted, !book.isCompleted, book.durationSec > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(book.progressSec), total: Double(max(book.durationSec, 1)))
                        .tint(AudexColor.primary)
                    Text("\(DurationFormat.short(book.progressSec)) of \(DurationFormat.short(book.durationSec))")
                        .font(.caption)
                        .foregroundStyle(AudexColor.onSurfaceVariant)
                }
            }

            Button {
                Task { await playback.play(bookID: book.id) }
            } label: {
                Label(playTitle, systemImage: isThisPlaying ? "pause.fill" : "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AudexColor.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var playTitle: String {
        if isThisPlaying { return "PAUSE" }
        if book.isCompleted { return "PLAY AGAIN" }
        if book.isStarted { return "CONTINUE" }
        return "PLAY"
    }
}

struct MetaChip: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AudexColor.primary.opacity(0.12), in: Capsule())
    }
}

struct GenreChip: View {
    let text: String
    var selected: Bool = false

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? .white : AudexColor.primary)
            .background(
                Capsule().fill(selected ? AudexColor.primary : Color.clear)
            )
            .overlay {
                Capsule().stroke(AudexColor.primary.opacity(0.5))
            }
    }
}
