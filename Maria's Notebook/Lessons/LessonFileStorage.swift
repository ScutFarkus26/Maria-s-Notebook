import Foundation

public enum LessonFileStorage {
    /// Returns the directory URL where lesson files are stored.
    /// Attempts to use the iCloud container if available, otherwise falls back to the app's Documents directory.
    /// Ensures the directory exists before returning.
    public static func lessonFilesDirectory() throws -> URL {
        let fm = FileManager.default

        // Attempt iCloud container first
        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            let lessonFilesURL = ubiquityURL.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Lesson Files", isDirectory: true)
            try createDirectoryIfNeeded(at: lessonFilesURL)
            return lessonFilesURL
        }

        // Fallback to local Documents directory
        let documentsURL = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Lesson Files", isDirectory: true)
        try createDirectoryIfNeeded(at: documentsURL)
        return documentsURL
    }

    /// Returns true if the given URL is inside the managed lesson files directory.
    public static func isManagedURL(_ url: URL) -> Bool {
        do {
            let managedDir = try lessonFilesDirectory().standardizedFileURL
            let standardizedURL = url.standardizedFileURL

            let managedPath = managedDir.path + "/"
            let urlPath = standardizedURL.path

            return urlPath.hasPrefix(managedPath)
        } catch {
            return false
        }
    }

    /// Deletes the item at the given URL if it is inside the managed lesson files directory.
    /// Does nothing if the URL is not managed or does not exist.
    public static func deleteIfManaged(_ url: URL) throws {
        let fm = FileManager.default
        guard isManagedURL(url) else { return }
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
    }

    /// Imports a file or package directory from a source URL into the managed lesson files directory.
    /// The destination filename is constructed from a sanitized lesson name, the lesson UUID suffix, and the source file extension.
    /// Uniqueness is ensured by appending a counter if needed.
    /// Returns the final destination URL.
    public static func importFile(from sourceURL: URL, forLessonWithID lessonID: UUID, lessonName: String?) throws -> URL {
        let fm = FileManager.default

        let destDir = try lessonFilesDirectory()

        try createDirectoryIfNeeded(at: destDir)

        // Extract file extension (including dot), if any
        let sourceExt = sourceURL.pathExtension
        let extWithDot: String
        if !sourceExt.isEmpty {
            extWithDot = "." + sourceExt
        } else {
            extWithDot = ""
        }

        // Sanitize lesson name or fallback
        let baseNameSanitized = sanitizeFilenameComponent(lessonName?.trimmed(), fallback: "Lesson")

        // UUID suffix: last 8 characters of UUID string without hyphens
        let uuidString = lessonID.uuidString.replacingOccurrences(of: "-", with: "")
        let uuidSuffix = String(uuidString.suffix(8))

        var baseFilename = "\(baseNameSanitized)-\(uuidSuffix)"
        if !extWithDot.isEmpty {
            baseFilename += extWithDot
        }

        var destinationURL = destDir.appendingPathComponent(baseFilename, isDirectory: false)

        // Ensure uniqueness by appending a counter
        var counter = 1
        while fm.fileExists(atPath: destinationURL.path) {
            let numberedBase = "\(baseNameSanitized)-\(uuidSuffix)-\(counter)"
            let filename = numberedBase + extWithDot
            destinationURL = destDir.appendingPathComponent(filename, isDirectory: false)
            counter += 1
        }

        try fm.copyItem(at: sourceURL, to: destinationURL)

        return destinationURL
    }

    /// Creates a standard bookmark Data for the given URL without security scope.
    public static func makeBookmark(for url: URL) throws -> Data {
        let bookmarkData = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        return bookmarkData
    }

    /// Returns a relative path string for a managed URL, relative to the lesson files directory.
    public static func relativePath(forManagedURL url: URL) throws -> String {
        let base = try lessonFilesDirectory()
        let rel = url.standardizedFileURL.path.replacingOccurrences(of: base.standardizedFileURL.path + "/", with: "")
        return rel
    }

    /// Resolves a relative path (previously returned by `relativePath(forManagedURL:)`) to an absolute URL inside the managed directory.
    public static func resolve(relativePath: String) throws -> URL {
        let base = try lessonFilesDirectory()
        return base.appendingPathComponent(relativePath, isDirectory: false)
    }

    // MARK: - Private Helpers

    private static func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                // Exists but is not a directory, remove it and create directory
                try fm.removeItem(at: url)
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Sanitizes a filename component by allowing only alphanumerics, space, dash, underscore, and dot.
    /// Other characters replaced with dash. Repeated dashes are collapsed.
    /// Leading/trailing dots and spaces are trimmed.
    /// Ensures the result is not empty; if so returns fallback.
    private static func sanitizeFilenameComponent(_ input: String?, fallback: String) -> String {
        guard let input = input, !input.isEmpty else {
            return fallback
        }

        // Allowed characters: alphanumeric, space, dash, underscore, dot
        // Replace disallowed characters with dash
        let allowedCharacterSet = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_." 
        )

        // Replace disallowed characters with dash
        var sanitized = input.unicodeScalars.map { scalar -> Character in
            if allowedCharacterSet.contains(scalar) {
                return Character(scalar)
            } else {
                return "-"
            }
        }.reduce(into: "") { $0.append($1) }

        // Collapse repeated dashes
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }

        // Trim leading/trailing dots and spaces and dashes
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: " .-"))

        if sanitized.isEmpty {
            return fallback
        }

        return sanitized
    }
}
