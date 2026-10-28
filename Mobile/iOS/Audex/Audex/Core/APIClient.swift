import Foundation

enum APIError: LocalizedError {
    case missingServerURL
    case invalidServerURL
    case unauthorized
    case httpStatus(Int, String?)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingServerURL:
            return "Configure your Audex server URL to continue."
        case .invalidServerURL:
            return "Enter a valid http:// or https:// server URL."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .httpStatus(let code, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "Server returned HTTP \(code)."
        case .invalidResponse:
            return "Received an unexpected response from the server."
        }
    }
}

@MainActor
final class APIClient {
    var baseURL: URL?
    var token: String?
    var onUnauthorized: (() -> Void)?
    var onTokenRefreshed: ((String) -> Void)?

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var isRefreshing = false

    nonisolated static func normalize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withTrailingSlash = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
        guard let url = URL(string: withTrailingSlash),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    init(baseURL: URL? = nil, token: String? = nil) {
        self.baseURL = baseURL
        self.token = token

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: config)

        let decoder = JSONDecoder()
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }

    func resolvedURL(_ path: String) throws -> URL {
        guard let baseURL else { throw APIError.missingServerURL }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        if let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
            return url
        }
        throw APIError.invalidServerURL
    }

    func coverURL(for bookID: Int) -> URL? {
        try? resolvedURL("books/\(bookID)/cover")
    }

    func chapterStreamURL(for chapterID: Int, streamPath: String? = nil) -> URL? {
        if let streamPath, !streamPath.isEmpty, let url = try? resolvedURL(streamPath) {
            return url
        }
        return try? resolvedURL("chapters/\(chapterID)/audio")
    }

    func chapterDownloadURL(for chapter: Chapter) -> URL? {
        if !chapter.downloadUrl.isEmpty, let url = try? resolvedURL(chapter.downloadUrl) {
            return url
        }
        return try? resolvedURL("chapters/\(chapter.id)/download")
    }

    func authorizedHeaderValue() -> [String: String] {
        guard let token, !token.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    func validateServer(url: URL) async throws {
        var request = URLRequest(url: url.appendingPathComponent("books"))
        request.httpMethod = "GET"
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<500).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode, nil)
        }
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = try encoder.encode(LoginRequest(email: email, password: password))
        return try await request("POST", path: "login", body: body, authorized: false)
    }

    func refresh() async throws -> AuthResponse {
        return try await request("POST", path: "refresh", authorized: true)
    }

    /// Refreshes the token if it is nearing expiry. Safe to call repeatedly;
    /// does nothing when there is no token or when the token is still valid.
    func refreshIfNearingExpiry() async {
        guard let token, !token.isEmpty else { return }
        guard JWTClaims.isNearExpiry(token) else { return }
        _ = await attemptTokenRefresh()
    }

    func books() async throws -> [Book] {
        try await request("GET", path: "books")
    }

    func book(id: Int) async throws -> BookDetail {
        try await request("GET", path: "books/\(id)")
    }

    func playlists() async throws -> [Playlist] {
        try await request("GET", path: "playlists")
    }

    func playlist(id: Int) async throws -> Playlist {
        try await request("GET", path: "playlists/\(id)")
    }

    func setFavorite(bookID: Int, isFavorite: Bool) async throws {
        let method = isFavorite ? "PUT" : "DELETE"
        _ = try await send(method: method, path: "books/\(bookID)/favorite", body: nil, authorized: true)
    }

    func completeBook(id: Int) async throws {
        do {
            _ = try await send(method: "PUT", path: "books/\(id)/complete", body: nil, authorized: true)
        } catch {
            do {
                _ = try await send(method: "POST", path: "books/\(id)/complete", body: nil, authorized: true)
            } catch {
                _ = try await send(method: "PUT", path: "books/\(id)/completed", body: nil, authorized: true)
            }
        }
    }

    func updateProgress(userID: Int, progress: ProgressUpdate) async throws {
        let body = try encoder.encode(progress)
        _ = try await send(method: "POST", path: "users/\(userID)/progress", body: body, authorized: true)
    }

    func account() async throws -> Account {
        try await request("GET", path: "account")
    }

    func changeEmail(newEmail: String, currentPassword: String) async throws -> EmailChangeResponse {
        let body = try encoder.encode(ChangeEmailRequest(newEmail: newEmail, currentPassword: currentPassword))
        return try await request("PUT", path: "account/email", body: body)
    }

    func changePassword(currentPassword: String, newPassword: String) async throws -> MessageResponse {
        let body = try encoder.encode(ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword))
        return try await request("PUT", path: "account/password", body: body)
    }

    func downloadFile(from url: URL, to destinationURL: URL) async throws {
        await refreshIfNeeded()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 401 {
            if await attemptTokenRefresh(), let token, !token.isEmpty {
                var retryRequest = URLRequest(url: url)
                retryRequest.httpMethod = "GET"
                retryRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (retryTempURL, retryResponse) = try await session.download(for: retryRequest)
                guard let retryHttp = retryResponse as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                if (200..<300).contains(retryHttp.statusCode) {
                    try moveDownloadedFile(from: retryTempURL, to: destinationURL)
                    return
                }
                if retryHttp.statusCode == 401 {
                    handleSessionExpired()
                    throw APIError.unauthorized
                }
                throw APIError.httpStatus(retryHttp.statusCode, nil)
            }
            handleSessionExpired()
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.httpStatus(http.statusCode, nil)
        }
        try moveDownloadedFile(from: tempURL, to: destinationURL)
    }

    private func moveDownloadedFile(from tempURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default
        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
    }

    private func request<T: Decodable>(
        _ method: String,
        path: String,
        body: Data? = nil,
        authorized: Bool = true
    ) async throws -> T {
        let data = try await send(method: method, path: path, body: body, authorized: authorized)
        return try decoder.decode(T.self, from: data)
    }

    private func send(
        method: String,
        path: String,
        body: Data?,
        authorized: Bool,
        allowRetryOn401: Bool = true
    ) async throws -> Data {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let isAuthRequest = cleanPath == "login" || cleanPath == "register" || cleanPath.hasSuffix("/login") || cleanPath.hasSuffix("/register")
        let isRefreshRequest = cleanPath == "refresh" || cleanPath.hasSuffix("/refresh")

        if authorized && !isAuthRequest && !isRefreshRequest {
            await refreshIfNeeded()
        }

        let url = try resolvedURL(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized && !isAuthRequest, let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 {
            if isAuthRequest || !authorized {
                let message = (try? decoder.decode(MessageResponse.self, from: data))?.message
                    ?? "Invalid email or password"
                throw APIError.httpStatus(401, message)
            }

            if !isRefreshRequest && allowRetryOn401 {
                if await attemptTokenRefresh() {
                    return try await send(
                        method: method,
                        path: path,
                        body: body,
                        authorized: authorized,
                        allowRetryOn401: false
                    )
                }
            }

            handleSessionExpired()
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(MessageResponse.self, from: data))?.message
            throw APIError.httpStatus(http.statusCode, message)
        }

        return data
    }

    private func refreshIfNeeded() async {
        guard !isRefreshing, let token, JWTClaims.isNearExpiry(token) else { return }
        _ = await attemptTokenRefresh()
    }

    private func attemptTokenRefresh() async -> Bool {
        guard !isRefreshing, let currentToken = token, !currentToken.isEmpty else { return false }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let url = try resolvedURL("refresh")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return false
            }
            let refreshed = try decoder.decode(AuthResponse.self, from: data)
            self.token = refreshed.token
            KeychainStore.save(refreshed.token)
            onTokenRefreshed?(refreshed.token)
            return true
        } catch {
            return false
        }
    }

    private func handleSessionExpired() {
        token = nil
        KeychainStore.delete()
        onUnauthorized?()
    }
}
