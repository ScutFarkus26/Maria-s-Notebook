#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Initialization Tests

@Suite("LessonPickerViewModel Initialization Tests", .serialized)
@MainActor
struct LessonPickerViewModelInitializationTests {

    @Test("LessonPickerViewModel initializes with default values")
    func initializesWithDefaultValues() {
        let vm = LessonPickerViewModel()

        #expect(vm.selectedStudentIDs.isEmpty)
        #expect(vm.scheduledFor == nil)
        #expect(vm.givenAt == nil)
        #expect(vm.notes == "")
        #expect(vm.needsPractice == false)
        #expect(vm.needsAnotherPresentation == false)
        #expect(vm.followUpWork == "")
        #expect(vm.selectedLessonID == nil)
        #expect(vm.mode == .plan)
    }

    @Test("LessonPickerViewModel initializes with custom values")
    func initializesWithCustomValues() {
        let studentID = UUID()
        let lessonID = UUID()
        let date = TestCalendar.date(year: 2025, month: 3, day: 15)

        let vm = LessonPickerViewModel(
            selectedStudentIDs: [studentID],
            scheduledFor: date,
            notes: "Test notes",
            needsPractice: true,
            selectedLessonID: lessonID,
            mode: .given
        )

        #expect(vm.selectedStudentIDs.contains(studentID))
        #expect(vm.scheduledFor == date)
        #expect(vm.notes == "Test notes")
        #expect(vm.needsPractice == true)
        #expect(vm.selectedLessonID == lessonID)
        #expect(vm.mode == .given)
    }

    @Test("LessonPickerViewModel lessonSearchText starts empty")
    func lessonSearchTextStartsEmpty() {
        let vm = LessonPickerViewModel()

        #expect(vm.lessonSearchText == "")
    }

    @Test("LessonPickerViewModel studentSearchText starts empty")
    func studentSearchTextStartsEmpty() {
        let vm = LessonPickerViewModel()

        #expect(vm.studentSearchText == "")
    }

    @Test("LessonPickerViewModel studentLevelFilter defaults to all")
    func studentLevelFilterDefaultsToAll() {
        let vm = LessonPickerViewModel()

        #expect(vm.studentLevelFilter == .all)
    }

    @Test("LessonPickerViewModel showFollowUpField defaults to false")
    func showFollowUpFieldDefaultsToFalse() {
        let vm = LessonPickerViewModel()

        #expect(vm.showFollowUpField == false)
    }
}

// MARK: - Configuration Tests

@Suite("LessonPickerViewModel Configuration Tests", .serialized)
@MainActor
struct LessonPickerViewModelConfigurationTests {

    @Test("configure sets lessons and students")
    func configureSetsLessonsAndStudents() {
        let vm = LessonPickerViewModel()

        let lessons = [
            makeTestLesson(name: "Addition"),
            makeTestLesson(name: "Subtraction"),
        ]
        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Anderson"),
            makeTestStudent(firstName: "Bob", lastName: "Brown"),
        ]

        vm.configure(lessons: lessons, students: students)

        #expect(vm.sortedLessons.count == 2)
        #expect(vm.sortedStudents.count == 2)
    }

    @Test("configure sorts lessons alphabetically")
    func configureSortsLessons() {
        let vm = LessonPickerViewModel()

        let lessons = [
            makeTestLesson(name: "Zebra Lesson"),
            makeTestLesson(name: "Apple Lesson"),
            makeTestLesson(name: "Mango Lesson"),
        ]

        vm.configure(lessons: lessons, students: [])

        #expect(vm.sortedLessons[0].name == "Apple Lesson")
        #expect(vm.sortedLessons[1].name == "Mango Lesson")
        #expect(vm.sortedLessons[2].name == "Zebra Lesson")
    }

    @Test("configure sorts students by first name then last name")
    func configureSortsStudents() {
        let vm = LessonPickerViewModel()

        let students = [
            makeTestStudent(firstName: "Charlie", lastName: "Clark"),
            makeTestStudent(firstName: "Alice", lastName: "Anderson"),
            makeTestStudent(firstName: "Alice", lastName: "Brown"),
        ]

        vm.configure(lessons: [], students: students)

        #expect(vm.sortedStudents[0].firstName == "Alice")
        #expect(vm.sortedStudents[0].lastName == "Anderson")
        #expect(vm.sortedStudents[1].firstName == "Alice")
        #expect(vm.sortedStudents[1].lastName == "Brown")
        #expect(vm.sortedStudents[2].firstName == "Charlie")
    }

    @Test("configure populates lessonSearchText when lesson already selected")
    func configurePopulatesSearchTextForSelectedLesson() {
        let lessonID = UUID()
        let vm = LessonPickerViewModel(selectedLessonID: lessonID)

        let lessons = [
            makeTestLesson(id: lessonID, name: "Selected Lesson"),
            makeTestLesson(name: "Other Lesson"),
        ]

        vm.configure(lessons: lessons, students: [])

        #expect(vm.lessonSearchText == "Selected Lesson")
    }
}

