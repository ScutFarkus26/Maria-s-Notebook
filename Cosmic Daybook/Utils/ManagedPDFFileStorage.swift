import Foundation
import OSLog

/// One managed-document folder under `Documents/<folderName>/` in the app's iCloud
/// container, falling back to local Documents when iCloud is unavailable.
///
/// `BookClubFileStorage`, `StoryFileStorage`, `StudentDocumentFileStorage`,
/// `ResourceFileStorage` and `LessonFileStorage` are façades over one configured
/// instance each. Existing user files on disk depend on the folder name, the
/// sanitized-filename scheme, the iCloud/local fallback order and the relative-path
/// semantics, so none of those may change.
///
/// Bookmarks are plain (not security-scoped): the files live in the app's own
/// container, so they are deliberately not routed through `SecurityScopedBookmark`.
nonisolated struct ManagedPDFFileStorage: Sendable {
    /// Result of a successful import: the destination, its path relative to
    /// `directory()`, and a plain bookmark.
    struct ImportedFile {
        let url: URL
        let relativePath: String
        let bookmark: Data
    }

    enum ImportError: LocalizedError {
        case sourceMissing
        /// `subject` is the plural noun the message names ("stories").
        case notAPDF(subject: String)
        case encrypted
        case copyFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .sourceMissing:
                return "Source file is missing or unreadable."
            case .notAPDF(let subject):
                return "Only PDF files can be imported as \(subject)."
            case .encrypted:
                return "This PDF is encrypted and cannot be imported."
            case .copyFailed(let underlying):
                return "Failed to copy PDF: \(underlying.localizedDescription)"
            }
        }
    }

    /// On-disk folder name under `Documents/` ("Story Files").
    let folderName: String
    /// Filename stem used when a title sanitizes to nothing ("Story").
    let fallbackBaseName: String
    /// Logged when iCloud is unavailable and local Documents is used instead.
    let localFallbackWarning: String
    let logger: Logger

    // MARK: - Directory

    /// The managed root, created if needed: `Documents/<folderName>` in the iCloud
    /// container when it is available, otherwise in local Documents.
    func directory() throws -> URL {
        let fm = FileManager.default

        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            let dir = ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            try createDirectoryIfNeeded(at: dir)
            return dir
        }

        logger.warning("\(localFallbackWarning, privacy: .public)")
        let local = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(folderName, isDirectory: true)
        try createDirectoryIfNeeded(at: local)
        return local
    }

    /// `directory()/<sanitized component>`, created if needed.
    /// `nil` or empty maps to `fallback`.
    func subdirectory(named component: String?, fallback: String) throws -> URL {
        let folder = Self.sanitizeFilenameComponent(component, fallback: fallback)
        let url = try directory().appendingPathComponent(folder, isDirectory: true)
        try createDirectoryIfNeeded(at: url)
        return url
    }

    func createDirectoryIfNeeded(at url: URL) throws {
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

    // MARK: - Import

    /// Copies a PDF into `directory()` under `<sanitized title>.pdf` (numbered
    /// `-2`, `-3`, … on collision). `subject` names what is being imported in the
    /// `notAPDF` message.
    func importPDF(from sourceURL: URL, title: String?, subject: String) throws -> ImportedFile {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw ImportError.sourceMissing
        }
        guard sourceURL.pathExtension.lowercased() == "pdf" else {
            throw ImportError.notAPDF(subject: subject)
        }

        let destDir = try directory()
        let destination = uniqueDestination(in: destDir, baseName: sanitizedBaseName(title), extWithDot: ".pdf")
        do {
            try fm.copyItem(at: sourceURL, to: destination)
        } catch {
            throw ImportError.copyFailed(underlying: error)
        }
        return try importedFile(at: destination)
    }

    /// The sanitized filename stem for a title, or `fallbackBaseName`.
    func sanitizedBaseName(_ title: String?) -> String {
        Self.sanitizeFilenameComponent(title, fallback: fallbackBaseName)
    }

    /// `<baseName><extWithDot>` inside `directory`, or the first free
    /// `<baseName>-<n><extWithDot>` counting from 2 when that name is taken.
    func uniqueDestination(in directory: URL, baseName: String, extWithDot: String) -> URL {
        let fm = FileManager.default
        var destination = directory.appendingPathComponent(baseName + extWithDot, isDirectory: false)
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(baseName)-\(counter)\(extWithDot)", isDirectory: false)
            counter += 1
        }
        return destination
    }

    /// The relative path + bookmark pair for a file already written under `directory()`.
    func importedFile(at destination: URL) throws -> ImportedFile {
        let relativePath = try relativePath(forManagedURL: destination)
        let bookmark = try makeBookmark(for: destination)
        return ImportedFile(url: destination, relativePath: relativePath, bookmark: bookmark)
    }

    // MARK: - Resolution

    /// Resolves a stored file, preferring the bookmark and falling back to the relative path.
    func resolveURL(bookmark: Data?, relativePath: String) -> URL? {
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

    private func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        } catch {
            return nil
        }
    }

    func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func relativePath(forManagedURL url: URL) throws -> String {
        let base = try directory()
        let basePath = base.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.replacingOccurrences(of: basePath, with: "")
    }

    func resolve(relativePath: String) throws -> URL {
        let base = try directory()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }

    func isManagedURL(_ url: URL) -> Bool {
        do {
            let dir = try directory().standardizedFileURL
            return url.standardizedFileURL.path.hasPrefix(dir.path + "/")
        } catch {
            return false
        }
    }

    func deleteIfManaged(_ url: URL) throws {
        let fm = FileManager.default
        guard isManagedURL(url) else { return }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    // MARK: - Filenames

    /// Keeps ASCII letters, digits, space, `-`, `_` and `.`; every other scalar becomes
    /// `-`, runs of dashes collapse, and leading/trailing ` .-` are trimmed. Returns
    /// `fallback` when the input is nil, empty, or sanitizes to nothing.
    static func sanitizeFilenameComponent(_ input: String?, fallback: String) -> String {
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
