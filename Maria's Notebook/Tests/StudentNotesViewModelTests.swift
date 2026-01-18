#if canImport(Testing)
import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Maria_s_Notebook

// MARK: - StudentNotesViewModel Initialization Tests

@Suite("StudentNotesViewModel Initialization Tests", .serialized)
@MainActor
struct StudentNotesViewModelInitTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("init fetches notes for student")
    func initFetchesNotesForStudent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let note = Note(body: "Test note", scope: .student(student.id))
        context.insert(note)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        #expect(!vm.items.isEmpty)
    }

    @Test("init sets empty items for student with no notes")
    func initSetsEmptyItemsForNoNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        #expect(vm.items.isEmpty)
    }
}

// MARK: - StudentNotesViewModel Pagination Tests

@Suite("StudentNotesViewModel Pagination Tests", .serialized)
@MainActor
struct StudentNotesViewModelPaginationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("loadInitialPage sets displayedItemCount")
    func loadInitialPageSetsDisplayedItemCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        // Create 50 notes
        for i in 0..<50 {
            let note = Note(body: "Note \(i)", scope: .student(student.id))
            context.insert(note)
        }
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        #expect(vm.displayedItems.count <= 30) // Default page size
        #expect(vm.hasMoreItems == true)
    }

    @Test("loadMoreIfNeeded increases displayed items")
    func loadMoreIfNeededIncreasesDisplayed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        // Create 50 notes
        for i in 0..<50 {
            let note = Note(body: "Note \(i)", scope: .student(student.id))
            context.insert(note)
        }
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let initialCount = vm.displayedItems.count

        vm.loadMoreIfNeeded()

        #expect(vm.displayedItems.count > initialCount)
    }

    @Test("loadMoreIfNeeded does nothing when all items displayed")
    func loadMoreIfNeededDoesNothingWhenAllDisplayed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        // Create only 5 notes (less than page size)
        for i in 0..<5 {
            let note = Note(body: "Note \(i)", scope: .student(student.id))
            context.insert(note)
        }
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let initialCount = vm.displayedItems.count

        vm.loadMoreIfNeeded()

        #expect(vm.displayedItems.count == initialCount)
        #expect(vm.hasMoreItems == false)
    }

    @Test("hasMoreItems is false when all items displayed")
    func hasMoreItemsIsFalseWhenAllDisplayed() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        // Create only 5 notes
        for i in 0..<5 {
            let note = Note(body: "Note \(i)", scope: .student(student.id))
            context.insert(note)
        }
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        #expect(vm.hasMoreItems == false)
    }
}

// MARK: - StudentNotesViewModel Note Filtering Tests

@Suite("StudentNotesViewModel Note Filtering Tests", .serialized)
@MainActor
struct StudentNotesViewModelFilteringTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("fetchAllNotes includes notes scoped to student")
    func fetchIncludesStudentScopedNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "A")
        context.insert(student)

        let studentNote = Note(body: "Student note", scope: .student(student.id))
        context.insert(studentNote)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        #expect(vm.items.contains { $0.body == "Student note" })
    }

    @Test("fetchAllNotes includes notes scoped to all")
    func fetchIncludesAllScopedNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "A")
        context.insert(student)

        let allNote = Note(body: "All students note", scope: .all)
        context.insert(allNote)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        #expect(vm.items.contains { $0.body == "All students note" })
    }

    @Test("fetchAllNotes excludes notes scoped to other students")
    func fetchExcludesOtherStudentNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let alice = makeTestStudent(firstName: "Alice", lastName: "A")
        let bob = makeTestStudent(firstName: "Bob", lastName: "B")
        context.insert(alice)
        context.insert(bob)

        let bobNote = Note(body: "Bob's note", scope: .student(bob.id))
        context.insert(bobNote)
        try context.save()

        let vm = StudentNotesViewModel(student: alice, modelContext: context)

        #expect(!vm.items.contains { $0.body == "Bob's note" })
    }

    @Test("fetchAllNotes sorts by date descending")
    func fetchSortsByDateDescending() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let oldNote = Note(
            createdAt: TestCalendar.date(year: 2025, month: 1, day: 1),
            body: "Old note",
            scope: .student(student.id)
        )
        let newNote = Note(
            createdAt: TestCalendar.date(year: 2025, month: 6, day: 15),
            body: "New note",
            scope: .student(student.id)
        )
        context.insert(oldNote)
        context.insert(newNote)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        #expect(vm.items.count >= 2)
        // Newest should be first
        #expect(vm.items[0].date >= vm.items[1].date)
    }
}

// MARK: - StudentNotesViewModel Add Note Tests

@Suite("StudentNotesViewModel Add Note Tests", .serialized)
@MainActor
struct StudentNotesViewModelAddNoteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("addGeneralNote creates note for student")
    func addGeneralNoteCreatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        vm.addGeneralNote(body: "New general note")

        #expect(vm.items.contains { $0.body == "New general note" })
    }

    @Test("addGeneralNote trims whitespace")
    func addGeneralNoteTrimsWhitespace() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        vm.addGeneralNote(body: "  Trimmed note  \n")

        #expect(vm.items.contains { $0.body == "Trimmed note" })
    }

    @Test("addGeneralNote does not create empty note")
    func addGeneralNoteDoesNotCreateEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let initialCount = vm.items.count

        vm.addGeneralNote(body: "")

        #expect(vm.items.count == initialCount)
    }

    @Test("addGeneralNote does not create whitespace-only note")
    func addGeneralNoteDoesNotCreateWhitespaceOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let initialCount = vm.items.count

        vm.addGeneralNote(body: "   \n\t  ")

        #expect(vm.items.count == initialCount)
    }
}

