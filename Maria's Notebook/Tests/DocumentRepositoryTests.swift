#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("DocumentRepository Fetch Tests", .serialized)
@MainActor
struct DocumentRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Document.self,
        ])
    }

    @Test("fetchDocument returns document by ID")
    func fetchDocumentReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let document = Document(title: "Test Document", category: "Report")
        context.insert(document)
        try context.save()

        let repository = DocumentRepository(context: context)
        let fetched = repository.fetchDocument(id: document.id)

        #expect(fetched != nil)
        #expect(fetched?.id == document.id)
        #expect(fetched?.title == "Test Document")
    }

    @Test("fetchDocument returns nil for missing ID")
    func fetchDocumentReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = DocumentRepository(context: context)
        let fetched = repository.fetchDocument(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchDocuments returns all when no predicate")
    func fetchDocumentsReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let document1 = Document(title: "Document 1", category: "Report")
        let document2 = Document(title: "Document 2", category: "Certificate")
        let document3 = Document(title: "Document 3", category: "Report")
        context.insert(document1)
        context.insert(document2)
        context.insert(document3)
        try context.save()

        let repository = DocumentRepository(context: context)
        let fetched = repository.fetchDocuments()

        #expect(fetched.count == 3)
    }

    @Test("fetchDocuments sorts by uploadDate descending by default")
    func fetchDocumentsSortsByUploadDateDesc() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let document1 = Document(title: "Old Document", category: "Report", uploadDate: oldDate)
        let document2 = Document(title: "New Document", category: "Report", uploadDate: newDate)
        context.insert(document1)
        context.insert(document2)
        try context.save()

        let repository = DocumentRepository(context: context)
        let fetched = repository.fetchDocuments()

        #expect(fetched[0].title == "New Document")
        #expect(fetched[1].title == "Old Document")
    }

    @Test("fetchDocuments byCategory filters correctly")
    func fetchDocumentsByCategoryFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let document1 = Document(title: "Report 1", category: "Report")
        let document2 = Document(title: "Certificate 1", category: "Certificate")
        let document3 = Document(title: "Report 2", category: "Report")
        context.insert(document1)
        context.insert(document2)
        context.insert(document3)
        try context.save()

        let repository = DocumentRepository(context: context)
        let fetched = repository.fetchDocuments(byCategory: "Report")

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.category == "Report" })
    }

    @Test("fetchDocuments forStudent returns student documents")
    func fetchDocumentsForStudentReturnsStudentDocuments() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)

        let document1 = Document(title: "Student Doc", category: "Report", student: student)
        let document2 = Document(title: "Other Doc", category: "Report")
        context.insert(document1)
        context.insert(document2)
        try context.save()

        let repository = DocumentRepository(context: context)
        let fetched = repository.fetchDocuments(forStudent: student)

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Student Doc")
    }

    @Test("fetchDocuments handles empty database")
    func fetchDocumentsHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = DocumentRepository(context: context)
        let fetched = repository.fetchDocuments()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("DocumentRepository Create Tests", .serialized)
@MainActor
struct DocumentRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Document.self,
        ])
    }

    @Test("createDocument creates document with required fields")
    func createDocumentCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = DocumentRepository(context: context)
        let document = repository.createDocument(title: "Test Document", category: "Report")

        #expect(document.title == "Test Document")
        #expect(document.category == "Report")
    }

    @Test("createDocument sets optional fields when provided")
    func createDocumentSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)

        let pdfData = "Test PDF Content".data(using: .utf8)!

        let repository = DocumentRepository(context: context)
        let document = repository.createDocument(
            title: "Progress Report",
            category: "Report",
            pdfData: pdfData,
            student: student
        )

        #expect(document.pdfData == pdfData)
        #expect(document.student?.id == student.id)
    }

    @Test("createDocument sets uploadDate to current date")
    func createDocumentSetsUploadDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let beforeCreate = Date()

        let repository = DocumentRepository(context: context)
        let document = repository.createDocument(title: "Test", category: "Report")

        let afterCreate = Date()

        #expect(document.uploadDate >= beforeCreate)
        #expect(document.uploadDate <= afterCreate)
    }

    @Test("createDocument persists to context")
    func createDocumentPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = DocumentRepository(context: context)
        let document = repository.createDocument(title: "Test", category: "Report")

        let fetched = repository.fetchDocument(id: document.id)

        #expect(fetched != nil)
        #expect(fetched?.id == document.id)
    }
}

// MARK: - Update Tests

@Suite("DocumentRepository Update Tests", .serialized)
@MainActor
struct DocumentRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Document.self,
        ])
    }

    @Test("updateDocument updates title")
    func updateDocumentUpdatesTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let document = Document(title: "Original Title", category: "Report")
        context.insert(document)
        try context.save()

        let repository = DocumentRepository(context: context)
        let result = repository.updateDocument(id: document.id, title: "Updated Title")

        #expect(result == true)
        #expect(document.title == "Updated Title")
    }

    @Test("updateDocument updates category")
    func updateDocumentUpdatesCategory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let document = Document(title: "Test", category: "Report")
        context.insert(document)
        try context.save()

        let repository = DocumentRepository(context: context)
        let result = repository.updateDocument(id: document.id, category: "Certificate")

        #expect(result == true)
        #expect(document.category == "Certificate")
    }

    @Test("updateDocument updates pdfData")
    func updateDocumentUpdatesPdfData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let document = Document(title: "Test", category: "Report")
        context.insert(document)
        try context.save()

        let newPdfData = "New PDF Content".data(using: .utf8)!

        let repository = DocumentRepository(context: context)
        let result = repository.updateDocument(id: document.id, pdfData: newPdfData)

        #expect(result == true)
        #expect(document.pdfData == newPdfData)
    }

    @Test("updateDocument returns false for missing ID")
    func updateDocumentReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = DocumentRepository(context: context)
        let result = repository.updateDocument(id: UUID(), title: "New Title")

        #expect(result == false)
    }

    @Test("updateDocument only changes specified fields")
    func updateDocumentOnlyChangesSpecifiedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let document = Document(title: "Original", category: "Report")
        context.insert(document)
        try context.save()

        let repository = DocumentRepository(context: context)
        _ = repository.updateDocument(id: document.id, title: "Updated")

        #expect(document.title == "Updated")
        #expect(document.category == "Report") // Unchanged
    }
}

// MARK: - Delete Tests

@Suite("DocumentRepository Delete Tests", .serialized)
@MainActor
struct DocumentRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Document.self,
        ])
    }

    @Test("deleteDocument removes document from context")
    func deleteDocumentRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let document = Document(title: "Test", category: "Report")
        context.insert(document)
        try context.save()

        let documentID = document.id

        let repository = DocumentRepository(context: context)
        try repository.deleteDocument(id: documentID)

        let fetched = repository.fetchDocument(id: documentID)
        #expect(fetched == nil)
    }

    @Test("deleteDocument does nothing for missing ID")
    func deleteDocumentDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = DocumentRepository(context: context)
        try repository.deleteDocument(id: UUID())

        // Should not throw
    }
}

#endif
