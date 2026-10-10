//
//  DocumentRepository.swift
//  Cosmic Daybook
//
//  Repository for CDDocument entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

struct DocumentRepository: SavingRepository {
    typealias Model = CDDocument

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDDocument by ID
    func fetchDocument(id: UUID) -> CDDocument? { fetch(id: id) }

    // MARK: - Create

    /// Create a new CDDocument backed by a file in the iCloud "Student Files" folder.
    @discardableResult
    func createDocument(
        title: String,
        category: String,
        pdfFileBookmark: Data? = nil,
        pdfFileRelativePath: String = "",
        student: CDStudent? = nil
    ) -> CDDocument {
        let document = CDDocument(context: context)
        document.title = title
        document.category = category
        document.uploadDate = Date()
        document.pdfData = nil
        document.pdfFileBookmark = pdfFileBookmark
        document.pdfFileRelativePath = pdfFileRelativePath
        document.student = student
        return document
    }

    // MARK: - Update

    /// Update an existing CDDocument's properties
    @discardableResult
    func updateDocument(
        id: UUID,
        title: String? = nil,
        category: String? = nil
    ) -> Bool {
        guard let document = fetchDocument(id: id) else { return false }

        if let title { document.title = title }
        if let category { document.category = category }

        return true
    }

    // MARK: - Delete

    /// Delete a CDDocument by ID, then its on-disk file if managed. The file
    /// goes only once the delete has saved, and only when no other record
    /// names it: it used to go first, so a failed save left the record
    /// pointing at nothing. A failed save puts the record back and throws.
    func deleteDocument(id: UUID) throws {
        guard let document = fetchDocument(id: id) else { return }
        let relativePath = document.pdfFileRelativePath
        let fileURL = StudentDocumentFileStorage.resolveURL(
            bookmark: document.pdfFileBookmark,
            relativePath: relativePath
        )
        // Only this delete is taken back on failure; the view context can
        // hold other screens' unsaved edits.
        let transaction = ContextMutationTransaction(context: context)
        context.delete(document)
        do {
            try context.save()
        } catch {
            transaction.rollback()
            throw error
        }
        transaction.commit()
        guard let fileURL, !isFileStillNamed(relativePath: relativePath) else { return }
        try? StudentDocumentFileStorage.deleteIfManaged(fileURL)
    }

    /// Whether another document (a copy sync made twice, say) still names
    /// the file at `relativePath`.
    private func isFileStillNamed(relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        let request = CDFetchRequest(CDDocument.self)
        request.predicate = NSPredicate(format: "pdfFileRelativePath == %@", relativePath)
        return ((try? context.count(for: request)) ?? 1) > 0
    }
}
