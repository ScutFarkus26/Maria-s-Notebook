import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct BackupDocument: FileDocument {
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

struct BackupPackageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: BackupFile.fileExtension) ?? .data] }
    static var writableContentTypes: [UTType] { [UTType(filenameExtension: BackupFile.fileExtension) ?? .data] }
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
