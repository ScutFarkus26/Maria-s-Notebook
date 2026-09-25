import Foundation

/// File storage for `CDBookClubPacket` PDFs under `Documents/Book Club Files/`.
/// A façade over one `ManagedPDFFileStorage` so call sites keep their names.
enum BookClubFileStorage {
    typealias BookClubFileError = ManagedPDFFileStorage.ImportError
    typealias ImportedPacketFile = ManagedPDFFileStorage.ImportedFile

    nonisolated static let storage = ManagedPDFFileStorage(
        folderName: "Book Club Files",
        fallbackBaseName: "BookClub",
        localFallbackWarning: "iCloud unavailable; using local Documents for book club files.",
        logger: .bookClub
    )

    static func packetFilesDirectory() throws -> URL {
        try storage.directory()
    }

    /// `packetID` is accepted for symmetry with the entity; the filename is the title alone.
    static func importPDF(
        from sourceURL: URL,
        packetID: UUID,
        title: String?
    ) throws -> ImportedPacketFile {
        try storage.importPDF(from: sourceURL, title: title, subject: "book club packets")
    }

    static func resolveURL(bookmark: Data?, relativePath: String) -> URL? {
        storage.resolveURL(bookmark: bookmark, relativePath: relativePath)
    }

    static func deleteIfManaged(_ url: URL) throws {
        try storage.deleteIfManaged(url)
    }
}
