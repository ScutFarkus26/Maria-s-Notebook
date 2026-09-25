import Foundation

/// File storage for `CDStory` PDFs under `Documents/Story Files/`.
/// A façade over one `ManagedPDFFileStorage` so call sites keep their names.
enum StoryFileStorage {
    typealias StoryFileError = ManagedPDFFileStorage.ImportError
    typealias ImportedStoryFile = ManagedPDFFileStorage.ImportedFile

    nonisolated static let storage = ManagedPDFFileStorage(
        folderName: "Story Files",
        fallbackBaseName: "Story",
        localFallbackWarning: "iCloud unavailable; using local Documents for story files.",
        logger: .stories
    )

    /// Returns the root directory for story PDFs.
    static func storyFilesDirectory() throws -> URL {
        try storage.directory()
    }

    /// Imports a PDF for a story, copying it into the managed directory and producing
    /// both a relative path and a bookmark. `storyID` is accepted for symmetry with
    /// the entity; the filename is the title alone.
    static func importPDF(
        from sourceURL: URL,
        storyID: UUID,
        title: String?
    ) throws -> ImportedStoryFile {
        try storage.importPDF(from: sourceURL, title: title, subject: "stories")
    }

    /// Resolves a story PDF to a usable URL, preferring the bookmark and falling back to relative path.
    static func resolveURL(bookmark: Data?, relativePath: String) -> URL? {
        storage.resolveURL(bookmark: bookmark, relativePath: relativePath)
    }

    static func deleteIfManaged(_ url: URL) throws {
        try storage.deleteIfManaged(url)
    }
}
