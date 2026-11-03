import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct BackupPackageDocument: FileDocument, Sendable {
    // Fix: referencing BackupFile.fileExtension caused isolation issues.
    // We can either mark BackupFile as Sendable (it's just constants) or just access the string directly.
    // Since UTType creation is lightweight, we can compute this safely.
    static var readableContentTypes: [UTType] {
        if let type = UTType(filenameExtension: BackupFile.fileExtension) {
            return [type]
        }
        return [.data]
    }
    
    static var writableContentTypes: [UTType] {
        if let type = UTType(filenameExtension: BackupFile.fileExtension) {
            return [type]
        }
        return [.data]
    }
    
    /// The backup's bytes: a finished file on disk (Back Up Now's), or bytes
    /// read in by the system.
    private enum Contents: Sendable {
        case file(URL)
        case data(Data)
    }

    private let contents: Contents

    /// A finished backup file, which the exporter copies from disk. Until
    /// 2026-11 the whole backup, photos and all, was read into memory first
    /// (bug hunt 2026-11-02 #9). The file must stay until the exporter is done.
    init(fileURL: URL) { contents = .file(fileURL) }

    init(configuration: ReadConfiguration) throws {
        guard let file = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        contents = .data(file)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        switch contents {
        case .file(let url):
            // No `.immediate`: the bytes are read as the wrapper is written out.
            try FileWrapper(url: url, options: [])
        case .data(let data):
            FileWrapper(regularFileWithContents: data)
        }
    }
}
