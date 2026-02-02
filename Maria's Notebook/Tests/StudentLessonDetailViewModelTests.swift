#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Helper Factory

@MainActor
private func makeDetailContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        Student.self,
        Lesson.self,
        StudentLesson.self,
        LessonPresentation.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        WorkCheckIn.self,
        WorkPlanItem.self,
        Track.self,
        TrackStep.self,
        StudentTrackEnrollment.self,
        GroupTrack.self,
        Note.self,
    ])
}

@MainActor
private func makeTestSaveCoordinator() -> SaveCoordinator {
    let coordinator = SaveCoordinator()
    coordinator.suppressAlerts = true
    return coordinator
}

// MARK: - Initialization Tests

@Suite("StudentLessonDetailViewModel Initialization Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelInitializationTests {

    @Test("ViewModel initializes with StudentLesson values")
    func initializesWithStudentLessonValues() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let lesson = makeTestLesson(name: "Addition")
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(lesson)
        context.insert(student)

        let scheduledDate = TestCalendar.date(year: 2025, month: 3, day: 15)
        let studentLesson = makeTestStudentLesson(
            lessonID: lesson.id,
            studentIDs: [student.id],
            scheduledFor: scheduledDate,
            notes: "Test notes"
        )
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.editingLessonID == lesson.id)
        #expect(vm.scheduledFor == scheduledDate)
        #expect(vm.notes == "Test notes")
        #expect(vm.selectedStudentIDs.contains(student.id))
    }

    @Test("ViewModel initializes UI state to defaults")
    func initializesUIStateToDefaults() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.showLessonPicker == false)
        #expect(vm.showAssignmentComposer == false)
        #expect(vm.showingAddStudentSheet == false)
        #expect(vm.showingStudentPickerPopover == false)
        #expect(vm.showDeleteAlert == false)
        #expect(vm.showingMoveStudentsSheet == false)
    }

    @Test("ViewModel initializes with autoFocusLessonPicker")
    func initializesWithAutoFocusLessonPicker() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator,
            autoFocusLessonPicker: true
        )

        #expect(vm.showLessonPicker == true)
    }
}

// MARK: - Lesson Object Tests

@Suite("StudentLessonDetailViewModel Lesson Object Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelLessonObjectTests {

    @Test("lessonObject returns correct lesson from list")
    func lessonObjectReturnsCorrectLesson() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let lesson1 = makeTestLesson(name: "Addition")
        let lesson2 = makeTestLesson(name: "Subtraction")
        context.insert(lesson1)
        context.insert(lesson2)

        let studentLesson = makeTestStudentLesson(lessonID: lesson1.id)
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        let result = vm.lessonObject(from: [lesson1, lesson2])

        #expect(result?.id == lesson1.id)
        #expect(result?.name == "Addition")
    }

    @Test("lessonObject returns nil when not found")
    func lessonObjectReturnsNilWhenNotFound() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(lessonID: UUID())
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        let otherLesson = makeTestLesson(name: "Other")
        let result = vm.lessonObject(from: [otherLesson])

        #expect(result == nil)
    }
}

// MARK: - Next Lesson In Group Tests

@Suite("StudentLessonDetailViewModel Next Lesson Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelNextLessonTests {

    @Test("nextLessonInGroup returns nil when current lesson not found")
    func nextLessonInGroupReturnsNilWhenCurrentNotFound() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(lessonID: UUID())
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        let result = vm.nextLessonInGroup(from: [])

        #expect(result == nil)
    }

    @Test("nextLessonInGroup returns next lesson in same group")
    func nextLessonInGroupReturnsNextInGroup() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let lesson1 = makeTestLesson(
            name: "Addition",
            subject: "Math",
            group: "Operations",
            orderInGroup: 1
        )
        let lesson2 = makeTestLesson(
            name: "Subtraction",
            subject: "Math",
            group: "Operations",
            orderInGroup: 2
        )
        let lesson3 = makeTestLesson(
            name: "Multiplication",
            subject: "Math",
            group: "Operations",
            orderInGroup: 3
        )
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)

        let studentLesson = makeTestStudentLesson(lessonID: lesson1.id)
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        let result = vm.nextLessonInGroup(from: [lesson1, lesson2, lesson3])

        #expect(result?.id == lesson2.id)
    }
}

// MARK: - Move Students Tests

@Suite("StudentLessonDetailViewModel Move Students Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelMoveStudentsTests {

    @Test("studentsToMove is initially empty")
    func studentsToMoveIsInitiallyEmpty() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.studentsToMove.isEmpty)
    }

    @Test("movedStudentNames is initially empty")
    func movedStudentNamesIsInitiallyEmpty() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.movedStudentNames.isEmpty)
    }

    @Test("showMovedBanner is initially false")
    func showMovedBannerIsInitiallyFalse() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.showMovedBanner == false)
    }
}

// MARK: - Notes Autosave Tests