// MARK: - StudentNotesViewModel Delete Tests

@Suite("StudentNotesViewModel Delete Tests", .serialized)
@MainActor
struct StudentNotesViewModelDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("delete removes item from list")
    func deleteRemovesItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let note = Note(body: "To be deleted", scope: .student(student.id))
        context.insert(note)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let itemToDelete = vm.items.first { $0.body == "To be deleted" }!

        vm.delete(item: itemToDelete)

        #expect(!vm.items.contains { $0.body == "To be deleted" })
    }
}

// MARK: - StudentNotesViewModel Batch Operations Tests

@Suite("StudentNotesViewModel Batch Operations Tests", .serialized)
@MainActor
struct StudentNotesViewModelBatchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("batchDelete removes multiple items")
    func batchDeleteRemovesMultiple() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let note1 = Note(body: "Note 1", scope: .student(student.id))
        let note2 = Note(body: "Note 2", scope: .student(student.id))
        let note3 = Note(body: "Note 3", scope: .student(student.id))
        context.insert(note1)
        context.insert(note2)
        context.insert(note3)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let idsToDelete = Set([note1.id, note2.id])

        vm.batchDelete(ids: idsToDelete)

        #expect(!vm.items.contains { $0.id == note1.id })
        #expect(!vm.items.contains { $0.id == note2.id })
        #expect(vm.items.contains { $0.id == note3.id })
    }

    @Test("batchUpdateCategory updates category for multiple items")
    func batchUpdateCategoryUpdatesMultiple() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let note1 = Note(body: "Note 1", scope: .student(student.id), category: .general)
        let note2 = Note(body: "Note 2", scope: .student(student.id), category: .general)
        context.insert(note1)
        context.insert(note2)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let idsToUpdate = Set([note1.id, note2.id])

        vm.batchUpdateCategory(.academic, for: idsToUpdate)

        // Verify notes were updated
        let updatedItems = vm.items.filter { idsToUpdate.contains($0.id) }
        #expect(updatedItems.allSatisfy { $0.category == .academic })
    }

    @Test("batchToggleReportFlag toggles flag for multiple items")
    func batchToggleReportFlagToggles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let note1 = Note(body: "Note 1", scope: .student(student.id), includeInReport: false)
        let note2 = Note(body: "Note 2", scope: .student(student.id), includeInReport: false)
        context.insert(note1)
        context.insert(note2)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let idsToToggle = Set([note1.id, note2.id])

        vm.batchToggleReportFlag(for: idsToToggle)

        // Verify flags were toggled
        let toggledItems = vm.items.filter { idsToToggle.contains($0.id) }
        #expect(toggledItems.allSatisfy { $0.includeInReport == true })
    }

    @Test("batchTogglePin toggles pin for multiple items")
    func batchTogglePinToggles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let note1 = Note(body: "Note 1", scope: .student(student.id), isPinned: false)
        let note2 = Note(body: "Note 2", scope: .student(student.id), isPinned: false)
        context.insert(note1)
        context.insert(note2)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)
        let idsToToggle = Set([note1.id, note2.id])

        vm.batchTogglePin(for: idsToToggle)

        // Verify pins were toggled
        let toggledItems = vm.items.filter { idsToToggle.contains($0.id) }
        #expect(toggledItems.allSatisfy { $0.isPinned == true })
    }
}

// MARK: - StudentNotesViewModel Note Lookup Tests

@Suite("StudentNotesViewModel Note Lookup Tests", .serialized)
@MainActor
struct StudentNotesViewModelNoteLookupTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("note by id returns note when exists")
    func noteByIdReturnsNoteWhenExists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let note = Note(body: "Find me", scope: .student(student.id))
        context.insert(note)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        let found = vm.note(by: note.id)

        #expect(found != nil)
        #expect(found?.body == "Find me")
    }

    @Test("note by id returns nil when not exists")
    func noteByIdReturnsNilWhenNotExists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let vm = StudentNotesViewModel(student: student, modelContext: context)

        let found = vm.note(by: UUID())

        #expect(found == nil)
    }
}

// MARK: - UnifiedNoteItem Tests

@Suite("UnifiedNoteItem Tests", .serialized)
struct UnifiedNoteItemTests {

    @Test("UnifiedNoteItem Source has all expected cases")
    func sourceHasAllCases() {
        // Verify cases exist
        let cases: [UnifiedNoteItem.Source] = [.general, .lesson, .work, .meeting, .presentation, .attendance]
        #expect(cases.count == 6)
    }

    @Test("UnifiedNoteItem is Identifiable")
    func isIdentifiable() {
        let item = UnifiedNoteItem(
            id: UUID(),
            date: Date(),
            body: "Test",
            source: .general,
            contextText: "Context",
            color: .blue,
            associatedID: nil,
            category: .general,
            includeInReport: false,
            imagePath: nil,
            reportedBy: nil,
            reporterName: nil,
            isPinned: false
        )

        #expect(item.id != UUID()) // Has a valid ID
    }
}

#endif
