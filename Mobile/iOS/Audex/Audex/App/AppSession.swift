import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    let settings = AppSettings()
    let api: APIClient

    var serverURL: URL?
    var token: String?
    var account: Account?
    var sessionBannerMessage: String?

    init() {
        let initialURL = settings.serverURL
        let savedToken = KeychainStore.load()
        let validToken: String? = {
            guard let savedToken, !JWTClaims.isNearExpiry(savedToken, threshold: 0) else {
                KeychainStore.delete()
                return nil
            }
            return savedToken
        }()

        self.serverURL = initialURL
        self.token = validToken
        self.api = APIClient(baseURL: initialURL, token: validToken)

        self.api.onUnauthorized = { [weak self] in
            guard let self else { return }
            self.token = nil
            self.account = nil
            self.sessionBannerMessage = "Session expired. Please sign in again."
        }
        self.api.onTokenRefreshed = { [weak self] newToken in
            guard let self else { return }
            self.token = newToken
        }
    }

    var isLoggedIn: Bool {
        guard let token, !token.isEmpty else { return false }
        return !JWTClaims.isNearExpiry(token, threshold: 0)
    }

    var userID: Int? {
        if let account { return account.id }
        guard let token else { return nil }
        return JWTClaims.userID(from: token)
    }

    var prefersDarkMode: Bool {
        get { settings.prefersDarkMode }
        set { settings.prefersDarkMode = newValue }
    }

    var isDarkMode: Bool {
        get { settings.prefersDarkMode }
        set { settings.prefersDarkMode = newValue }
    }

    func saveServerURL(_ rawValue: String) async throws {
        guard let normalized = APIClient.normalize(rawValue) else {
            throw APIError.invalidServerURL
        }
        try await api.validateServer(url: normalized)
        settings.serverURLString = normalized.absoluteString
        serverURL = normalized
        api.baseURL = normalized
    }

    func applyServerURLWithoutRemoteValidation(_ rawValue: String) throws {
        guard let normalized = APIClient.normalize(rawValue) else {
            throw APIError.invalidServerURL
        }
        settings.serverURLString = normalized.absoluteString
        serverURL = normalized
        api.baseURL = normalized
    }

    func clearServerURL() {
        serverURL = nil
        api.baseURL = nil
    }

    func login(email: String, password: String) async throws {
        sessionBannerMessage = nil
        let response = try await api.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        token = response.token
        api.token = response.token
        KeychainStore.save(response.token)
        await loadAccount()
    }

    func loadAccount() async {
        guard isLoggedIn else { return }
        if let loaded = try? await api.account() {
            account = loaded
        }
    }

    func updateEmail(newEmail: String, currentPassword: String) async throws -> String {
        let response = try await api.changeEmail(newEmail: newEmail, currentPassword: currentPassword)
        token = response.token
        api.token = response.token
        KeychainStore.save(response.token)
        await loadAccount()
        return response.message ?? "Email updated."
    }

    func updatePassword(currentPassword: String, newPassword: String) async throws -> String {
        let response = try await api.changePassword(currentPassword: currentPassword, newPassword: newPassword)
        return response.message ?? "Password updated."
    }

    func logout() {
        token = nil
        account = nil
        api.token = nil
        KeychainStore.delete()
    }
}

@MainActor
@Observable
final class LibraryStore {
    private let session: AppSession

    var books: [Book] = []
    var isLoading = false
    var errorMessage: String?

    var playlists: [Playlist] = []
    var isLoadingPlaylists = false
    var playlistsError: String?

    init(session: AppSession) {
        self.session = session
    }

    func refresh() async {
        guard session.isLoggedIn else { return }
        if books.isEmpty {
            isLoading = true
        }
        errorMessage = nil
        do {
            books = try await session.api.books()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadPlaylists() async {
        guard session.isLoggedIn else { return }
        if playlists.isEmpty {
            isLoadingPlaylists = true
        }
        playlistsError = nil
        do {
            playlists = try await session.api.playlists()
        } catch {
            playlistsError = error.localizedDescription
        }
        isLoadingPlaylists = false
    }

    func books(for filter: LibraryFilter) -> [Book] {
        switch filter {
        case .all:
            return books.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .continueListening:
            return books
                .filter { $0.isStarted && !$0.isCompleted }
                .sorted { ($0.lastPlayedAt ?? "") > ($1.lastPlayedAt ?? "") }
        case .recents:
            return Array(books.sorted { $0.addedAt > $1.addedAt }.prefix(20))
        case .favorites:
            return books
                .filter(\.isFavorite)
                .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }

    func toggleFavorite(_ book: Book) async {
        let currentFavorite = books.first(where: { $0.id == book.id })?.isFavorite ?? book.isFavorite
        let next = !currentFavorite
        applyFavorite(bookID: book.id, isFavorite: next)
        do {
            try await session.api.setFavorite(bookID: book.id, isFavorite: next)
        } catch {
            applyFavorite(bookID: book.id, isFavorite: !next)
        }
    }

    func applyFavorite(bookID: Int, isFavorite: Bool) {
        if let index = books.firstIndex(where: { $0.id == bookID }) {
            books[index].isFavorite = isFavorite
        }
        for pIndex in playlists.indices {
            if let bIndex = playlists[pIndex].books.firstIndex(where: { $0.id == bookID }) {
                playlists[pIndex].books[bIndex].isFavorite = isFavorite
            }
        }
    }

    func completeBook(_ bookID: Int) async {
        applyCompleted(bookID: bookID)
        do {
            try await session.api.completeBook(id: bookID)
        } catch {
            await refresh()
        }
    }

    func applyCompleted(bookID: Int) {
        if let index = books.firstIndex(where: { $0.id == bookID }) {
            books[index].isCompleted = true
            books[index].progressSec = books[index].durationSec
        }
        for pIndex in playlists.indices {
            if let bIndex = playlists[pIndex].books.firstIndex(where: { $0.id == bookID }) {
                playlists[pIndex].books[bIndex].isCompleted = true
                playlists[pIndex].books[bIndex].progressSec = playlists[pIndex].books[bIndex].durationSec
            }
        }
    }

    var allAuthors: [String] {
        Array(Set(books.map(\.author).filter { !$0.isEmpty })).sorted()
    }

    var allYears: [Int] {
        Array(Set(books.compactMap(\.year))).sorted(by: >)
    }

    var allNarrators: [String] {
        Array(Set(books.compactMap(\.readBy).filter { !$0.isEmpty })).sorted()
    }

    var allGenres: [String] {
        Array(Set(books.flatMap(\.genreList).filter { !$0.isEmpty })).sorted()
    }
}

@MainActor
@Observable
final class AppModel {
    let session: AppSession
    let library: LibraryStore
    let downloads: DownloadManager
    let playback: PlaybackController

    init() {
        let session = AppSession()
        let library = LibraryStore(session: session)
        let downloads = DownloadManager(session: session)
        let playback = PlaybackController(session: session, downloads: downloads, library: library)
        self.session = session
        self.library = library
        self.downloads = downloads
        self.playback = playback
    }
}