// MARK: - Mode Tests

@Suite("LessonPickerViewModel Mode Tests", .serialized)
@MainActor
struct LessonPickerViewModelModeTests {

    @Test("toggleMode switches plan to given")
    func toggleModeSwitchesPlanToGiven() {
        let vm = LessonPickerViewModel(mode: .plan)

        vm.toggleMode()

        #expect(vm.mode == .given)
    }

    @Test("toggleMode switches given to plan")
    func toggleModeSwitchesGivenToPlan() {
        let vm = LessonPickerViewModel(mode: .given)

        vm.toggleMode()

        #expect(vm.mode == .plan)
    }

    @Test("mode can be set directly")
    func modeCanBeSetDirectly() {
        let vm = LessonPickerViewModel()

        vm.mode = .given

        #expect(vm.mode == .given)

        vm.mode = .plan

        #expect(vm.mode == .plan)
    }
}

// MARK: - Student Selection Tests

@Suite("LessonPickerViewModel Student Selection Tests", .serialized)
@MainActor
struct LessonPickerViewModelStudentSelectionTests {

    @Test("toggleStudentSelection adds unselected student")
    func toggleAddsUnselectedStudent() {
        let vm = LessonPickerViewModel()
        let studentID = UUID()

        vm.toggleStudentSelection(studentID)

        #expect(vm.selectedStudentIDs.contains(studentID))
    }

    @Test("toggleStudentSelection removes selected student")
    func toggleRemovesSelectedStudent() {
        let studentID = UUID()
        let vm = LessonPickerViewModel(selectedStudentIDs: [studentID])

        vm.toggleStudentSelection(studentID)

        #expect(!vm.selectedStudentIDs.contains(studentID))
    }

    @Test("multiple students can be selected")
    func multipleStudentsCanBeSelected() {
        let vm = LessonPickerViewModel()
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        vm.toggleStudentSelection(id1)
        vm.toggleStudentSelection(id2)
        vm.toggleStudentSelection(id3)

        #expect(vm.selectedStudentIDs.count == 3)
        #expect(vm.selectedStudentIDs.contains(id1))
        #expect(vm.selectedStudentIDs.contains(id2))
        #expect(vm.selectedStudentIDs.contains(id3))
    }

    @Test("removeStudent removes student")
    func removeStudentRemovesStudent() {
        let studentID = UUID()
        let vm = LessonPickerViewModel(selectedStudentIDs: [studentID])

        vm.removeStudent(studentID)

        #expect(!vm.selectedStudentIDs.contains(studentID))
    }

    @Test("removeStudent does nothing for non-selected student")
    func removeStudentDoesNothingForNonSelected() {
        let vm = LessonPickerViewModel()
        let studentID = UUID()

        vm.removeStudent(studentID)

        #expect(vm.selectedStudentIDs.isEmpty)
    }

