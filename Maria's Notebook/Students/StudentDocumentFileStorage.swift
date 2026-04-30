import Foundation
import OSLog

/// File storage for `CDDocument` PDFs (per-student documents).
/// Stores PDFs under `Documents/Student Files/{Student Name}/` in the iCloud container,
/// mirroring the pattern used by `StoryFileStorage`.
enum StudentDocumentFileStorage {
    private static let logger = Logger.students
    private static let unfiledFolderName = "Unfiled"

    enum StudentDocumentError: LocalizedError {
        case sourceMissing
        case writeFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .sourceMissing:
                return "Source file is missing or unreadable."
            case .writeFailed(let underlying):
                return "Failed to write document: \(underlying.localizedDescription)"
            }
        }
    }

    // MARK: - Directory Management

    /// Returns the root directory for student document PDFs.
    /// Uses the iCloud container if available, otherwise local Documents.
    static func studentFilesDirectory() throws -> URL {
        let fm = FileManager.default

        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            let dir = ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Student Files", isDirectory: true)
            try createDirectoryIfNeeded(at: dir)
            return dir
        }

        logger.warning("iCloud unavailable; using local Documents for student files.")
        let local = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Student Files", isDirectory: true)
        try createDirectoryIfNeeded(at: local)
        return local
    }

    /// Returns the folder for a given student name (creating it if needed).
    /// `nil` or empty maps to the "Unfiled" folder.
    static func studentDirectory(for studentName: String?) throws -> URL {
        let folder = sanitizeFilenameComponent(studentName, fallback: unfiledFolderName)
        let url = try studentFilesDirectory().appendingPathComponent(folder, isDirectory: true)
        try createDirectoryIfNeeded(at: url)
        return url
    }

    // MARK: - Import

    struct ImportedStudentDocument {
        let url: URL
        let relativePath: String
        let bookmark: Data
    }

    /// Writes raw PDF data into the student's folder. Used during migration from the
    /// `pdfData` blob and for new imports that already have data in memory.
    static func writePDFData(
        _ data: Data,
        studentName: String?,
        title: String?
    ) throws -> ImportedStudentDocument {
        let destDir = try studentDirectory(for: studentName)
        let baseName = sanitizeFilenameComponent(title, fallback: "Document")

        var filename = "\(baseName).pdf"
        var destination = destDir.appendingPathComponent(filename, isDirectory: false)
        let fm = FileManager.default
        var counter = 2
        while fm.fileExists(atPath: destination.path) {
            filename = "\(baseName)-\(counter).pdf"
            destination = destDir.appendingPathComponent(filename, isDirectory: false)
            counter += 1
        }

        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw StudentDocumentError.writeFailed(underlying: error)
        }

        let relativePath = try relativePath(forManagedURL: destination)
        let bookmark = try makeBookmark(for: destination)
        return ImportedStudentDocument(url: destination, relativePath: relativePath, bookmark: bookmark)
    }

    /// Imports a PDF from a source URL into the student's folder.
    static func importPDF(
        from sourceURL: URL,
        studentName: String?,
        title: String?
    ) throws -> ImportedStudentDocument {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw StudentDocumentError.sourceMissing
        }
        let data = try Data(contentsOf: sourceURL)
        return try writePDFData(data, studentName: studentName, title: title)
    }

    // MARK: - Resolution

    /// Resolves a stored PDF to a usable URL, preferring the bookmark and falling back to the relative path.
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
        let base = try studentFilesDirectory()
        let basePath = base.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.replacingOccurrences(of: basePath, with: "")
    }

    static func resolve(relativePath: String) throws -> URL {
        let base = try studentFilesDirectory()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }

    static func isManagedURL(_ url: URL) -> Bool {
        do {
            let dir = try studentFilesDirectory().standardizedFileURL
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
