import Foundation

/// The Resources screen's file folders, one `ManagedPDFFileStorage` each:
/// stories under `Documents/Story Files/`, book club packets under
/// `Documents/Book Club Files/`, and resource files under
/// `Documents/Resource Files/<Category>/` (visible in Finder). Book Club left
/// the app on 2026-11-21; its folder is left on disk as it is, and still named
/// here so the folder tests and the container cache know it.
///
/// Stored files are found by these folder names (and the filename scheme in
/// `ManagedPDFFileStorage`), so none of them may change: they are the names
/// the old `StoryFileStorage`, `BookClubFileStorage` and `ResourceFileStorage`
/// used. Each function takes the folder as a parameter so tests can point it
/// at a container of their own.
enum LibraryFileStorage {
    nonisolated static let stories = ManagedPDFFileStorage(
        folderName: "Story Files",
        fallbackBaseName: "Story",
        localFallbackWarning: "iCloud unavailable; using local Documents for story files.",
        logger: .stories
    )

    nonisolated static let packets = ManagedPDFFileStorage(
        folderName: "Book Club Files",
        fallbackBaseName: "BookClub",
        localFallbackWarning: "iCloud unavailable; using local Documents for book club files.",
        logger: .bookClub
    )

    nonisolated static let resources = ManagedPDFFileStorage(
        folderName: "Resource Files",
        fallbackBaseName: "Resource",
        localFallbackWarning: "iCloud not available, using local Documents",
        logger: .resources
    )

    // MARK: - Stories

    /// Where a story's PDF is, preferring its bookmark and falling back to its
    /// relative path; nil when it can't be found.
    static func url(for story: CDStory, in storage: ManagedPDFFileStorage = stories) -> URL? {
        storage.resolveURL(bookmark: story.pdfFileBookmark, relativePath: story.pdfFileRelativePath)
    }

    /// Removes a story's PDF when it lives in the story folder.
    static func deleteFile(of story: CDStory) {
        guard let url = url(for: story) else { return }
        try? stories.deleteIfManaged(url)
    }

    // MARK: - Resource files

    /// Copies a file into `Resource Files/<category>/`, keeping the source
    /// extension (`.pdf` when it has none), under a numbered name when the
    /// title's is taken.
    static func importResourceFile(
        from sourceURL: URL,
        title: String?,
        category: ResourceCategory,
        in storage: ManagedPDFFileStorage = resources
    ) throws -> (url: URL, relativePath: String) {
        let destDir = try storage.subdirectory(named: category.rawValue, fallback: "Other")
        let sourceExt = sourceURL.pathExtension
        let destinationURL = storage.uniqueDestination(
            in: destDir,
            baseName: storage.sanitizedBaseName(title),
            extWithDot: sourceExt.isEmpty ? ".pdf" : "." + sourceExt
        )
        try UbiquitousFile.coordinatedCopy(from: sourceURL, to: destinationURL)
        return (destinationURL, try storage.relativePath(forManagedURL: destinationURL))
    }

    /// The resource file stored at `relativePath`, whether or not it is there.
    static func resolveResource(relativePath: String) throws -> URL {
        try resources.resolve(relativePath: relativePath)
    }

    /// Where a resource stored at `relativePath` is kept: the managed folder
    /// plus the path, whether or not the file is there; nil for an empty path
    /// or a folder that can't be made. What the resource detail draws its
    /// Share and Print items from.
    static func resourceFileURL(relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }
        return try? resolveResource(relativePath: relativePath)
    }

    /// A sanitized filename stem for an exported resource document.
    static func sanitizedExportFilename(_ title: String?) -> String {
        resources.sanitizedBaseName(title)
    }
}