    @Test("selectedStudents returns students matching selectedStudentIDs")
    func selectedStudentsReturnsMatchingStudents() {
        let vm = LessonPickerViewModel()

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")

        vm.configure(lessons: [], students: [student1, student2, student3])
        vm.toggleStudentSelection(student1.id)
        vm.toggleStudentSelection(student3.id)

        #expect(vm.selectedStudents.count == 2)
        #expect(vm.selectedStudents.contains { $0.id == student1.id })
        #expect(vm.selectedStudents.contains { $0.id == student3.id })
    }
}

// MARK: - Lesson Selection Tests

@Suite("LessonPickerViewModel Lesson Selection Tests", .serialized)
@MainActor
struct LessonPickerViewModelLessonSelectionTests {

    @Test("selectLesson updates selectedLessonID")
    func selectLessonUpdatesSelectedLessonID() {
        let vm = LessonPickerViewModel()
        let lessonID = UUID()
        let lesson = makeTestLesson(id: lessonID, name: "Test Lesson")

        vm.configure(lessons: [lesson], students: [])
        vm.selectLesson(lessonID)

        #expect(vm.selectedLessonID == lessonID)
    }

    @Test("selectLesson updates lessonSearchText")
    func selectLessonUpdatesSearchText() {
        let vm = LessonPickerViewModel()
        let lessonID = UUID()
        let lesson = makeTestLesson(id: lessonID, name: "Test Lesson")

        vm.configure(lessons: [lesson], students: [])
        vm.selectLesson(lessonID)

        #expect(vm.lessonSearchText == "Test Lesson")
    }

    @Test("selectLesson clears searchText when lesson not found")
    func selectLessonClearsSearchTextWhenNotFound() {
        let vm = LessonPickerViewModel()

        vm.configure(lessons: [], students: [])
        vm.selectLesson(UUID())

        #expect(vm.lessonSearchText == "")
    }
}

// MARK: - Filtering Tests

@Suite("LessonPickerViewModel Filtering Tests", .serialized)
@MainActor
struct LessonPickerViewModelFilteringTests {

    @Test("filteredLessons returns all when search text is empty")
    func filteredLessonsReturnsAllWhenEmpty() {
        let vm = LessonPickerViewModel()

        let lessons = [
            makeTestLesson(name: "Lesson A"),
            makeTestLesson(name: "Lesson B"),
            makeTestLesson(name: "Lesson C"),
        ]

        vm.configure(lessons: lessons, students: [])
        vm.lessonSearchText = ""

        #expect(vm.filteredLessons.count == 3)
    }

    @Test("filteredLessons filters by name")
    func filteredLessonsFiltersByName() {
        let vm = LessonPickerViewModel()

        let lessons = [
            makeTestLesson(name: "Addition"),
            makeTestLesson(name: "Subtraction"),
            makeTestLesson(name: "Multiplication"),
        ]

        vm.configure(lessons: lessons, students: [])
        vm.lessonSearchText = "Add"

        #expect(vm.filteredLessons.count == 1)
        #expect(vm.filteredLessons[0].name == "Addition")
    }

    @Test("filteredLessons filters by subject")
    func filteredLessonsFiltersBySubject() {
        let vm = LessonPickerViewModel()

        let lessons = [
            makeTestLesson(name: "Addition", subject: "Math"),
            makeTestLesson(name: "Reading", subject: "Language"),
            makeTestLesson(name: "Subtraction", subject: "Math"),
        ]

        vm.configure(lessons: lessons, students: [])
        vm.lessonSearchText = "Math"

        #expect(vm.filteredLessons.count == 2)
    }

    @Test("filteredLessons filters by group")
    func filteredLessonsFiltersByGroup() {
        let vm = LessonPickerViewModel()

        let lessons = [
            makeTestLesson(name: "Lesson A", group: "Operations"),
            makeTestLesson(name: "Lesson B", group: "Geometry"),
            makeTestLesson(name: "Lesson C", group: "Operations"),
        ]

        vm.configure(lessons: lessons, students: [])
        vm.lessonSearchText = "Operations"

        #expect(vm.filteredLessons.count == 2)
    }

    @Test("filteredLessons is case insensitive")
    func filteredLessonsIsCaseInsensitive() {
        let vm = LessonPickerViewModel()

        let lessons = [
            makeTestLesson(name: "Addition"),
        ]

        vm.configure(lessons: lessons, students: [])
        vm.lessonSearchText = "ADDITION"

        #expect(vm.filteredLessons.count == 1)
    }

