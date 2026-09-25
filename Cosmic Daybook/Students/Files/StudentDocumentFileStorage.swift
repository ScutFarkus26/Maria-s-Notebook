import Foundation

/// File storage for `CDDocument` PDFs (per-student documents) under
/// `Documents/Student Files/{Student Name}/`. A façade over one
/// `ManagedPDFFileStorage`; the per-student subfolder and the write-from-data
/// import are what set it apart from the other PDF libraries.
enum StudentDocumentFileStorage {
    private static let unfiledFolderName = "Unfiled"

    typealias ImportedStudentDocument = ManagedPDFFileStorage.ImportedFile

    nonisolated static let storage = ManagedPDFFileStorage(
        folderName: "Student Files",
        fallbackBaseName: "Document",
        localFallbackWarning: "iCloud unavailable; using local Documents for student files.",
        logger: .students
    )

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
    static func studentFilesDirectory() throws -> URL {
        try storage.directory()
    }

    /// Returns the folder for a given student name (creating it if needed).
    /// `nil` or empty maps to the "Unfiled" folder.
    static func studentDirectory(for studentName: String?) throws -> URL {
        try storage.subdirectory(named: studentName, fallback: unfiledFolderName)
    }

    // MARK: - Import

    /// Writes raw PDF data into the student's folder. Used during migration from the
    /// `pdfData` blob and for new imports that already have data in memory.
    static func writePDFData(
        _ data: Data,
        studentName: String?,
        title: String?
    ) throws -> ImportedStudentDocument {
        let destDir = try studentDirectory(for: studentName)
        let destination = storage.uniqueDestination(
            in: destDir,
            baseName: storage.sanitizedBaseName(title),
            extWithDot: ".pdf"
        )
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw StudentDocumentError.writeFailed(underlying: error)
        }
        return try storage.importedFile(at: destination)
    }

    // MARK: - Resolution

    /// Resolves a stored PDF to a usable URL, preferring the bookmark and falling back to the relative path.
    static func resolveURL(bookmark: Data?, relativePath: String) -> URL? {
        storage.resolveURL(bookmark: bookmark, relativePath: relativePath)
    }

    static func deleteIfManaged(_ url: URL) throws {
        try storage.deleteIfManaged(url)
    }
}
