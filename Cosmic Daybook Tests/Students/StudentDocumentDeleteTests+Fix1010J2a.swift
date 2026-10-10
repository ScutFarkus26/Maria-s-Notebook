import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #90: deleting a child's file removed it from disk
// before the delete was saved, so a failed save left the record pointing at
// nothing. The file now goes only once the delete has saved, and only when no
// other record names it; a failed save puts the record back.
@Suite("Deleting a child's file (Fix1010 J2a)", .serialized)
@MainActor
struct StudentDocumentDeleteFix1010J2aTests {

    /// A file in the managed Student Files folder, under a folder of this
    /// test's own, removed afterwards by the caller.
    private static func managedFile() throws -> (StudentDocumentFileStorage.ImportedStudentDocument, URL) {
        let folderName = "Fix1010 J2a \(UUID().uuidString)"
        let file = try StudentDocumentFileStorage.writePDFData(
            Data("%PDF-1.4 reading log".utf8), studentName: folderName, title: "Reading log"
        )
        return (file, try StudentDocumentFileStorage.studentDirectory(for: folderName))
    }

    private static func document(
        in context: NSManagedObjectContext, naming file: StudentDocumentFileStorage.ImportedStudentDocument
    ) -> CDDocument {
        DocumentRepository(context: context).createDocument(
            title: "Reading log", category: "Work samples", pdfFileRelativePath: file.relativePath
        )
    }

    private static func documents(in context: NSManagedObjectContext) -> [CDDocument] {
        context.safeFetch(CDFetchRequest(CDDocument.self))
    }

    @Test("A delete that saves removes the record, then the file")
    func deleteRemovesRecordThenFile() throws {
        let (file, folder) = try Self.managedFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = try CoreDataTestHelpers.makeContext()
        let document = Self.document(in: context, naming: file)
        #expect(CoreDataTestHelpers.save(context))

        try DocumentRepository(context: context).deleteDocument(id: try #require(document.id))

        #expect(Self.documents(in: context).isEmpty)
        #expect(!context.hasChanges, "the delete is saved")
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test("A delete whose save fails keeps the file and puts the record back")
    func failedSaveKeepsFileAndRecord() throws {
        let (file, folder) = try Self.managedFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentDelete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: storeFolder) }
        let storeURL = storeFolder.appendingPathComponent("Notebook.sqlite")
        let model = try CoreDataStack.sharedModel()

        // The record, saved by a notebook that can write…
        let writer = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try writer.addPersistentStore(type: .sqlite, at: storeURL)
        let writing = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        writing.persistentStoreCoordinator = writer
        let id = try #require(Self.document(in: writing, naming: file).id)
        try writing.save()

        // …then deleted where every save fails (the store opened read-only).
        let reader = NSPersistentStoreCoordinator(managedObjectModel: model)
        _ = try reader.addPersistentStore(
            type: .sqlite, at: storeURL, options: [NSReadOnlyPersistentStoreOption: true as NSNumber]
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = reader
        let unrelated = CDNote(context: context)  // another screen's unsaved edit
        unrelated.body = "half-written"

        #expect(throws: (any Error).self) {
            try DocumentRepository(context: context).deleteDocument(id: id)
        }

        #expect(FileManager.default.fileExists(atPath: file.url.path), "the file is never removed before the save")
        #expect(context.deletedObjects.isEmpty, "the record is put back")
        #expect(Self.documents(in: context).map(\.id) == [id])
        #expect(context.insertedObjects.contains(unrelated), "other unsaved edits are left alone")
    }

    @Test("A file another record still names stays when one of them is deleted")
    func sharedFileIsKept() throws {
        let (file, folder) = try Self.managedFile()
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = try CoreDataTestHelpers.makeContext()
        let first = Self.document(in: context, naming: file)
        let copy = Self.document(in: context, naming: file)  // the same file, twice (a sync duplicate)
        #expect(CoreDataTestHelpers.save(context))

        try DocumentRepository(context: context).deleteDocument(id: try #require(first.id))

        #expect(Self.documents(in: context).map(\.id) == [copy.id])
        #expect(FileManager.default.fileExists(atPath: file.url.path))
    }
}
