#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("NoteRepository Fetch Tests", .serialized)
@MainActor
struct NoteRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
            NoteStudentLink.self,
            WorkModel.self,
            WorkParticipantEntity.self,
        ])
    }

    @Test("fetchNote returns note by ID")
    func fetchNoteReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Test note content", scope: .all)
        context.insert(note)
        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNote(id: note.id)

        #expect(fetched != nil)
        #expect(fetched?.id == note.id)
        #expect(fetched?.body == "Test note content")
    }

    @Test("fetchNote returns nil for missing ID")
    func fetchNoteReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNote(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchNotes returns all when no predicate")
    func fetchNotesReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note1 = Note(body: "Note 1", scope: .all)
        let note2 = Note(body: "Note 2", scope: .all)
        let note3 = Note(body: "Note 3", scope: .all)
        context.insert(note1)
        context.insert(note2)
        context.insert(note3)
        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotes()

        #expect(fetched.count == 3)
    }

    @Test("fetchNotes sorts by createdAt descending by default")
    func fetchNotesSortsByCreatedAtDesc() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let note1 = Note(body: "Old Note", scope: .all)
        note1.createdAt = oldDate
        let note2 = Note(body: "New Note", scope: .all)
        note2.createdAt = newDate
        context.insert(note1)
        context.insert(note2)
        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotes()

        #expect(fetched[0].body == "New Note")
        #expect(fetched[1].body == "Old Note")
    }

    @Test("fetchNotesForStudent returns notes scoped to all")
    func fetchNotesForStudentReturnsAllScoped() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let note = Note(body: "Note for everyone", scope: .all)
        context.insert(note)
        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotesForStudent(studentID: studentID)

        #expect(fetched.count == 1)
        #expect(fetched[0].body == "Note for everyone")
    }

    @Test("fetchNotesForStudent returns notes scoped to specific student")
    func fetchNotesForStudentReturnsStudentScoped() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let otherStudentID = UUID()

        let note1 = Note(body: "Note for specific student", scope: .student(studentID))
        let note2 = Note(body: "Note for other student", scope: .student(otherStudentID))
        context.insert(note1)
        context.insert(note2)
        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotesForStudent(studentID: studentID)

        #expect(fetched.count == 1)
        #expect(fetched[0].body == "Note for specific student")
    }

    @Test("fetchNotes handles empty database")
    func fetchNotesHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotes()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("NoteRepository Create Tests", .serialized)
@MainActor
struct NoteRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
            NoteStudentLink.self,
            WorkModel.self,
            WorkParticipantEntity.self,
        ])
    }

    @Test("createNote creates note with required fields")
    func createNoteCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteRepository(context: context)
        let note = repository.createNote(body: "Test note content")

        #expect(note.body == "Test note content")
        #expect(note.category == .general) // Default
        #expect(note.isPinned == false) // Default
    }

    @Test("createNote sets optional fields when provided")
    func createNoteSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()

        let repository = NoteRepository(context: context)
        let note = repository.createNote(
            body: "Important observation",
            category: .behavioral,
            scope: .student(studentID),
            isPinned: true,
            includeInReport: true
        )

        #expect(note.body == "Important observation")
        #expect(note.category == .behavioral)
        #expect(note.isPinned == true)
        #expect(note.includeInReport == true)
        if case .student(let id) = note.scope {
            #expect(id == studentID)
        } else {
            Issue.record("Expected student scope")
        }
    }

    @Test("createNote persists to context")
    func createNotePersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteRepository(context: context)
        let note = repository.createNote(body: "Test note")

        let fetched = repository.fetchNote(id: note.id)

        #expect(fetched != nil)
        #expect(fetched?.id == note.id)
    }

    @Test("createNote with lesson relationship")
    func createNoteWithLessonRelationship() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math")
        context.insert(lesson)
        try context.save()

        let repository = NoteRepository(context: context)
        let note = repository.createNote(
            body: "Notes about this lesson",
            lesson: lesson
        )

        #expect(note.lesson?.id == lesson.id)
    }
}

// MARK: - Update Tests

@Suite("NoteRepository Update Tests", .serialized)
@MainActor
struct NoteRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
            NoteStudentLink.self,
            WorkModel.self,
            WorkParticipantEntity.self,
        ])
    }

    @Test("updateNote updates body")
    func updateNoteUpdatesBody() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Original content", scope: .all)
        context.insert(note)
        try context.save()

        let repository = NoteRepository(context: context)
        let result = repository.updateNote(id: note.id, body: "Updated content")

        #expect(result == true)
        #expect(note.body == "Updated content")
    }

    @Test("updateNote updates category")
    func updateNoteUpdatesCategory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Test note", scope: .all, category: .general)
        context.insert(note)
        try context.save()

        let repository = NoteRepository(context: context)
        let result = repository.updateNote(id: note.id, category: .behavioral)

        #expect(result == true)
        #expect(note.category == .behavioral)
    }

    @Test("updateNote updates isPinned")
    func updateNoteUpdatesIsPinned() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Test note", scope: .all, isPinned: false)
        context.insert(note)
        try context.save()

        let repository = NoteRepository(context: context)
        let result = repository.updateNote(id: note.id, isPinned: true)

        #expect(result == true)
        #expect(note.isPinned == true)
    }

    @Test("updateNote updates scope")
    func updateNoteUpdatesScope() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let note = Note(body: "Test note", scope: .all)
        context.insert(note)
        try context.save()

        let repository = NoteRepository(context: context)
        let result = repository.updateNote(id: note.id, scope: .student(studentID))

        #expect(result == true)
        if case .student(let id) = note.scope {
            #expect(id == studentID)
        } else {
            Issue.record("Expected student scope")
        }
    }

    @Test("updateNote updates updatedAt")
    func updateNoteUpdatesUpdatedAt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Test note", scope: .all)
        let originalUpdatedAt = note.updatedAt
        context.insert(note)
        try context.save()

        // Small delay to ensure time difference
        try await Task.sleep(for: .milliseconds(10))

        let repository = NoteRepository(context: context)
        _ = repository.updateNote(id: note.id, body: "Updated content")

        #expect(note.updatedAt > originalUpdatedAt)
    }

    @Test("updateNote returns false for missing ID")
    func updateNoteReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteRepository(context: context)
        let result = repository.updateNote(id: UUID(), body: "New content")

        #expect(result == false)
    }

    @Test("updateNote only changes specified fields")
    func updateNoteOnlyChangesSpecifiedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Original", scope: .all, isPinned: true, category: .behavioral)
        context.insert(note)
        try context.save()

        let repository = NoteRepository(context: context)
        _ = repository.updateNote(id: note.id, body: "Updated")

        #expect(note.body == "Updated")
        #expect(note.isPinned == true) // Unchanged
        #expect(note.category == .behavioral) // Unchanged
    }
}

// MARK: - Delete Tests

@Suite("NoteRepository Delete Tests", .serialized)
@MainActor
struct NoteRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
            NoteStudentLink.self,
            WorkModel.self,
            WorkParticipantEntity.self,
        ])
    }

    @Test("deleteNote removes note from context")
    func deleteNoteRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Test note", scope: .all)
        context.insert(note)
        try context.save()

        let noteID = note.id

        let repository = NoteRepository(context: context)
        try repository.deleteNote(id: noteID)

        let fetched = repository.fetchNote(id: noteID)
        #expect(fetched == nil)
    }

    @Test("deleteNote does nothing for missing ID")
    func deleteNoteDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = NoteRepository(context: context)
        try repository.deleteNote(id: UUID())

        // Should not throw - just silently does nothing
    }
}

#endif
