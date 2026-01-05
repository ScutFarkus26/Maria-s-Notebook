import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct BackupDocument: FileDocument, Sendable {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let file = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
    }
}

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
    
    var data: Data
    
    init(data: Data) { self.data = data }
    
    init(configuration: ReadConfiguration) throws {
        guard let file = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = file
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
