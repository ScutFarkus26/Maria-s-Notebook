//
//  DocumentRepository.swift
//  Maria's Notebook
//
//  Repository for CDDocument entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct DocumentRepository: SavingRepository {
    typealias Model = CDDocument

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDDocument by ID
    func fetchDocument(id: UUID) -> CDDocument? { fetch(id: id) }

    /// Fetch multiple Documents with optional filtering and sorting
    func fetchDocuments(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "uploadDate", ascending: false)]
    ) -> [CDDocument] {
        let request = CDFetchRequest(CDDocument.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    /// Fetch documents for a specific student
    func fetchDocuments(forStudent student: CDStudent) -> [CDDocument] {
        let docs = student.documents
        return docs.sorted { ($0.uploadDate ?? .distantPast) > ($1.uploadDate ?? .distantPast) }
    }

    /// Fetch documents by category
    func fetchDocuments(byCategory category: String) -> [CDDocument] {
        fetchDocuments(predicate: NSPredicate(format: "category == %@", category))
    }

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

    /// Delete a CDDocument by ID. Also removes its on-disk file if managed.
    func deleteDocument(id: UUID) throws {
        guard let document = fetchDocument(id: id) else { return }
        if let url = StudentDocumentFileStorage.resolveURL(
            bookmark: document.pdfFileBookmark,
            relativePath: document.pdfFileRelativePath
        ) {
            try? StudentDocumentFileStorage.deleteIfManaged(url)
        }
        context.delete(document)
        try context.save()
    }
}
