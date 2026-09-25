import Foundation

/// File storage for CDResource Library documents under
/// `Documents/Resource Files/<Category>/` (visible in Finder). A façade over one
/// `ManagedPDFFileStorage`; the category subfolder and keeping the source file's
/// extension are what set it apart from the other PDF libraries.
enum ResourceFileStorage {
    nonisolated static let storage = ManagedPDFFileStorage(
        folderName: "Resource Files",
        fallbackBaseName: "Resource",
        localFallbackWarning: "iCloud not available, using local Documents",
        logger: .resources
    )

    // MARK: - Directory Management

    /// Returns the root directory for resource files.
    static func resourceFilesDirectory() throws -> URL {
        try storage.directory()
    }

    /// Returns the organizational directory for a given category.
    static func categoryDirectory(for category: ResourceCategory) throws -> URL {
        try storage.subdirectory(named: category.rawValue, fallback: "Other")
    }

    // MARK: - File Import

    /// Imports a file into the resource library under the appropriate category folder,
    /// keeping the source extension (`.pdf` when it has none).
    /// Returns the destination URL and relative path.
    static func importFile(
        from sourceURL: URL,
        resourceID: UUID,
        title: String?,
        category: ResourceCategory
    ) throws -> (url: URL, relativePath: String) {
        let destDir = try categoryDirectory(for: category)
        let sourceExt = sourceURL.pathExtension
        let destinationURL = storage.uniqueDestination(
            in: destDir,
            baseName: storage.sanitizedBaseName(title),
            extWithDot: sourceExt.isEmpty ? ".pdf" : "." + sourceExt
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        let relPath = try relativePath(forManagedURL: destinationURL)
        return (url: destinationURL, relativePath: relPath)
    }

    // MARK: - Bookmarks & Paths

    static func makeBookmark(for url: URL) throws -> Data {
        try storage.makeBookmark(for: url)
    }

    static func relativePath(forManagedURL url: URL) throws -> String {
        try storage.relativePath(forManagedURL: url)
    }

    static func resolve(relativePath: String) throws -> URL {
        try storage.resolve(relativePath: relativePath)
    }

    /// Returns a sanitized filename stem suitable for exported resource documents.
    static func sanitizedExportFilename(_ title: String?) -> String {
        storage.sanitizedBaseName(title)
    }
}
