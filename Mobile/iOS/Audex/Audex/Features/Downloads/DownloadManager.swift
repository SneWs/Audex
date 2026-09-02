import Foundation

enum DownloadState: Equatable {
    case idle
    case downloading(completed: Int, total: Int)
    case completed
    case error(String)
}

@Observable
final class DownloadManager {
    private(set) var states: [Int: DownloadState] = [:]
    private let session: AppSession

    init(session: AppSession) {
        self.session = session
    }

    func state(for book: BookDetail) -> DownloadState {
        if let existing = states[book.id] { return existing }
        return isDownloaded(book) ? .completed : .idle
    }

    func isDownloaded(_ book: BookDetail) -> Bool {
        let chapters = book.sortedChapters
        guard !chapters.isEmpty else { return false }
        return chapters.allSatisfy { localFile(for: book, chapter: $0) != nil }
    }

    func download(_ book: BookDetail) async {
        if case .downloading = states[book.id] { return }

        let chapters = book.sortedChapters
        let total = chapters.count
        guard total > 0 else {
            states[book.id] = .error("No downloadable chapters")
            return
        }

        states[book.id] = .downloading(completed: 0, total: total)
        let directory = bookDirectory(for: book)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var completed = 0
            for chapter in chapters {
                try await Self.downloadChapter(book: book, chapter: chapter, directory: directory, api: session.api)
                completed += 1
                states[book.id] = .downloading(completed: completed, total: total)
            }
            states[book.id] = .completed
        } catch {
            states[book.id] = .error(error.localizedDescription)
        }
    }

    func localFile(for book: BookDetail, chapter: Chapter) -> URL? {
        let file = fileURL(book: book, chapter: chapter, directory: bookDirectory(for: book))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber, size.intValue > 0 {
            return file
        }
        return nil
    }

    private func bookDirectory(for book: BookDetail) -> URL {
        offlineRoot().appendingPathComponent(FileName.sanitize(book.title.isEmpty ? "book-\(book.id)" : book.title), isDirectory: true)
    }

    private func offlineRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("offline-books", isDirectory: true)
    }

    private func fileURL(book: BookDetail, chapter: Chapter, directory: URL) -> URL {
        let ext = Self.fileExtension(from: chapter.downloadUrl)
        let name = "\(String(format: "%03d", chapter.trackNumber))-\(FileName.sanitize(chapter.title))\(ext)"
        return directory.appendingPathComponent(name)
    }

    private static func fileExtension(from downloadURL: String) -> String {
        let path = downloadURL.split(separator: "?").first.map(String.init) ?? downloadURL
        let ext = URL(string: path)?.pathExtension ?? (path as NSString).pathExtension
        if ext.isEmpty { return ".mp3" }
        return ".\(ext.lowercased())"
    }

    private static func downloadChapter(book: BookDetail, chapter: Chapter, directory: URL, api: APIClient) async throws {
        let ext = fileExtension(from: chapter.downloadUrl)
        let name = "\(String(format: "%03d", chapter.trackNumber))-\(FileName.sanitize(chapter.title))\(ext)"
        let target = directory.appendingPathComponent(name)
        if let size = try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber, size.intValue > 0 {
            return
        }

        guard let remote = api.downloadURL(chapterID: chapter.id) else {
            throw APIError.message("Missing download URL")
        }
        let request = api.authenticatedRequest(url: remote)
        let (temp, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.status(http.statusCode, nil)
        }
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.moveItem(at: temp, to: target)
    }
}
