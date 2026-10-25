import Foundation

struct AuthResponse: Codable {
    let token: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct MessageResponse: Codable {
    let message: String?
}

struct Account: Codable {
    let id: Int
    let email: String
    let role: String
    let isDefaultAdmin: Bool
}

struct EmailChangeResponse: Codable {
    let message: String?
    let email: String
    let token: String
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
    let trackNumber: Int
    let durationSec: Int
    let streamUrl: String
    let downloadUrl: String

    enum CodingKeys: String, CodingKey {
        case id, title, trackNumber, durationSec, streamUrl, downloadUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Chapter"
        trackNumber = try container.decodeIfPresent(Int.self, forKey: .trackNumber) ?? 0
        durationSec = try container.decodeIfPresent(Int.self, forKey: .durationSec) ?? 0
        streamUrl = try container.decodeIfPresent(String.self, forKey: .streamUrl) ?? ""
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl) ?? ""
    }
}

struct Book: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let customTitle: String?
    let subtitle: String?
    let author: String
    let year: Int?
    let readBy: String?
    let durationSec: Int
    let chapterCount: Int
    let hasCover: Bool
    let description: String?
    let publisher: String?
    let language: String?
    let isbn10: String?
    let isbn13: String?
    let pageCount: Int?
    let rating: Double?
    let ratingCount: Int?
    let openLibraryUrl: String?
    let addedAt: String
    var progressSec: Int
    var isCompleted: Bool
    var isFavorite: Bool
    let lastPlayedAt: String?
    let resumeChapterId: Int?
    let resumePositionSec: Int
    let genres: [String]?

    var displayTitle: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }
        return title
    }

    var isStarted: Bool {
        lastPlayedAt != nil || resumePositionSec > 0 || resumeChapterId != nil
    }

    var progressFraction: Double {
        guard durationSec > 0 else { return 0 }
        return min(1, max(0, Double(progressSec) / Double(durationSec)))
    }

    var remainingSec: Int {
        max(0, durationSec - progressSec)
    }

    var genreList: [String] {
        genres ?? []
    }
}

struct BookDetail: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let customTitle: String?
    let subtitle: String?
    let author: String
    let year: Int?
    let readBy: String?
    let durationSec: Int
    let chapterCount: Int
    let hasCover: Bool
    let description: String?
    let publisher: String?
    let language: String?
    let isbn10: String?
    let isbn13: String?
    let pageCount: Int?
    let rating: Double?
    let ratingCount: Int?
    let openLibraryUrl: String?
    let addedAt: String
    var progressSec: Int
    var isCompleted: Bool
    var isFavorite: Bool
    let lastPlayedAt: String?
    let resumeChapterId: Int?
    let resumePositionSec: Int
    let genres: [String]?
    let chapters: [Chapter]?

    var displayTitle: String {
        if let customTitle, !customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customTitle
        }
        return title
    }

    var artistLine: String {
        if let readBy, !readBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(author) · Read by \(readBy)"
        }
        return author
    }

    var isStarted: Bool {
        lastPlayedAt != nil || resumePositionSec > 0 || resumeChapterId != nil
    }

    var progressFraction: Double {
        guard durationSec > 0 else { return 0 }
        return min(1, max(0, Double(progressSec) / Double(durationSec)))
    }

    var remainingSec: Int {
        max(0, durationSec - progressSec)
    }

    var sortedChapters: [Chapter] {
        (chapters ?? []).sorted { lhs, rhs in
            if lhs.trackNumber == rhs.trackNumber {
                return lhs.id < rhs.id
            }
            return lhs.trackNumber < rhs.trackNumber
        }
    }

    var asBook: Book {
        Book(
            id: id,
            title: title,
            customTitle: customTitle,
            subtitle: subtitle,
            author: author,
            year: year,
            readBy: readBy,
            durationSec: durationSec,
            chapterCount: chapterCount,
            hasCover: hasCover,
            description: description,
            publisher: publisher,
            language: language,
            isbn10: isbn10,
            isbn13: isbn13,
            pageCount: pageCount,
            rating: rating,
            ratingCount: ratingCount,
            openLibraryUrl: openLibraryUrl,
            addedAt: addedAt,
            progressSec: progressSec,
            isCompleted: isCompleted,
            isFavorite: isFavorite,
            lastPlayedAt: lastPlayedAt,
            resumeChapterId: resumeChapterId,
            resumePositionSec: resumePositionSec,
            genres: genres
        )
    }
}

struct Playlist: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    var isAutoGenerated: Bool
    var ownerUserId: Int?
    var ownerEmail: String?
    var canEdit: Bool
    let createdAt: String
    let updatedAt: String
    var books: [Book]

    enum CodingKeys: String, CodingKey {
        case id, name, isAutoGenerated, ownerUserId, ownerEmail, canEdit, createdAt, updatedAt, books
    }

    init(
        id: Int,
        name: String,
        isAutoGenerated: Bool = false,
        ownerUserId: Int? = nil,
        ownerEmail: String? = nil,
        canEdit: Bool = false,
        createdAt: String = "",
        updatedAt: String = "",
        books: [Book] = []
    ) {
        self.id = id
        self.name = name
        self.isAutoGenerated = isAutoGenerated
        self.ownerUserId = ownerUserId
        self.ownerEmail = ownerEmail
        self.canEdit = canEdit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.books = books
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Series"
        isAutoGenerated = try container.decodeIfPresent(Bool.self, forKey: .isAutoGenerated) ?? false
        ownerUserId = try container.decodeIfPresent(Int.self, forKey: .ownerUserId)
        ownerEmail = try container.decodeIfPresent(String.self, forKey: .ownerEmail)
        canEdit = try container.decodeIfPresent(Bool.self, forKey: .canEdit) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        books = try container.decodeIfPresent([Book].self, forKey: .books) ?? []
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case continueListening
    case recents
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "My Library"
        case .continueListening: return "Continue Listening"
        case .recents: return "Recently Added"
        case .favorites: return "Favorites"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "Your library is empty"
        case .continueListening: return "Nothing in progress"
        case .recents: return "No recent additions"
        case .favorites: return "No favorites yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .all: return "Books added to your Audex server will appear here."
        case .continueListening: return "Start listening to an audiobook to pick up where you left off."
        case .recents: return "Recently added audiobooks will appear here."
        case .favorites: return "Tap the heart on any audiobook to save it to Favorites."
        }
    }
}
