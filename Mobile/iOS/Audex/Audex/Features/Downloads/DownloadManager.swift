import Foundation
import Observation

enum DownloadState: Equatable {
    case idle
    case downloading(downloaded: Int, total: Int)
    case completed
    case failed(String)
}

@MainActor
@Observable
final class DownloadManager {
    private let session: AppSession
    var states: [Int: DownloadState] = [:]

    init(session: AppSession) {
        self.session = session
    }

    private var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("offline-books", isDirectory: true)
    }

    func bookDirectory(for bookTitle: String, bookID: Int) -> URL {
        let folder = FileName.sanitize(bookTitle.isEmpty ? "book-\(bookID)" : bookTitle)
        return rootDirectory.appendingPathComponent(folder, isDirectory: true)
    }

    func localFileURL(for book: BookDetail, chapter: Chapter) -> URL {
        let ext = fileExtension(from: chapter.downloadUrl)
        let prefix = String(format: "%03d", chapter.trackNumber)
        let baseName = "\(prefix)-\(FileName.sanitize(chapter.title))\(ext)"
        return bookDirectory(for: book.title, bookID: book.id).appendingPathComponent(baseName)
    }

    private func fileExtension(from urlString: String) -> String {
        let clean = urlString.components(separatedBy: "?").first ?? urlString
        let ext = URL(fileURLWithPath: clean).pathExtension.lowercased()
        return ext.isEmpty ? ".mp3" : ".\(ext)"
    }

    func existingOfflineFile(for book: BookDetail, chapter: Chapter) -> URL? {
        let fileURL = localFileURL(for: book, chapter: chapter)
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path),
              let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber,
              size.int64Value > 0 else {
            return nil
        }
        return fileURL
    }

    func isBookDownloaded(_ book: BookDetail) -> Bool {
        let chapters = book.sortedChapters
        guard !chapters.isEmpty else { return false }
        return chapters.allSatisfy { existingOfflineFile(for: book, chapter: $0) != nil }
    }

    func state(for book: BookDetail) -> DownloadState {
        if let state = states[book.id] {
            return state
        }
        return isBookDownloaded(book) ? .completed : .idle
    }

    func download(book: BookDetail) async {
        let chapters = book.sortedChapters
        guard !chapters.isEmpty else { return }
        if case .downloading = states[book.id] { return }

        let total = chapters.count
        states[book.id] = .downloading(downloaded: 0, total: total)

        do {
            var completed = 0
            let api = session.api
            try await withThrowingTaskGroup(of: Void.self) { group in
                for chapter in chapters {
                    let target = localFileURL(for: book, chapter: chapter)
                    let alreadyExists = existingOfflineFile(for: book, chapter: chapter) != nil
                    let downloadURL = api.chapterDownloadURL(for: chapter)

                    group.addTask { @MainActor in
                        if !alreadyExists {
                            guard let downloadURL else {
                                throw APIError.invalidServerURL
                            }
                            try await api.downloadFile(from: downloadURL, to: target)
                        }
                    }
                }

                for try await _ in group {
                    completed += 1
                    states[book.id] = .downloading(downloaded: completed, total: total)
                }
            }
            states[book.id] = .completed
        } catch {
            states[book.id] = .failed(error.localizedDescription)
        }
    }

    func removeDownloads(for book: BookDetail) {
        let dir = bookDirectory(for: book.title, bookID: book.id)
        try? FileManager.default.removeItem(at: dir)
        states[book.id] = .idle
    }
}
