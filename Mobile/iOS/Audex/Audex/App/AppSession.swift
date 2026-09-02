import Foundation

@Observable
final class AppSession {
    let settings: AppSettings
    let api = APIClient()

    var sessionExpiredMessage: String?
    var account: Account?

    var isLoggedIn: Bool { api.token != nil }
    var serverURL: URL? { settings.serverURL }
    var prefersDarkMode: Bool {
        get { settings.prefersDarkMode }
        set { settings.prefersDarkMode = newValue }
    }

    var userID: Int? {
        guard let token = api.token else { return nil }
        return JWTClaims.userID(from: token)
    }

    init() {
        settings = AppSettings()
        api.origin = settings.serverURL
        api.token = KeychainStore.load()
        api.onUnauthorized = { [weak self] in
            self?.handleSessionExpired()
        }
    }

    func saveServerURL(_ raw: String) async throws {
        let origin = try await api.validateServer(raw)
        settings.serverURLString = origin.absoluteString
        api.origin = origin
    }

    func login(email: String, password: String) async throws {
        let response = try await api.login(email: email, password: password)
        store(token: response.token)
        sessionExpiredMessage = nil
        await loadAccount()
    }

    func register(email: String, password: String) async throws {
        let response = try await api.register(email: email, password: password)
        store(token: response.token)
        sessionExpiredMessage = nil
        await loadAccount()
    }

    func logout() {
        api.token = nil
        account = nil
        KeychainStore.delete()
    }

    func handleSessionExpired() {
        api.token = nil
        account = nil
        KeychainStore.delete()
        sessionExpiredMessage = "Session expired. Please log in again."
    }

    func loadAccount() async {
        do {
            account = try await api.account()
        } catch {
            account = nil
        }
    }

    func updateEmail(newEmail: String, currentPassword: String) async throws {
        let response = try await api.updateEmail(newEmail: newEmail, currentPassword: currentPassword)
        store(token: response.token)
        await loadAccount()
    }

    func updatePassword(currentPassword: String, newPassword: String) async throws {
        try await api.updatePassword(currentPassword: currentPassword, newPassword: newPassword)
    }

    private func store(token: String) {
        api.token = token
        KeychainStore.save(token)
    }
}

@Observable
final class LibraryStore {
    var books: [Book] = []
    var isLoading = false
    var errorMessage: String?

    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func books(for filter: LibraryFilter) -> [Book] {
        switch filter {
        case .all:
            books.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .continueListening:
            books.filter { $0.isStarted && !$0.isCompleted }
                .sorted { ($0.lastPlayedAt ?? "") > ($1.lastPlayedAt ?? "") }
        case .recents:
            Array(books.sorted { $0.addedAt > $1.addedAt }.prefix(20))
        case .favorites:
            books.filter(\.isFavorite)
                .sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        }
    }

    func refresh() async {
        isLoading = books.isEmpty
        errorMessage = nil
        do {
            books = try await session.api.books()
        } catch let error as APIError {
            if case .unauthorized = error { return }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func toggleFavorite(_ book: Book) async {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        let newValue = !books[index].isFavorite
        books[index].isFavorite.toggle()
        do {
            try await session.api.setFavorite(id: book.id, isFavorite: newValue)
        } catch {
            if let revert = books.firstIndex(where: { $0.id == book.id }) {
                books[revert].isFavorite = !newValue
            }
        }
    }

    func applyFavorite(bookID: Int, isFavorite: Bool) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].isFavorite = isFavorite
    }
}

@Observable
final class AppModel {
    let session: AppSession
    let library: LibraryStore
    let downloads: DownloadManager
    let playback: PlaybackController

    init() {
        let session = AppSession()
        self.session = session
        library = LibraryStore(session: session)
        downloads = DownloadManager(session: session)
        playback = PlaybackController(session: session, downloads: downloads)
    }
}
