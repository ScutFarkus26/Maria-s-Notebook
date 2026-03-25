//
//  DocumentRepository.swift
//  Maria's Notebook
//
//  Repository for Document entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import OSLog
import SwiftData

@MainActor
struct DocumentRepository: SavingRepository {
    typealias Model = Document

    private static let logger = Logger.database

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a Document by ID
    func fetchDocument(id: UUID) -> Document? {
        var descriptor = FetchDescriptor<Document>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch multiple Documents with optional filtering and sorting
    func fetchDocuments(
        predicate: Predicate<Document>? = nil,
        sortBy: [SortDescriptor<Document>] = [SortDescriptor(\.uploadDate, order: .reverse)]
    ) -> [Document] {
        var descriptor = FetchDescriptor<Document>()
        if let predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    /// Fetch documents for a specific student
    func fetchDocuments(forStudent student: Student) -> [Document] {
        return (student.documents ?? []).sorted { $0.uploadDate > $1.uploadDate }
    }

    /// Fetch documents by category
    func fetchDocuments(byCategory category: String) -> [Document] {
        let predicate = #Predicate<Document> { $0.category == category }
        return fetchDocuments(predicate: predicate)
    }

    // MARK: - Create

    /// Create a new Document
    /// - Parameters:
    ///   - title: Document title
    ///   - category: Document category
    ///   - pdfData: Optional PDF data
    ///   - student: Optional associated student
    /// - Returns: The created Document entity
    @discardableResult
    func createDocument(
        title: String,
        category: String,
        pdfData: Data? = nil,
        student: Student? = nil
    ) -> Document {
        let document = Document(
            title: title,
            category: category,
            uploadDate: Date(),
            pdfData: pdfData,
            student: student
        )
        context.insert(document)
        return document
    }

    // MARK: - Update

    /// Update an existing Document's properties
    /// - Parameters:
    ///   - id: The UUID of the document to update
    ///   - title: New title (optional)
    ///   - category: New category (optional)
    ///   - pdfData: New PDF data (optional)
    /// - Returns: true if update succeeded, false if document not found
    @discardableResult
    func updateDocument(
        id: UUID,
        title: String? = nil,
        category: String? = nil,
        pdfData: Data? = nil
    ) -> Bool {
        guard let document = fetchDocument(id: id) else { return false }

        if let title {
            document.title = title
        }
        if let category {
            document.category = category
        }
        if let pdfData {
            document.pdfData = pdfData
        }

        return true
    }

    // MARK: - Delete

    /// Delete a Document by ID
    func deleteDocument(id: UUID) throws {
        guard let document = fetchDocument(id: id) else { return }
        context.delete(document)
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error, privacy: .public)")
            throw error
        }
    }
}
