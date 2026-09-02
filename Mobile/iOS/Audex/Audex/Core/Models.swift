import Foundation

struct AuthResponse: Codable {
    let token: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct MessageResponse: Codable {
    let message: String
}

struct Account: Codable {
    let id: Int
    let email: String
    let prefersDarkMode: Bool
}

struct EmailChangeResponse: Codable {
    let token: String
    let email: String
}

struct ChangeEmailRequest: Codable {
    let newEmail: String
    let currentPassword: String
}

struct ChangePasswordRequest: Codable {
    let currentPassword: String
    let newPassword: String
}

struct ProgressUpdate: Codable {
    let bookId: Int
    let chapterId: Int
    let positionSec: Int
}

struct Chapter: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let durationSec: Int
    let trackNumber: Int
    var audioUrl: String
    var downloadUrl: String

    init(id: Int, title: String, durationSec: Int, trackNumber: Int, audioUrl: String = "", downloadUrl: String = "") {
        self.id = id
        self.title = title
        self.durationSec = durationSec
        self.trackNumber = trackNumber
        self.audioUrl = audioUrl
        self.downloadUrl = downloadUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        durationSec = try container.decode(Int.self, forKey: .durationSec)
        trackNumber = try container.decode(Int.self, forKey: .trackNumber)
        audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl) ?? ""
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl) ?? ""
    }
}

struct Book: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    var customTitle: String?
    var subtitle: String?
    let author: String
    var year: Int?
    var readBy: String?
    let durationSec: Int
    let chapterCount: Int
    let hasCover: Bool
    var description: String?
    var publisher: String?
    var language: String?
    var isbn10: String?
    var isbn13: String?
    var pageCount: Int?
    var rating: Double?
    var ratingCount: Int?
    var openLibraryUrl: String?
    let addedAt: String
    let progressSec: Int
    let isCompleted: Bool
    var isFavorite: Bool
    var lastPlayedAt: String?
    var resumeChapterId: Int?
    let resumePositionSec: Int
    var genres: [String]? = []

    var isStarted: Bool { lastPlayedAt != nil }

    var displayTitle: String {
        let custom = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? title : custom
    }

    var artistLine: String {
        Self.artistLine(author: author, readBy: readBy)
    }

    static func artistLine(author: String, readBy: String?) -> String {
        let author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let narrator = (readBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !author.isEmpty, !narrator.isEmpty { return "\(author) · Read by \(narrator)" }
        if !author.isEmpty { return author }
        if !narrator.isEmpty { return "Read by \(narrator)" }
        return ""
    }
}

struct BookDetail: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    var customTitle: String?
    var subtitle: String?
    let author: String
    var year: Int?
    var readBy: String?
    let durationSec: Int
    let chapterCount: Int
    let hasCover: Bool
    var description: String?
    var publisher: String?
    var language: String?
    var isbn10: String?
    var isbn13: String?
    var pageCount: Int?
    var rating: Double?
    var ratingCount: Int?
    var openLibraryUrl: String?
    let addedAt: String
    let progressSec: Int
    let isCompleted: Bool
    var isFavorite: Bool
    var lastPlayedAt: String?
    var resumeChapterId: Int?
    let resumePositionSec: Int
    var genres: [String]? = []
    var chapters: [Chapter] = []

    var isStarted: Bool { lastPlayedAt != nil }

    var displayTitle: String {
        let custom = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? title : custom
    }

    var artistLine: String {
        Book.artistLine(author: author, readBy: readBy)
    }

    var sortedChapters: [Chapter] {
        chapters.sorted { lhs, rhs in
            if lhs.trackNumber != rhs.trackNumber { return lhs.trackNumber < rhs.trackNumber }
            return lhs.id < rhs.id
        }
    }
}

extension BookDetail {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        customTitle = try container.decodeIfPresent(String.self, forKey: .customTitle)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        author = try container.decode(String.self, forKey: .author)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        readBy = try container.decodeIfPresent(String.self, forKey: .readBy)
        durationSec = try container.decode(Int.self, forKey: .durationSec)
        chapterCount = try container.decode(Int.self, forKey: .chapterCount)
        hasCover = try container.decode(Bool.self, forKey: .hasCover)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        isbn10 = try container.decodeIfPresent(String.self, forKey: .isbn10)
        isbn13 = try container.decodeIfPresent(String.self, forKey: .isbn13)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        ratingCount = try container.decodeIfPresent(Int.self, forKey: .ratingCount)
        openLibraryUrl = try container.decodeIfPresent(String.self, forKey: .openLibraryUrl)
        addedAt = try container.decode(String.self, forKey: .addedAt)
        progressSec = try container.decodeIfPresent(Int.self, forKey: .progressSec) ?? 0
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        lastPlayedAt = try container.decodeIfPresent(String.self, forKey: .lastPlayedAt)
        resumeChapterId = try container.decodeIfPresent(Int.self, forKey: .resumeChapterId)
        resumePositionSec = try container.decodeIfPresent(Int.self, forKey: .resumePositionSec) ?? 0
        genres = try container.decodeIfPresent([String].self, forKey: .genres) ?? []
        chapters = try container.decodeIfPresent([Chapter].self, forKey: .chapters) ?? []
    }
}

enum LibraryFilter: String, Hashable, CaseIterable {
    case all
    case continueListening
    case recents
    case favorites

    var title: String {
        switch self {
        case .all: "My Library"
        case .continueListening: "Continue Listening"
        case .recents: "Recently Added"
        case .favorites: "Favorites"
        }
    }

    var subtitle: String? {
        switch self {
        case .all: nil
        case .continueListening: "Books you've started but haven't finished"
        case .recents: "The latest audiobooks added to your library"
        case .favorites: "Books you've marked as favorites"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: "No books found"
        case .continueListening: "Nothing in progress"
        case .recents: "No recently added books"
        case .favorites: "No favorites yet"
        }
    }
}