@Suite("StudentLessonDetailViewModel Notes Autosave Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelNotesAutosaveTests {

    @Test("notesDirty is initially false")
    func notesDirtyIsInitiallyFalse() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(notes: "Original notes")
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.notesDirty == false)
    }

    @Test("originalNotes stores initial notes value")
    func originalNotesStoresInitialValue() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(notes: "Original notes")
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.originalNotes == "Original notes")
    }

    @Test("Changing notes sets notesDirty to true")
    func changingNotesSetsDirtyFlag() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(notes: "Original")
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        vm.notes = "Changed notes"

        #expect(vm.notesDirty == true)
    }

    @Test("Setting notes to same value does not set dirty flag")
    func settingNotesToSameValueDoesNotSetDirty() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(notes: "Same notes")
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        vm.notes = "Same notes"

        #expect(vm.notesDirty == false)
    }

    @Test("flushNotesAutosaveIfNeeded updates model when dirty")
    func flushNotesAutosaveUpdatesModelWhenDirty() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(notes: "Original")
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        vm.notes = "Updated notes"
        vm.flushNotesAutosaveIfNeeded()

        #expect(studentLesson.notes == "Updated notes")
        #expect(vm.notesDirty == false)
        #expect(vm.originalNotes == "Updated notes")
    }

    @Test("flushNotesAutosaveIfNeeded does nothing when not dirty")
    func flushNotesAutosaveDoesNothingWhenNotDirty() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(notes: "Original")
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        vm.flushNotesAutosaveIfNeeded()

        #expect(studentLesson.notes == "Original")
    }
}

// MARK: - Mastery State Tests

@Suite("StudentLessonDetailViewModel Mastery State Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelMasteryStateTests {

    @Test("masteryState defaults to .presented")
    func masteryStateDefaultsToPresented() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.masteryState == .presented)
    }

    @Test("masteryState loads .mastered from existing LessonPresentation")
    func masteryStateLoadsMasteredFromExisting() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let student = makeTestStudent()
        let lesson = makeTestLesson()
        context.insert(student)
        context.insert(lesson)

        let studentLesson = makeTestStudentLesson(
            lessonID: lesson.id,
            studentIDs: [student.id]
        )
        context.insert(studentLesson)

        // Create mastered LessonPresentation
        let lp = LessonPresentation(
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString,
            presentationID: nil,
            state: .mastered,
            presentedAt: Date(),
            lastObservedAt: Date(),
            masteredAt: Date()
        )
        context.insert(lp)
        try context.save()

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.masteryState == .mastered)
    }

    @Test("masteryState can be changed")
    func masteryStateCanBeChanged() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        vm.masteryState = .mastered

        #expect(vm.masteryState == .mastered)

        vm.masteryState = .practicing

        #expect(vm.masteryState == .practicing)
    }
}

// MARK: - isPresented State Tests

@Suite("StudentLessonDetailViewModel isPresented State Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelIsPresentedStateTests {

    @Test("isPresented reflects StudentLesson state")
    func isPresentedReflectsStudentLessonState() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(isPresented: true)
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.isPresented == true)
    }

    @Test("isPresented can be toggled")
    func isPresentedCanBeToggled() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson(isPresented: false)
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        vm.isPresented = true

        #expect(vm.isPresented == true)
    }
}

// MARK: - needsAnotherPresentation Tests

@Suite("StudentLessonDetailViewModel needsAnotherPresentation Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelNeedsAnotherPresentationTests {

    @Test("needsAnotherPresentation reflects StudentLesson state")
    func needsAnotherPresentationReflectsState() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        studentLesson.needsAnotherPresentation = true
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.needsAnotherPresentation == true)
    }

    @Test("needsAnotherPresentation can be changed")
    func needsAnotherPresentationCanBeChanged() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        vm.needsAnotherPresentation = true

        #expect(vm.needsAnotherPresentation == true)
    }
}

// MARK: - Date Handling Tests

@Suite("StudentLessonDetailViewModel Date Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelDateTests {

    @Test("scheduledFor reflects StudentLesson state")
    func scheduledForReflectsState() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let date = TestCalendar.date(year: 2025, month: 6, day: 15)
        let studentLesson = makeTestStudentLesson(scheduledFor: date)
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.scheduledFor == date)
    }

    @Test("givenAt reflects StudentLesson state")
    func givenAtReflectsState() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let date = TestCalendar.date(year: 2025, month: 6, day: 20)
        let studentLesson = makeTestStudentLesson(givenAt: date)
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.givenAt == date)
    }

    @Test("scheduledFor can be modified")
    func scheduledForCanBeModified() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        let newDate = TestCalendar.date(year: 2025, month: 7, day: 1)
        vm.scheduledFor = newDate

        #expect(vm.scheduledFor == newDate)
    }

    @Test("givenAt can be modified")
    func givenAtCanBeModified() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let studentLesson = makeTestStudentLesson()
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        let newDate = TestCalendar.date(year: 2025, month: 7, day: 10)
        vm.givenAt = newDate

        #expect(vm.givenAt == newDate)
    }
}

// MARK: - Student Selection Tests

@Suite("StudentLessonDetailViewModel Student Selection Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelStudentSelectionTests {

    @Test("selectedStudentIDs reflects StudentLesson state")
    func selectedStudentIDsReflectsState() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let studentLesson = makeTestStudentLesson(studentIDs: [student1.id, student2.id])
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        #expect(vm.selectedStudentIDs.count == 2)
        #expect(vm.selectedStudentIDs.contains(student1.id))
        #expect(vm.selectedStudentIDs.contains(student2.id))
    }

    @Test("selectedStudentIDs can be modified")
    func selectedStudentIDsCanBeModified() throws {
        let container = try makeDetailContainer()
        let context = ModelContext(container)
        let saveCoordinator = makeTestSaveCoordinator()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student1)

        let studentLesson = makeTestStudentLesson(studentIDs: [student1.id])
        context.insert(studentLesson)

        let vm = StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator
        )

        let newStudentID = UUID()
        vm.selectedStudentIDs.insert(newStudentID)

        #expect(vm.selectedStudentIDs.count == 2)
        #expect(vm.selectedStudentIDs.contains(newStudentID))
    }
}

#endif
