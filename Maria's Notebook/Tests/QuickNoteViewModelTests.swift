#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - QuickNoteViewModel Initialization Tests

@Suite("QuickNoteViewModel Initialization Tests", .serialized)
@MainActor
struct QuickNoteViewModelInitTests {

    @Test("init with no initial student starts empty")
    func initWithNoInitialStudentStartsEmpty() {
        let vm = QuickNoteViewModel()

        #expect(vm.bodyText == "")
        #expect(vm.category == .general)
        #expect(vm.selectedStudentIDs.isEmpty)
        #expect(vm.includeInReport == false)
        #expect(vm.initialStudentID == nil)
    }

    @Test("init with initial student pre-selects student")
    func initWithInitialStudentPreSelects() {
        let studentID = UUID()
        let vm = QuickNoteViewModel(initialStudentID: studentID)

        #expect(vm.selectedStudentIDs.contains(studentID))
        #expect(vm.initialStudentID == studentID)
    }

    @Test("init defaults to current date for noteDate")
    func initDefaultsToCurrentDate() {
        let vm = QuickNoteViewModel()

        // Should be close to now
        let diff = abs(vm.noteDate.timeIntervalSinceNow)
        #expect(diff < 60) // Within 1 minute
    }

    @Test("init sets attachedImage to nil")
    func initSetsAttachedImageToNil() {
        let vm = QuickNoteViewModel()

        #expect(vm.attachedImage == nil)
        #expect(vm.attachedImagePath == nil)
    }

    @Test("init sets AI state to idle")
    func initSetsAIStateToIdle() {
        let vm = QuickNoteViewModel()

        #expect(vm.isProcessingAI == false)
        #expect(vm.aiError == nil)
    }

    @Test("init sets UI state to not showing pickers")
    func initSetsUIStateToNotShowingPickers() {
        let vm = QuickNoteViewModel()

        #expect(vm.isShowingStudentPicker == false)
        #expect(vm.isShowingCamera == false)
    }
}

// MARK: - QuickNoteViewModel Setup Tests

@Suite("QuickNoteViewModel Setup Tests", .serialized)
@MainActor
struct QuickNoteViewModelSetupTests {

    @Test("setupInitialState adds initial student when provided")
    func setupInitialStateAddsInitialStudent() {
        let studentID = UUID()
        let vm = QuickNoteViewModel(initialStudentID: studentID)
        vm.selectedStudentIDs.removeAll() // Clear it first

        vm.setupInitialState()

        #expect(vm.selectedStudentIDs.contains(studentID))
    }

    @Test("setupInitialState does nothing when no initial student")
    func setupInitialStateDoesNothingWhenNoInitialStudent() {
        let vm = QuickNoteViewModel()

        vm.setupInitialState()

        #expect(vm.selectedStudentIDs.isEmpty)
    }
}

// MARK: - QuickNoteViewModel Category Tests

@Suite("QuickNoteViewModel Category Tests", .serialized)
@MainActor
struct QuickNoteViewModelCategoryTests {

    @Test("category can be set to academic")
    func categoryCanBeSetToAcademic() {
        let vm = QuickNoteViewModel()

        vm.category = .academic

        #expect(vm.category == .academic)
    }

    @Test("category can be set to behavioral")
    func categoryCanBeSetToBehavioral() {
        let vm = QuickNoteViewModel()

        vm.category = .behavioral

        #expect(vm.category == .behavioral)
    }

    @Test("category can be set to social")
    func categoryCanBeSetToSocial() {
        let vm = QuickNoteViewModel()

        vm.category = .social

        #expect(vm.category == .social)
    }

    @Test("categoryColor returns different colors for different categories")
    func categoryColorReturnsDifferentColors() {
        let vm = QuickNoteViewModel()

        let academicColor = vm.categoryColor(.academic)
        let behavioralColor = vm.categoryColor(.behavioral)
        let socialColor = vm.categoryColor(.social)
        let generalColor = vm.categoryColor(.general)

        // Colors should all be different
        #expect(academicColor != behavioralColor)
        #expect(academicColor != socialColor)
        #expect(academicColor != generalColor)
    }
}

// MARK: - QuickNoteViewModel Student Display Tests

@Suite("QuickNoteViewModel Student Display Tests", .serialized)
@MainActor
struct QuickNoteViewModelStudentDisplayTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Student.self])
    }

    @Test("getDisplayName returns first name when unique")
    func getDisplayNameReturnsFirstNameWhenUnique() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let alice = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let bob = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(alice)
        context.insert(bob)
        try context.save()

        let vm = QuickNoteViewModel()
        let displayName = vm.getDisplayName(for: alice, students: [alice, bob])

        #expect(displayName == "Alice")
    }

    @Test("getDisplayName returns first name and last initial when duplicates")
    func getDisplayNameReturnsInitialWhenDuplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let alice1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let alice2 = makeTestStudent(firstName: "Alice", lastName: "Baker")
        context.insert(alice1)
        context.insert(alice2)
        try context.save()

        let vm = QuickNoteViewModel()
        let displayName1 = vm.getDisplayName(for: alice1, students: [alice1, alice2])
        let displayName2 = vm.getDisplayName(for: alice2, students: [alice1, alice2])

        #expect(displayName1 == "Alice A.")
        #expect(displayName2 == "Alice B.")
    }

    @Test("getDisplayName handles empty last name")
    func getDisplayNameHandlesEmptyLastName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let alice1 = Student(firstName: "Alice", lastName: "", birthday: Date())
        let alice2 = Student(firstName: "Alice", lastName: "Baker", birthday: Date())
        context.insert(alice1)
        context.insert(alice2)
        try context.save()

        let vm = QuickNoteViewModel()
        let displayName = vm.getDisplayName(for: alice1, students: [alice1, alice2])

        #expect(displayName == "Alice .")
    }

    @Test("getDisplayName is case insensitive for duplicate detection")
    func getDisplayNameIsCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let alice1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let alice2 = makeTestStudent(firstName: "ALICE", lastName: "Baker")
        context.insert(alice1)
        context.insert(alice2)
        try context.save()

        let vm = QuickNoteViewModel()
        let displayName1 = vm.getDisplayName(for: alice1, students: [alice1, alice2])
        let displayName2 = vm.getDisplayName(for: alice2, students: [alice1, alice2])

        #expect(displayName1 == "Alice A.")
        #expect(displayName2 == "ALICE B.")
    }
}