    @Test("filteredStudentsForPicker filters by level")
    func filteredStudentsForPickerFiltersByLevel() {
        let vm = LessonPickerViewModel()

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower),
            makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper),
            makeTestStudent(firstName: "Charlie", lastName: "Clark", level: .lower),
        ]

        vm.configure(lessons: [], students: students)
        vm.studentLevelFilter = .lower

        #expect(vm.filteredStudentsForPicker.count == 2)
        #expect(vm.filteredStudentsForPicker.allSatisfy { $0.level == .lower })
    }

    @Test("filteredStudentsForPicker filters by search text")
    func filteredStudentsForPickerFiltersBySearchText() {
        let vm = LessonPickerViewModel()

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Anderson"),
            makeTestStudent(firstName: "Bob", lastName: "Brown"),
            makeTestStudent(firstName: "Charlie", lastName: "Clark"),
        ]

        vm.configure(lessons: [], students: students)
        vm.studentSearchText = "Alice"

        #expect(vm.filteredStudentsForPicker.count == 1)
        #expect(vm.filteredStudentsForPicker[0].firstName == "Alice")
    }

    @Test("filteredStudentsForPicker combines level and search filters")
    func filteredStudentsForPickerCombinesFilters() {
        let vm = LessonPickerViewModel()

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower),
            makeTestStudent(firstName: "Alice", lastName: "Adams", level: .upper),
            makeTestStudent(firstName: "Bob", lastName: "Brown", level: .lower),
        ]

        vm.configure(lessons: [], students: students)
        vm.studentLevelFilter = .lower
        vm.studentSearchText = "Alice"

        #expect(vm.filteredStudentsForPicker.count == 1)
        #expect(vm.filteredStudentsForPicker[0].lastName == "Anderson")
    }
}

// MARK: - Validation Tests

@Suite("LessonPickerViewModel Validation Tests", .serialized)
@MainActor
struct LessonPickerViewModelValidationTests {

    @Test("isValid returns false when no lesson selected")
    func isValidReturnsFalseWhenNoLesson() {
        let vm = LessonPickerViewModel()

        vm.toggleStudentSelection(UUID())

        #expect(vm.isValid == false)
    }

    @Test("isValid returns false when no students selected")
    func isValidReturnsFalseWhenNoStudents() {
        let vm = LessonPickerViewModel(selectedLessonID: UUID())

        #expect(vm.isValid == false)
    }

    @Test("isValid returns true when lesson and students selected")
    func isValidReturnsTrueWhenValid() {
        let vm = LessonPickerViewModel(selectedLessonID: UUID())

        vm.toggleStudentSelection(UUID())

        #expect(vm.isValid == true)
    }

    @Test("shouldShowScheduleHint returns true in plan mode without scheduled date")
    func shouldShowScheduleHintTrueInPlanModeWithoutDate() {
        let vm = LessonPickerViewModel(scheduledFor: nil, mode: .plan)

        #expect(vm.shouldShowScheduleHint == true)
    }

    @Test("shouldShowScheduleHint returns false in plan mode with scheduled date")
    func shouldShowScheduleHintFalseInPlanModeWithDate() {
        let date = TestCalendar.date(year: 2025, month: 3, day: 15)
        let vm = LessonPickerViewModel(scheduledFor: date, mode: .plan)

        #expect(vm.shouldShowScheduleHint == false)
    }

    @Test("shouldShowScheduleHint returns false in given mode")
    func shouldShowScheduleHintFalseInGivenMode() {
        let vm = LessonPickerViewModel(mode: .given)

        #expect(vm.shouldShowScheduleHint == false)
    }
}

// MARK: - Reset Tests

@Suite("LessonPickerViewModel Reset Tests", .serialized)
@MainActor
struct LessonPickerViewModelResetTests {

