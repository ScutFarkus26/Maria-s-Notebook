#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Test Context Setup

@MainActor
private struct ViewModelTestContext {
    let container: ModelContainer
    let context: ModelContext
    let saveCoordinator: SaveCoordinator

    static func make() throws -> ViewModelTestContext {
        let container = try makeTestContainer(for: [
            Student.self, Lesson.self, StudentLesson.self, LessonPresentation.self,
            WorkModel.self, WorkParticipantEntity.self, WorkCheckIn.self,
            Track.self, TrackStep.self, StudentTrackEnrollment.self,
            GroupTrack.self, Note.self,
        ])
        let context = ModelContext(container)
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        return ViewModelTestContext(container: container, context: context, saveCoordinator: coordinator)
    }

    func makeViewModel(for studentLesson: StudentLesson, autoFocusLessonPicker: Bool = false) -> StudentLessonDetailViewModel {
        return StudentLessonDetailViewModel(
            studentLesson: studentLesson,
            modelContext: context,
            saveCoordinator: saveCoordinator,
            autoFocusLessonPicker: autoFocusLessonPicker
        )
    }
}

// MARK: - Initialization Tests

@Suite("StudentLessonDetailViewModel Initialization Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelInitializationTests {

    @Test("ViewModel initializes with StudentLesson values")
    func initializesWithStudentLessonValues() throws {
        let tc = try ViewModelTestContext.make()
        let lesson = makeTestLesson(name: "Addition")
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        tc.context.insert(lesson)
        tc.context.insert(student)

        let scheduledDate = TestCalendar.date(year: 2025, month: 3, day: 15)
        let studentLesson = makeTestStudentLesson(
            lessonID: lesson.id, studentIDs: [student.id],
            scheduledFor: scheduledDate, notes: "Test notes"
        )
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.editingLessonID == lesson.id)
        #expect(vm.scheduledFor == scheduledDate)
        #expect(vm.notes == "Test notes")
        #expect(vm.selectedStudentIDs.contains(student.id))
    }

    @Test("ViewModel initializes UI state to defaults")
    func initializesUIStateToDefaults() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.showLessonPicker == false)
        #expect(vm.showAssignmentComposer == false)
        #expect(vm.showingAddStudentSheet == false)
        #expect(vm.showingStudentPickerPopover == false)
        #expect(vm.showDeleteAlert == false)
        #expect(vm.showingMoveStudentsSheet == false)
    }

    @Test("ViewModel initializes with autoFocusLessonPicker")
    func initializesWithAutoFocusLessonPicker() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson, autoFocusLessonPicker: true)

        #expect(vm.showLessonPicker == true)
    }
}

// MARK: - Lesson Object Tests

@Suite("StudentLessonDetailViewModel Lesson Object Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelLessonObjectTests {

    @Test("lessonObject returns correct lesson from list")
    func lessonObjectReturnsCorrectLesson() throws {
        let tc = try ViewModelTestContext.make()
        let lesson1 = makeTestLesson(name: "Addition")
        let lesson2 = makeTestLesson(name: "Subtraction")
        tc.context.insert(lesson1)
        tc.context.insert(lesson2)

        let studentLesson = makeTestStudentLesson(lessonID: lesson1.id)
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)
        let result = vm.lessonObject(from: [lesson1, lesson2])

        #expect(result?.id == lesson1.id)
        #expect(result?.name == "Addition")
    }

    @Test("lessonObject returns nil when not found")
    func lessonObjectReturnsNilWhenNotFound() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(lessonID: UUID())
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)
        let result = vm.lessonObject(from: [makeTestLesson(name: "Other")])

        #expect(result == nil)
    }
}

// MARK: - Next Lesson In Group Tests

@Suite("StudentLessonDetailViewModel Next Lesson Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelNextLessonTests {

    @Test("nextLessonInGroup returns nil when current lesson not found")
    func nextLessonInGroupReturnsNilWhenCurrentNotFound() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(lessonID: UUID())
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.nextLessonInGroup(from: []) == nil)
    }

    @Test("nextLessonInGroup returns next lesson in same group")
    func nextLessonInGroupReturnsNextInGroup() throws {
        let tc = try ViewModelTestContext.make()
        let lessons = [
            makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 1),
            makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 2),
            makeTestLesson(name: "Multiplication", subject: "Math", group: "Operations", orderInGroup: 3)
        ]
        lessons.forEach { tc.context.insert($0) }

        let studentLesson = makeTestStudentLesson(lessonID: lessons[0].id)
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.nextLessonInGroup(from: lessons)?.id == lessons[1].id)
    }
}

// MARK: - Move Students Tests

@Suite("StudentLessonDetailViewModel Move Students Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelMoveStudentsTests {

    @Test("studentsToMove is initially empty")
    func studentsToMoveIsInitiallyEmpty() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.studentsToMove.isEmpty)
    }

    @Test("movedStudentNames is initially empty")
    func movedStudentNamesIsInitiallyEmpty() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.movedStudentNames.isEmpty)
    }

    @Test("showMovedBanner is initially false")
    func showMovedBannerIsInitiallyFalse() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.showMovedBanner == false)
    }
}

