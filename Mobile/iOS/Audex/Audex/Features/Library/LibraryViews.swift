import SwiftUI

struct LibraryView: View {
    let filter: LibraryFilter

    @Environment(LibraryStore.self) private var library

    var body: some View {
        NavigationStack {
            Group {
                let items = library.books(for: filter)
                if library.isLoading && library.books.isEmpty {
                    ProgressView("Loading library…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage = library.errorMessage, library.books.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't Load Library", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Retry") {
                            Task { await library.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if items.isEmpty {
                    ContentUnavailableView(
                        filter.emptyTitle,
                        systemImage: iconName,
                        description: Text(filter.emptyMessage)
                    )
                } else {
                    ScrollView {
                        BookGrid(books: items)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle(filter.title)
            .refreshable {
                await library.refresh()
            }
            .task {
                if library.books.isEmpty {
                    await library.refresh()
                }
            }
            .navigationDestination(for: Book.self) { book in
                BookDetailView(bookID: book.id, initialBook: book)
            }
        }
    }

    private var iconName: String {
        switch filter {
        case .all: return "books.vertical"
        case .continueListening: return "play.circle"
        case .recents: return "sparkles"
        case .favorites: return "heart"
        }
    }
}

struct BookGrid: View {
    let books: [Book]
    var onFavoriteToggle: ((Book) async -> Void)? = nil
    var onComplete: ((Book) async -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 460), spacing: 14, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(books) { book in
                NavigationLink(value: book) {
                    BookCard(
                        book: book,
                        onFavoriteToggle: onFavoriteToggle,
                        onComplete: onComplete
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct BookCard: View {
    let book: Book
    var onFavoriteToggle: ((Book) async -> Void)? = nil
    var onComplete: ((Book) async -> Void)? = nil

    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackController.self) private var playback

    var body: some View {
        let isThisPlaying = playback.currentBook?.id == book.id && playback.isPlaying
        let isStarted = book.isStarted && !book.isCompleted

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                CoverImage(bookID: book.id, hasCover: book.hasCover, cornerRadius: 10)
                    .frame(width: 78, height: 78)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(book.displayTitle)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 4)

                        Button {
                            Task {
                                if let onFavoriteToggle {
                                    await onFavoriteToggle(book)
                                } else {
                                    await library.toggleFavorite(book)
                                }
                            }
                        } label: {
                            Image(systemName: book.isFavorite ? "heart.fill" : "heart")
                                .foregroundStyle(book.isFavorite ? Color.red : .secondary)
                                .font(.body.weight(.semibold))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(book.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    }

                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if let readBy = book.readBy, !readBy.isEmpty {
                        Text("Narrated by \(readBy)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            HStack(spacing: 8) {
                MetaChip(icon: "book.closed", text: "\(book.chapterCount) ch")
                MetaChip(icon: "clock", text: DurationFormat.short(book.durationSec))
                if let year = book.year {
                    MetaChip(icon: "calendar", text: String(year))
                }
            }

            let genres = book.genreList
            if !genres.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(genres.prefix(3), id: \.self) { genre in
                        GenreChip(text: genre)
                    }
                }
            }

            if isStarted {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(Int((book.progressFraction * 100).rounded()))% complete")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AudexColor.coral)
                        Spacer()
                        Text("\(DurationFormat.short(book.remainingSec)) left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: book.progressFraction)
                        .tint(AudexColor.coral)
                }
            } else if book.isCompleted {
                Label("Completed", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AudexColor.amber)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await playback.play(bookID: book.id) }
                } label: {
                    Label(
                        isThisPlaying ? "Pause" : (isStarted ? "Continue" : "Play"),
                        systemImage: isThisPlaying ? "pause.fill" : "play.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AudexColor.coral)

                if isStarted {
                    Button {
                        Task {
                            if let onComplete {
                                await onComplete(book)
                            } else {
                                await library.completeBook(book.id)
                            }
                        }
                    } label: {
                        Text("Mark as complete")
                            .font(.caption.weight(.semibold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

struct MetaChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

struct GenreChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.system(size: 9))
            Text(text)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(AudexColor.coral)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(
            Capsule().strokeBorder(AudexColor.coral.opacity(0.45), lineWidth: 1)
        )
    }
}