// MARK: - QuickNoteViewModel Save Tests

@Suite("QuickNoteViewModel Save Tests", .serialized)
@MainActor
struct QuickNoteViewModelSaveTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Note.self,
            NoteStudentLink.self,
            StudentTrackEnrollment.self,
            GroupTrack.self,
        ])
    }

    @Test("saveNote does not save empty body")
    func saveNoteDoesNotSaveEmptyBody() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = QuickNoteViewModel()
        vm.bodyText = ""

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        #expect(notes.isEmpty)
    }

    @Test("saveNote does not save whitespace-only body")
    func saveNoteDoesNotSaveWhitespaceBody() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = QuickNoteViewModel()
        vm.bodyText = "   \n\t  "

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        #expect(notes.isEmpty)
    }

    @Test("saveNote saves note with body text")
    func saveNoteSavesNoteWithBody() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = QuickNoteViewModel()
        vm.bodyText = "Test observation text"
        vm.category = .academic

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        #expect(notes.count == 1)
        #expect(notes.first?.body == "Test observation text")
        #expect(notes.first?.category == .academic)
    }

    @Test("saveNote trims whitespace from body")
    func saveNoteTrimsBody() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = QuickNoteViewModel()
        vm.bodyText = "  Test text  \n"

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        #expect(notes.first?.body == "Test text")
    }

    @Test("saveNote uses scope all when no students selected")
    func saveNoteUsesScopeAllWhenNoStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = QuickNoteViewModel()
        vm.bodyText = "General note"
        vm.selectedStudentIDs = []

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        #expect(notes.first?.scope == .all)
    }

    @Test("saveNote uses student scope when one student selected")
    func saveNoteUsesStudentScopeWhenOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let vm = QuickNoteViewModel()
        vm.bodyText = "Student note"
        vm.selectedStudentIDs = [student.id]

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        #expect(notes.first?.scope == .student(student.id))
    }

    @Test("saveNote uses students scope when multiple students selected")
    func saveNoteUsesStudentsScopeWhenMultiple() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "A")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "B")
        context.insert(student1)
        context.insert(student2)
        try context.save()

        let vm = QuickNoteViewModel()
        vm.bodyText = "Multi-student note"
        vm.selectedStudentIDs = [student1.id, student2.id]

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        // Should be students scope with sorted IDs
        if case .students(let ids) = notes.first?.scope {
            #expect(ids.count == 2)
            #expect(ids.contains(student1.id))
            #expect(ids.contains(student2.id))
        } else {
            #expect(Bool(false), "Expected students scope")
        }
    }

    @Test("saveNote sets includeInReport flag")
    func saveNoteSetsIncludeInReport() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = QuickNoteViewModel()
        vm.bodyText = "Important note"
        vm.includeInReport = true

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        #expect(notes.first?.includeInReport == true)
    }

    @Test("saveNote sets noteDate")
    func saveNoteSetsNoteDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let specificDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let vm = QuickNoteViewModel()
        vm.bodyText = "Dated note"
        vm.noteDate = specificDate

        vm.saveNote(modelContext: context)

        let descriptor = FetchDescriptor<Note>()
        let notes = try context.fetch(descriptor)

        #expect(Calendar.current.isDate(notes.first!.createdAt, inSameDayAs: specificDate))
    }
}

// MARK: - QuickNoteViewModel Detected Candidates Tests

@Suite("QuickNoteViewModel Detected Candidates Tests", .serialized)
@MainActor
struct QuickNoteViewModelDetectedCandidatesTests {

    @Test("detectedCandidateIDs starts empty")
    func detectedCandidatesStartsEmpty() {
        let vm = QuickNoteViewModel()

        #expect(vm.detectedCandidateIDs.isEmpty)
    }

    @Test("detectedCandidateIDs can be modified")
    func detectedCandidatesCanBeModified() {
        let vm = QuickNoteViewModel()
        let candidateID = UUID()

        vm.detectedCandidateIDs.insert(candidateID)

        #expect(vm.detectedCandidateIDs.contains(candidateID))
    }
}

// MARK: - QuickNoteViewModel Track Context Tests

@Suite("QuickNoteViewModel Track Context Tests", .serialized)
@MainActor
struct QuickNoteViewModelTrackContextTests {

    @Test("selectedEnrollmentID starts nil")
    func selectedEnrollmentIDStartsNil() {
        let vm = QuickNoteViewModel()

        #expect(vm.selectedEnrollmentID == nil)
    }

    @Test("selectedEnrollmentID can be set")
    func selectedEnrollmentIDCanBeSet() {
        let vm = QuickNoteViewModel()
        let enrollmentID = UUID()

        vm.selectedEnrollmentID = enrollmentID

        #expect(vm.selectedEnrollmentID == enrollmentID)
    }
}

#endif