// MARK: - Notes Autosave Tests

@Suite("StudentLessonDetailViewModel Notes Autosave Tests", .serialized)
@MainActor
struct StudentLessonDetailViewModelNotesAutosaveTests {

    @Test("notesDirty is initially false")
    func notesDirtyIsInitiallyFalse() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(notes: "Original notes")
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.notesDirty == false)
    }

    @Test("originalNotes stores initial notes value")
    func originalNotesStoresInitialValue() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(notes: "Original notes")
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.originalNotes == "Original notes")
    }

    @Test("Changing notes sets notesDirty to true")
    func changingNotesSetsDirtyFlag() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(notes: "Original")
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        vm.notes = "Changed notes"

        #expect(vm.notesDirty == true)
    }

    @Test("Setting notes to same value does not set dirty flag")
    func settingNotesToSameValueDoesNotSetDirty() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(notes: "Same notes")
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        vm.notes = "Same notes"

        #expect(vm.notesDirty == false)
    }

    @Test("flushNotesAutosaveIfNeeded updates model when dirty")
    func flushNotesAutosaveUpdatesModelWhenDirty() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(notes: "Original")
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        vm.notes = "Updated notes"
        vm.flushNotesAutosaveIfNeeded()

        #expect(studentLesson.notes == "Updated notes")
        #expect(vm.notesDirty == false)
        #expect(vm.originalNotes == "Updated notes")
    }

    @Test("flushNotesAutosaveIfNeeded does nothing when not dirty")
    func flushNotesAutosaveDoesNothingWhenNotDirty() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(notes: "Original")
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

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
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.masteryState == .presented)
    }

    @Test("masteryState loads .mastered from existing LessonPresentation")
    func masteryStateLoadsMasteredFromExisting() throws {
        let tc = try ViewModelTestContext.make()
        let student = makeTestStudent()
        let lesson = makeTestLesson()
        tc.context.insert(student)
        tc.context.insert(lesson)

        let studentLesson = makeTestStudentLesson(lessonID: lesson.id, studentIDs: [student.id])
        tc.context.insert(studentLesson)

        let lp = LessonPresentation(
            studentID: student.id.uuidString, lessonID: lesson.id.uuidString,
            presentationID: nil, state: .mastered,
            presentedAt: Date(), lastObservedAt: Date(), masteredAt: Date()
        )
        tc.context.insert(lp)
        try tc.context.save()

        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.masteryState == .mastered)
    }

    @Test("masteryState can be changed")
    func masteryStateCanBeChanged() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

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
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(isPresented: true)
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.isPresented == true)
    }

    @Test("isPresented can be toggled")
    func isPresentedCanBeToggled() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson(isPresented: false)
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

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
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        studentLesson.needsAnotherPresentation = true
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.needsAnotherPresentation == true)
    }

    @Test("needsAnotherPresentation can be changed")
    func needsAnotherPresentationCanBeChanged() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

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
        let tc = try ViewModelTestContext.make()
        let date = TestCalendar.date(year: 2025, month: 6, day: 15)
        let studentLesson = makeTestStudentLesson(scheduledFor: date)
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.scheduledFor == date)
    }

    @Test("givenAt reflects StudentLesson state")
    func givenAtReflectsState() throws {
        let tc = try ViewModelTestContext.make()
        let date = TestCalendar.date(year: 2025, month: 6, day: 20)
        let studentLesson = makeTestStudentLesson(givenAt: date)
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.givenAt == date)
    }

    @Test("scheduledFor can be modified")
    func scheduledForCanBeModified() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        let newDate = TestCalendar.date(year: 2025, month: 7, day: 1)
        vm.scheduledFor = newDate

        #expect(vm.scheduledFor == newDate)
    }

    @Test("givenAt can be modified")
    func givenAtCanBeModified() throws {
        let tc = try ViewModelTestContext.make()
        let studentLesson = makeTestStudentLesson()
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

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
        let tc = try ViewModelTestContext.make()
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        tc.context.insert(student1)
        tc.context.insert(student2)

        let studentLesson = makeTestStudentLesson(studentIDs: [student1.id, student2.id])
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        #expect(vm.selectedStudentIDs.count == 2)
        #expect(vm.selectedStudentIDs.contains(student1.id))
        #expect(vm.selectedStudentIDs.contains(student2.id))
    }

    @Test("selectedStudentIDs can be modified")
    func selectedStudentIDsCanBeModified() throws {
        let tc = try ViewModelTestContext.make()
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        tc.context.insert(student1)

        let studentLesson = makeTestStudentLesson(studentIDs: [student1.id])
        tc.context.insert(studentLesson)
        let vm = tc.makeViewModel(for: studentLesson)

        let newStudentID = UUID()
        vm.selectedStudentIDs.insert(newStudentID)

        #expect(vm.selectedStudentIDs.count == 2)
        #expect(vm.selectedStudentIDs.contains(newStudentID))
    }
}

#endif
