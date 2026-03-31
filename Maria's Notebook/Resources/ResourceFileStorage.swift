import Foundation
import OSLog

/// File storage for CDResource Library documents.
/// Stores PDFs under `Documents/CDResource Files/Category/` in the iCloud container
/// (visible in Finder), following the same pattern as `LessonFileStorage`.
enum ResourceFileStorage {
    private static let logger = Logger.resources

    // MARK: - Directory Management

    /// Returns the root directory for resource files.
    /// Uses iCloud container Documents folder if available, otherwise local Documents.
    static func resourceFilesDirectory() throws -> URL {
        let fm = FileManager.default

        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            let resourceFilesURL = ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("CDResource Files", isDirectory: true)

            try createDirectoryIfNeeded(at: resourceFilesURL)
            return resourceFilesURL
        }

        // Fallback to local Documents directory
        logger.warning("iCloud not available, using local Documents")
        let documentsURL = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("CDResource Files", isDirectory: true)
        try createDirectoryIfNeeded(at: documentsURL)
        return documentsURL
    }

    /// Returns the organizational directory for a given category.
    static func categoryDirectory(for category: ResourceCategory) throws -> URL {
        let baseDir = try resourceFilesDirectory()
        let sanitizedCategory = sanitizeFilenameComponent(category.rawValue, fallback: "Other")
        let catDir = baseDir.appendingPathComponent(sanitizedCategory, isDirectory: true)
        try createDirectoryIfNeeded(at: catDir)
        return catDir
    }

    // MARK: - File Import

    /// Imports a PDF file into the resource library under the appropriate category folder.
    /// Returns the destination URL and relative path.
    static func importFile(
        from sourceURL: URL,
        resourceID: UUID,
        title: String?,
        category: ResourceCategory
    ) throws -> (url: URL, relativePath: String) {
        let fm = FileManager.default
        let destDir = try categoryDirectory(for: category)

        let sourceExt = sourceURL.pathExtension
        let extWithDot = sourceExt.isEmpty ? ".pdf" : "." + sourceExt

        let baseName = sanitizeFilenameComponent(title, fallback: "CDResource")
        let uuidString = resourceID.uuidString.replacingOccurrences(of: "-", with: "")
        let uuidSuffix = String(uuidString.suffix(8))

        var baseFilename = "\(baseName)-\(uuidSuffix)\(extWithDot)"
        var destinationURL = destDir.appendingPathComponent(baseFilename, isDirectory: false)

        var counter = 1
        while fm.fileExists(atPath: destinationURL.path) {
            baseFilename = "\(baseName)-\(uuidSuffix)-\(counter)\(extWithDot)"
            destinationURL = destDir.appendingPathComponent(baseFilename, isDirectory: false)
            counter += 1
        }

        try fm.copyItem(at: sourceURL, to: destinationURL)
        let relPath = try relativePath(forManagedURL: destinationURL)
        return (url: destinationURL, relativePath: relPath)
    }

    // MARK: - Bookmarks & Paths

    /// Creates a bookmark for the given URL.
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Returns a relative path for a managed URL.
    static func relativePath(forManagedURL url: URL) throws -> String {
        let base = try resourceFilesDirectory()
        let basePath = base.standardizedFileURL.path + "/"
        return url.standardizedFileURL.path.replacingOccurrences(of: basePath, with: "")
    }

    /// Resolves a relative path to an absolute URL.
    static func resolve(relativePath: String) throws -> URL {
        let base = try resourceFilesDirectory()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }

    /// Returns true if the URL is inside the managed resource files directory.
    static func isManagedURL(_ url: URL) -> Bool {
        do {
            let managedDir = try resourceFilesDirectory().standardizedFileURL
            let managedPath = managedDir.path + "/"
            return url.standardizedFileURL.path.hasPrefix(managedPath)
        } catch {
            return false
        }
    }

    /// Deletes the file at the given URL if it is inside the managed directory.
    static func deleteIfManaged(_ url: URL) throws {
        let fm = FileManager.default
        guard isManagedURL(url) else { return }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    // MARK: - Private Helpers

    private static func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                try fm.removeItem(at: url)
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    private static func sanitizeFilenameComponent(_ input: String?, fallback: String) -> String {
        guard let input, !input.isEmpty else { return fallback }

        let allowedCharacterSet = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_."
        )

        var sanitized = input.unicodeScalars.map { scalar -> Character in
            if allowedCharacterSet.contains(scalar) {
                return Character(scalar)
            } else {
                return "-"
            }
        }.reduce(into: "") { $0.append($1) }

        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }

        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))
        return sanitized.isEmpty ? fallback : sanitized
    }
}
