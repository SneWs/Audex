import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case unauthorized
    case status(Int, String?)
    case decoding(Error)
    case transport(Error)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Server URL is not configured"
        case .unauthorized:
            "Invalid email or password"
        case .status(let code, let message):
            message ?? "Request failed (HTTP \(code))"
        case .decoding:
            "Couldn't read the server response"
        case .transport(let error):
            error.localizedDescription
        case .message(let message):
            message
        }
    }
}

final class APIClient: @unchecked Sendable {
    var origin: URL?
    var token: String?
    var onUnauthorized: (() -> Void)?

    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var isRefreshing = false

    init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = ["User-Agent": "Audex-iOS"]
        session = URLSession(configuration: config)
        encoder.outputFormatting = [.sortedKeys]
    }

    static func normalize(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://\(value)"
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return URL(string: value)
    }

    func validateServer(_ raw: String) async throws -> URL {
        guard let origin = Self.normalize(raw) else {
            throw APIError.message("Invalid Server URL")
        }
        var request = URLRequest(url: try url("books", origin: origin))
        request.timeoutInterval = 8
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.message("Connection failed")
            }
            if http.statusCode == 404 {
                throw APIError.message("No Audex API at this URL")
            }
            return origin
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error)
        }
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await post("login", body: LoginRequest(email: email, password: password), authorized: false)
    }

    func register(email: String, password: String) async throws -> AuthResponse {
        try await post("register", body: LoginRequest(email: email, password: password), authorized: false)
    }

    func refresh() async throws -> AuthResponse {
        try decode(try await send(method: "POST", path: "refresh", body: nil, authorized: true))
    }

    func books() async throws -> [Book] {
        try await get("books")
    }

    func book(id: Int) async throws -> BookDetail {
        try await get("books/\(id)")
    }

    func updateProgress(userID: Int, update: ProgressUpdate) async throws {
        let _: Data = try await data(
            method: "POST",
            path: "users/\(userID)/progress",
            body: update,
            authorized: true
        )
    }

    func setFavorite(id: Int, isFavorite: Bool) async throws {
        _ = try await send(
            method: isFavorite ? "PUT" : "DELETE",
            path: "books/\(id)/favorite",
            body: nil,
            authorized: true
        )
    }

    func account() async throws -> Account {
        try await get("account")
    }

    func updateEmail(newEmail: String, currentPassword: String) async throws -> EmailChangeResponse {
        try await put("account/email", body: ChangeEmailRequest(newEmail: newEmail, currentPassword: currentPassword))
    }

    func updatePassword(currentPassword: String, newPassword: String) async throws {
        let _: Data = try await data(
            method: "PUT",
            path: "account/password",
            body: ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword),
            authorized: true
        )
    }

    func coverURL(for bookID: Int) -> URL? {
        try? url("books/\(bookID)/cover")
    }

    func audioURL(chapterID: Int) -> URL? {
        try? url("chapters/\(chapterID)/audio")
    }

    func downloadURL(chapterID: Int) -> URL? {
        try? url("chapters/\(chapterID)/download")
    }

    func authenticatedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Audex-iOS", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try decode(try await send(method: "GET", path: path, body: nil as Data?, authorized: true))
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, authorized: Bool) async throws -> T {
        try decode(try await send(method: "POST", path: path, body: encoder.encode(body), authorized: authorized))
    }

    private func put<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        try decode(try await send(method: "PUT", path: path, body: encoder.encode(body), authorized: true))
    }

    private func decode<T: Decodable>(_ payload: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: payload)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func data(method: String, path: String, body: (any Encodable)?, authorized: Bool) async throws -> Data {
        let encoded: Data?
        if let body {
            encoded = try encoder.encode(AnyEncodable(body))
        } else {
            encoded = nil
        }
        return try await send(method: method, path: path, body: encoded, authorized: authorized)
    }

    private func send(method: String, path: String, body: Data?, authorized: Bool) async throws -> Data {
        if authorized {
            try await refreshIfNeeded()
        }

        var request = URLRequest(url: try url(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let payload: Data
        let response: URLResponse
        do {
            (payload, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.message("Connection failed")
        }

        if http.statusCode == 401 {
            if authorized {
                token = nil
                onUnauthorized?()
            }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(MessageResponse.self, from: payload))?.message
            throw APIError.status(http.statusCode, message)
        }

        return payload
    }

    private func refreshIfNeeded() async throws {
        guard let token, JWTClaims.isNearExpiry(token) else { return }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await refresh()
            self.token = response.token
            KeychainStore.save(response.token)
        } catch {
            // Keep going with the current token; a later 401 handles expiry.
        }
    }

    private func url(_ path: String, origin: URL? = nil) throws -> URL {
        guard let origin = origin ?? self.origin else { throw APIError.notConfigured }
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else {
            throw APIError.notConfigured
        }
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        components.path = base.isEmpty ? "/\(trimmedPath)" : "\(base)/\(trimmedPath)"
        guard let url = components.url else { throw APIError.notConfigured }
        return url
    }
}

private struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeClosure = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}