    @Test("reset clears search text fields")
    func resetClearsSearchText() {
        let vm = LessonPickerViewModel()

        vm.lessonSearchText = "Some search"
        vm.studentSearchText = "Another search"
        vm.showFollowUpField = true

        vm.reset()

        #expect(vm.lessonSearchText == "")
        #expect(vm.studentSearchText == "")
        #expect(vm.showFollowUpField == false)
    }
}

// MARK: - GiveLessonMode Tests

@Suite("GiveLessonMode Tests", .serialized)
struct GiveLessonModeTests {

    @Test("GiveLessonMode.plan is hashable")
    func planIsHashable() {
        let mode: GiveLessonMode = .plan
        _ = mode.hashValue  // Just verify it can be hashed
        #expect(mode == .plan)
    }

    @Test("GiveLessonMode.given is hashable")
    func givenIsHashable() {
        let mode: GiveLessonMode = .given
        _ = mode.hashValue
        #expect(mode == .given)
    }

    @Test("GiveLessonMode equality works")
    func equalityWorks() {
        #expect(GiveLessonMode.plan == GiveLessonMode.plan)
        #expect(GiveLessonMode.given == GiveLessonMode.given)
        #expect(GiveLessonMode.plan != GiveLessonMode.given)
    }
}

// MARK: - StudentLevelFilter Tests

@Suite("StudentLevelFilter Tests", .serialized)
struct StudentLevelFilterTests {

    @Test("StudentLevelFilter has correct rawValues")
    func hasCorrectRawValues() {
        #expect(StudentLevelFilter.all.rawValue == "All")
        #expect(StudentLevelFilter.lower.rawValue == "Lower")
        #expect(StudentLevelFilter.upper.rawValue == "Upper")
    }

    @Test("StudentLevelFilter has three cases")
    func hasThreeCases() {
        #expect(StudentLevelFilter.allCases.count == 3)
    }

    @Test("StudentLevelFilter allCases contains all values")
    func allCasesContainsAllValues() {
        let allCases = StudentLevelFilter.allCases
        #expect(allCases.contains(.all))
        #expect(allCases.contains(.lower))
        #expect(allCases.contains(.upper))
    }
}

// MARK: - SaveError Tests

@Suite("LessonPickerViewModel.SaveError Tests", .serialized)
@MainActor
struct LessonPickerViewModelSaveErrorTests {

    @Test("SaveError.missingLesson has correct title")
    func missingLessonHasCorrectTitle() {
        let error = LessonPickerViewModel.SaveError.missingLesson

        #expect(error.title == "Choose a Lesson")
    }

    @Test("SaveError.missingLesson has correct description")
    func missingLessonHasCorrectDescription() {
        let error = LessonPickerViewModel.SaveError.missingLesson

        #expect(error.errorDescription == "Please select a lesson before saving.")
    }

    @Test("SaveError.persistFailed has correct title")
    func persistFailedHasCorrectTitle() {
        let underlying = NSError(domain: "test", code: 1, userInfo: nil)
        let error = LessonPickerViewModel.SaveError.persistFailed(underlying: underlying)

        #expect(error.title == "Save Failed")
    }

    @Test("SaveError.persistFailed includes underlying error description")
    func persistFailedIncludesUnderlyingDescription() {
        let underlying = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = LessonPickerViewModel.SaveError.persistFailed(underlying: underlying)

        #expect(error.errorDescription?.contains("Test error") == true)
    }
}

// MARK: - Display Helper Tests

@Suite("LessonPickerViewModel Display Helper Tests", .serialized)
@MainActor
struct LessonPickerViewModelDisplayHelperTests {

    @Test("displayName returns abbreviated name")
    func displayNameReturnsAbbreviatedName() {
        let vm = LessonPickerViewModel()
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")

        let displayName = vm.displayName(for: student)

        #expect(displayName == "Alice A.")
    }

    @Test("displayName handles single name")
    func displayNameHandlesSingleName() {
        let vm = LessonPickerViewModel()
        let student = Student(firstName: "Alice", lastName: "", birthday: Date())

        let displayName = vm.displayName(for: student)

        #expect(displayName == "Alice")
    }
}

#endif
