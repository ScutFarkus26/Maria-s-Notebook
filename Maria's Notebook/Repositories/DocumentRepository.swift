//
//  DocumentRepository.swift
//  Maria's Notebook
//
//  Repository for Document entity CRUD operations.
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

    /// Fetch a Document by ID
    func fetchDocument(id: UUID) -> CDDocument? {
        let request = CDFetchRequest(CDDocument.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple Documents with optional filtering and sorting
    func fetchDocuments(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "uploadDate", ascending: false)]
    ) -> [CDDocument] {
        let request = CDFetchRequest(CDDocument.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
    }

    /// Fetch documents for a specific student
    func fetchDocuments(forStudent student: CDStudent) -> [CDDocument] {
        let docs = (student.documents?.allObjects as? [CDDocument]) ?? []
        return docs.sorted { ($0.uploadDate ?? .distantPast) > ($1.uploadDate ?? .distantPast) }
    }

    /// Fetch documents by category
    func fetchDocuments(byCategory category: String) -> [CDDocument] {
        fetchDocuments(predicate: NSPredicate(format: "category == %@", category))
    }

    // MARK: - Create

    /// Create a new Document
    @discardableResult
    func createDocument(
        title: String,
        category: String,
        pdfData: Data? = nil,
        student: CDStudent? = nil
    ) -> CDDocument {
        let document = CDDocument(context: context)
        document.title = title
        document.category = category
        document.uploadDate = Date()
        document.pdfData = pdfData
        document.student = student
        return document
    }

    // MARK: - Update

    /// Update an existing Document's properties
    @discardableResult
    func updateDocument(
        id: UUID,
        title: String? = nil,
        category: String? = nil,
        pdfData: Data? = nil
    ) -> Bool {
        guard let document = fetchDocument(id: id) else { return false }

        if let title { document.title = title }
        if let category { document.category = category }
        if let pdfData { document.pdfData = pdfData }

        return true
    }

    // MARK: - Delete

    /// Delete a Document by ID
    func deleteDocument(id: UUID) throws {
        guard let document = fetchDocument(id: id) else { return }
        context.delete(document)
        try context.save()
    }
}
