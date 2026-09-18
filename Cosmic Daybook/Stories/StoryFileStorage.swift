import Foundation
import OSLog

/// File storage for `CDStory` PDFs.
/// Stores PDFs under `Documents/Story Files/` in the app's iCloud container,
/// mirroring the pattern used by `LessonFileStorage` and `ResourceFileStorage`.
enum StoryFileStorage {
    private static let logger = Logger.stories

    enum StoryFileError: LocalizedError {
        case sourceMissing
        case notAPDF
        case encrypted
        case copyFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .sourceMissing:
                return "Source file is missing or unreadable."
            case .notAPDF:
                return "Only PDF files can be imported as stories."
            case .encrypted:
                return "This PDF is encrypted and cannot be imported."
            case .copyFailed(let underlying):
                return "Failed to copy PDF: \(underlying.localizedDescription)"
            }
        }
    }

    // MARK: - Directory Management

    /// Returns the root directory for story PDFs.
    /// Uses the iCloud container if available, otherwise local Documents.
    static func storyFilesDirectory() throws -> URL {
        let fm = FileManager.default

        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            let dir = ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Story Files", isDirectory: true)
            try createDirectoryIfNeeded(at: dir)
            return dir
        }

        logger.warning("iCloud unavailable; using local Documents for story files.")
        let local = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Story Files", isDirectory: true)
        try createDirectoryIfNeeded(at: local)
        return local
    }

    // MARK: - Import

    /// Result of a successful PDF import.
    struct ImportedStoryFile {
        let url: URL
        let relativePath: String
        let bookmark: Data
    }

    /// Imports a PDF for a story, copying it into the managed directory and producing
    /// both a relative path and a bookmark.
    /// - Parameters:
    ///   - sourceURL: The PDF to import.
    ///   - storyID: The story's UUID (used for filename suffix).
    ///   - title: Optional sanitized title to use in the filename.
    static func importPDF(
        from sourceURL: URL,
        storyID: UUID,
        title: String?
    ) throws -> ImportedStoryFile {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw StoryFileError.sourceMissing
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "pdf" else {
            throw StoryFileError.notAPDF
        }

        let destDir = try storyFilesDirectory()

        let baseName = sanitizeFilenameComponent(title, fallback: "Story")

        var filename = "\(baseName).pdf"
        var destination = destDir.appendingPathComponent(filename, isDirectory: false)
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            filename = "\(baseName)-\(counter).pdf"
            destination = destDir.appendingPathComponent(filename, isDirectory: false)
            counter += 1
        }

        do {
            try fm.copyItem(at: sourceURL, to: destination)
        } catch {
            throw StoryFileError.copyFailed(underlying: error)
        }

        let relativePath = try relativePath(forManagedURL: destination)
        let bookmark = try makeBookmark(for: destination)
        return ImportedStoryFile(url: destination, relativePath: relativePath, bookmark: bookmark)
    }

    // MARK: - Resolution

    /// Resolves a story PDF to a usable URL, preferring the bookmark and falling back to relative path.
    static func resolveURL(bookmark: Data?, relativePath: String) -> URL? {
        if let bookmark, let url = resolveBookmark(bookmark) {
            return url
        }
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let url = try resolve(relativePath: trimmed)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            logger.warning("Failed to resolve relative path \(trimmed): \(error.localizedDescription)")
            return nil
        }
    }

    private static func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            return nil
        }
    }

    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func relativePath(forManagedURL url: URL) throws -> String {
        let base = try storyFilesDirectory()
        let basePath = base.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.replacingOccurrences(of: basePath, with: "")
    }

    static func resolve(relativePath: String) throws -> URL {
        let base = try storyFilesDirectory()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }

    static func isManagedURL(_ url: URL) -> Bool {
        do {
            let dir = try storyFilesDirectory().standardizedFileURL
            return url.standardizedFileURL.path.hasPrefix(dir.path + "/")
        } catch {
            return false
        }
    }

    static func deleteIfManaged(_ url: URL) throws {
        let fm = FileManager.default
        guard isManagedURL(url) else { return }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    // MARK: - Private

    private static func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                try fm.removeItem(at: url)
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func sanitizeFilenameComponent(_ input: String?, fallback: String) -> String {
        guard let input, !input.isEmpty else { return fallback }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_."
        )
        var sanitized = input.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }.reduce(into: "") { $0.append($1) }
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return sanitized.isEmpty ? fallback : sanitized
    }
}
