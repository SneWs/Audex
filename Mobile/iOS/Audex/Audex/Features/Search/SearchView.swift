import SwiftUI

struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""
    @State private var selectedAuthors: Set<String> = []
    @State private var selectedYears: Set<Int> = []
    @State private var selectedNarrators: Set<String> = []
    @State private var selectedGenres: Set<String> = []

    private var filtered: [Book] {
        library.books.filter { book in
            matchesQuery(book) && matchesFilters(book)
        }
        .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
    }

    private var hasActiveFilters: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedAuthors.isEmpty
            || !selectedYears.isEmpty
            || !selectedNarrators.isEmpty
            || !selectedGenres.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasActiveFilters {
                    ContentUnavailableView("Search your library", systemImage: "magnifyingglass", description: Text("Try a title, author, year, narrator, or genre."))
                } else if filtered.isEmpty {
                    ContentUnavailableView("No results", systemImage: "magnifyingglass", description: Text("Try a broader search."))
                } else {
                    BookGrid(books: filtered)
                }
            }
            .background(AudexColor.background.ignoresSafeArea())
            .navigationTitle("Search")
            .navigationDestination(for: Int.self) { bookID in
                BookDetailView(bookID: bookID)
            }
            .searchable(text: $query, prompt: "Title, author, narrator, or genre")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if hasActiveFilters {
                        Text("\(filtered.count)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AudexColor.primary.opacity(0.15), in: Capsule())
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                filterBar
            }
            .refreshable {
                await library.refresh()
            }
        }
        .task {
            if library.books.isEmpty {
                await library.refresh()
            }
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        let authors = Set(library.books.map(\.author).filter { !$0.isEmpty }).sorted()
        let years = Set(library.books.compactMap(\.year)).sorted(by: >)
        let narrators = Set(library.books.compactMap(\.readBy).filter { !$0.isEmpty }).sorted()
        let genres = Set(library.books.flatMap { $0.genres ?? [] }).sorted()

        if authors.isEmpty && years.isEmpty && narrators.isEmpty && genres.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    chipGroup("Authors", items: authors, selection: $selectedAuthors)
                    yearGroup(years)
                    chipGroup("Narrators", items: narrators, selection: $selectedNarrators)
                    chipGroup("Genres", items: genres, selection: $selectedGenres)
                    if hasActiveFilters {
                        Button("Clear") {
                            query = ""
                            selectedAuthors.removeAll()
                            selectedYears.removeAll()
                            selectedNarrators.removeAll()
                            selectedGenres.removeAll()
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(AudexColor.surface)
        }
    }

    private func chipGroup(_ title: String, items: [String], selection: Binding<Set<String>>) -> some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button {
                    if selection.wrappedValue.contains(item) {
                        selection.wrappedValue.remove(item)
                    } else {
                        selection.wrappedValue.insert(item)
                    }
                } label: {
                    Label(item, systemImage: selection.wrappedValue.contains(item) ? "checkmark" : "")
                }
            }
        } label: {
            Label(menuTitle(title, count: selection.wrappedValue.count), systemImage: "line.3.horizontal.decrease.circle")
                .font(.caption.weight(.semibold))
        }
    }

    private func yearGroup(_ years: [Int]) -> some View {
        Menu {
            ForEach(years, id: \.self) { year in
                Button {
                    if selectedYears.contains(year) {
                        selectedYears.remove(year)
                    } else {
                        selectedYears.insert(year)
                    }
                } label: {
                    Label(String(year), systemImage: selectedYears.contains(year) ? "checkmark" : "")
                }
            }
        } label: {
            Label(menuTitle("Years", count: selectedYears.count), systemImage: "calendar")
                .font(.caption.weight(.semibold))
        }
    }

    private func menuTitle(_ title: String, count: Int) -> String {
        count == 0 ? title : "\(title) (\(count))"
    }

    private func matchesQuery(_ book: Book) -> Bool {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return true }
        let haystack = [
            book.displayTitle,
            book.author,
            book.readBy ?? "",
            book.description ?? "",
            book.year.map(String.init) ?? "",
            (book.genres ?? []).joined(separator: " ")
        ].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(raw)
    }

    private func matchesFilters(_ book: Book) -> Bool {
        if !selectedAuthors.isEmpty, !selectedAuthors.contains(book.author) { return false }
        if !selectedYears.isEmpty, !selectedYears.contains(book.year ?? -1) { return false }
        if !selectedNarrators.isEmpty, !selectedNarrators.contains(book.readBy ?? "") { return false }
        if !selectedGenres.isEmpty {
            let genres = Set(book.genres ?? [])
            if selectedGenres.isDisjoint(with: genres) { return false }
        }
        return true
    }
}
