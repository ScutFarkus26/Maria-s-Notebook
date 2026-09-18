import Foundation
import OSLog

/// File storage for `CDBookClubPacket` PDFs.
/// Stores PDFs under `Documents/Book Club Files/` in the app's iCloud container,
/// mirroring the pattern used by `StoryFileStorage`.
enum BookClubFileStorage {
    private static let logger = Logger.bookClub

    enum BookClubFileError: LocalizedError {
        case sourceMissing
        case notAPDF
        case encrypted
        case copyFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .sourceMissing:
                return "Source file is missing or unreadable."
            case .notAPDF:
                return "Only PDF files can be imported as book club packets."
            case .encrypted:
                return "This PDF is encrypted and cannot be imported."
            case .copyFailed(let underlying):
                return "Failed to copy PDF: \(underlying.localizedDescription)"
            }
        }
    }

    static func packetFilesDirectory() throws -> URL {
        let fm = FileManager.default

        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            let dir = ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Book Club Files", isDirectory: true)
            try createDirectoryIfNeeded(at: dir)
            return dir
        }

        logger.warning("iCloud unavailable; using local Documents for book club files.")
        let local = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Book Club Files", isDirectory: true)
        try createDirectoryIfNeeded(at: local)
        return local
    }

    struct ImportedPacketFile {
        let url: URL
        let relativePath: String
        let bookmark: Data
    }

    static func importPDF(
        from sourceURL: URL,
        packetID: UUID,
        title: String?
    ) throws -> ImportedPacketFile {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw BookClubFileError.sourceMissing
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "pdf" else {
            throw BookClubFileError.notAPDF
        }

        let destDir = try packetFilesDirectory()

        let baseName = sanitizeFilenameComponent(title, fallback: "BookClub")

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
            throw BookClubFileError.copyFailed(underlying: error)
        }

        let relativePath = try relativePath(forManagedURL: destination)
        let bookmark = try makeBookmark(for: destination)
        _ = packetID
        return ImportedPacketFile(url: destination, relativePath: relativePath, bookmark: bookmark)
    }

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
        let base = try packetFilesDirectory()
        let basePath = base.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.replacingOccurrences(of: basePath, with: "")
    }

    static func resolve(relativePath: String) throws -> URL {
        let base = try packetFilesDirectory()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }

    static func isManagedURL(_ url: URL) -> Bool {
        do {
            let dir = try packetFilesDirectory().standardizedFileURL
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
