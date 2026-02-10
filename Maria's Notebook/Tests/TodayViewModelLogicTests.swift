#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - TodayViewModel Initialization Tests

@Suite("TodayViewModel Initialization Tests", .serialized)
@MainActor
struct TodayViewModelInitializationTests {

    @Test("TodayViewModel initializes with provided date and normalizes to start of day")
    func initializationAndNormalization() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15, hour: 14, minute: 30)
        let vm = TodayViewModel(context: context, date: testDate)

        let dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: vm.date)
        #expect(dateComponents.year == 2025)
        #expect(dateComponents.month == 3)
        #expect(dateComponents.day == 15)

        let timeComponents = Calendar.current.dateComponents([.hour, .minute, .second], from: vm.date)
        #expect(timeComponents.hour == 0)
        #expect(timeComponents.minute == 0)
        #expect(timeComponents.second == 0)
    }

    @Test("TodayViewModel has correct default values")
    func defaultValues() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let vm = TodayViewModel(context: context)

        let today = Calendar.current.startOfDay(for: Date())
        #expect(vm.date == today)
        #expect(vm.levelFilter == .all)
        expectEmptyViewModel(vm)
    }
}

// MARK: - TodayViewModel displayName Tests

@Suite("TodayViewModel Helper Methods Tests", .serialized)
@MainActor
struct TodayViewModelHelperMethodsTests {

    @Test("displayName and lessonName return fallbacks for unknown IDs")
    func fallbackNamesForUnknownIDs() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let vm = TodayViewModel(context: context)

        #expect(vm.displayName(for: UUID()) == "Student")
        #expect(vm.lessonName(for: UUID()) == "Lesson")
    }

    @Test("duplicateFirstNames is empty when no students")
    func emptyDuplicateFirstNames() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let vm = TodayViewModel(context: context)

        #expect(vm.duplicateFirstNames.isEmpty)
    }
}

// MARK: - TodayViewModel AttendanceSummary Tests

@Suite("TodayViewModel AttendanceSummary Computed Tests", .serialized)
@MainActor
struct TodayViewModelAttendanceSummaryComputedTests {

    @Test("attendance starts with zero counts and empty lists")
    func initialAttendanceState() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let vm = TodayViewModel(context: context)

        expectZeroAttendance(vm)
    }
}

// MARK: - TodayViewModel Reload Tests

@Suite("TodayViewModel Reload Tests", .serialized)
@MainActor
struct TodayViewModelReloadTests {

    @Test("reload fetches lessons for date and populates caches")
    func reloadFetchesAndPopulates() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)
        let nextDate = TestCalendar.date(year: 2025, month: 3, day: 16)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(student)
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, scheduledFor: testDate)
        let slOther = makeTestStudentLesson(student: student, lesson: lesson, scheduledFor: nextDate)
        context.insert(sl)
        context.insert(slOther)
        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.todaysLessons.count == 1)
        #expect(vm.todaysLessons.first?.id == sl.id)
        #expect(vm.studentsByID[student.id]?.firstName == "Alice")
        #expect(vm.lessonsByID[lesson.id]?.name == "Addition")
    }

    @Test("reload handles empty database")
    func reloadHandlesEmptyDatabase() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let vm = TodayViewModel(context: context)

        vm.reload()

        expectEmptyViewModel(vm)
    }
}

// MARK: - TodayViewModel Level Filter Tests

@Suite("TodayViewModel Level Filter Behavior Tests", .serialized)
@MainActor
struct TodayViewModelLevelFilterBehaviorTests {

    @Test("levelFilter can be changed")
    func levelFilterCanBeChanged() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let vm = TodayViewModel(context: context)

        vm.levelFilter = .lower
        #expect(vm.levelFilter == .lower)
        vm.levelFilter = .upper
        #expect(vm.levelFilter == .upper)
        vm.levelFilter = .all
        #expect(vm.levelFilter == .all)
    }

    @Test("levelFilter controls which lessons appear")
    func levelFilterFiltersLessons() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let lowerStudent = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let upperStudent = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lowerStudent)
        context.insert(upperStudent)
        context.insert(lesson)

        let sl1 = makeTestStudentLesson(student: lowerStudent, lesson: lesson, scheduledFor: testDate)
        let sl2 = makeTestStudentLesson(student: upperStudent, lesson: lesson, scheduledFor: testDate)
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)

        // Test .all filter
        vm.levelFilter = .all
        vm.reload()
        #expect(vm.todaysLessons.count == 2)

        // Test .lower filter
        vm.levelFilter = .lower
        vm.reload()
        #expect(vm.todaysLessons.count == 1)
        #expect(vm.todaysLessons.first?.resolvedStudentIDs.contains(lowerStudent.id) == true)

        // Test .upper filter
        vm.levelFilter = .upper
        vm.reload()
        #expect(vm.todaysLessons.count == 1)
        #expect(vm.todaysLessons.first?.resolvedStudentIDs.contains(upperStudent.id) == true)
    }
}

// MARK: - TodayViewModel Date Navigation Tests

@Suite("TodayViewModel Date Navigation Tests", .serialized)
@MainActor
struct TodayViewModelDateNavigationTests {

    @Test("date change is normalized")
    func dateChangeIsNormalized() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)
        let newDate = TestCalendar.date(year: 2025, month: 4, day: 20, hour: 15, minute: 45)

        vm.date = newDate

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: vm.date)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test("nextDayWithLessons finds day with lessons")
    func nextDayWithLessonsFindsDay() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let startDate = TestCalendar.date(year: 2025, month: 3, day: 10)
        let lessonDate = TestCalendar.date(year: 2025, month: 3, day: 12)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, scheduledFor: lessonDate)
        context.insert(sl)

        try context.save()

        let vm = TodayViewModel(context: context, date: startDate)
        let nextDay = vm.nextDayWithLessons(after: startDate)

        let components = Calendar.current.dateComponents([.year, .month, .day], from: nextDay)
        #expect(components.day == 12)
    }

    @Test("previousDayWithLessons finds day with lessons")
    func previousDayWithLessonsFindsDay() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let startDate = TestCalendar.date(year: 2025, month: 3, day: 15)
        let lessonDate = TestCalendar.date(year: 2025, month: 3, day: 12)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, scheduledFor: lessonDate)
        context.insert(sl)

        try context.save()

        let vm = TodayViewModel(context: context, date: startDate)
        let prevDay = vm.previousDayWithLessons(before: startDate)

        let components = Calendar.current.dateComponents([.year, .month, .day], from: prevDay)
        #expect(components.day == 12)
    }
}

// MARK: - TodayViewModel Attendance Reload Tests

@Suite("TodayViewModel Attendance Reload Tests", .serialized)
@MainActor
struct TodayViewModelAttendanceReloadTests {

    @Test("reload computes attendance summary and tracking lists")
    func reloadComputesAttendance() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let rec1 = makeTestAttendanceRecord(studentID: student1.id, date: testDate, status: .present)
        let rec2 = makeTestAttendanceRecord(studentID: student2.id, date: testDate, status: .absent)
        let rec3 = makeTestAttendanceRecord(studentID: student3.id, date: testDate, status: .tardy)
        context.insert(rec1)
        context.insert(rec2)
        context.insert(rec3)
        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.attendanceSummary.presentCount == 2) // present + tardy
        #expect(vm.attendanceSummary.tardyCount == 1)
        #expect(vm.attendanceSummary.absentCount == 1)
        #expect(vm.absentToday.contains(student2.id))
    }

    @Test("reload tracks leftEarly status")
    func reloadTracksLeftEarly() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let rec1 = makeTestAttendanceRecord(studentID: student1.id, date: testDate, status: .leftEarly)
        let rec2 = makeTestAttendanceRecord(studentID: student2.id, date: testDate, status: .present)
        context.insert(rec1)
        context.insert(rec2)
        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.leftEarlyToday.count == 1)
        #expect(vm.leftEarlyToday.contains(student1.id))
    }

    @Test("attendance summary respects level filter")
    func attendanceSummaryRespectsLevelFilter() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)
        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let lowerStudent = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let upperStudent = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        context.insert(lowerStudent)
        context.insert(upperStudent)

        let rec1 = makeTestAttendanceRecord(studentID: lowerStudent.id, date: testDate, status: .present)
        let rec2 = makeTestAttendanceRecord(studentID: upperStudent.id, date: testDate, status: .present)
        context.insert(rec1)
        context.insert(rec2)
        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.levelFilter = .lower
        vm.reload()

        #expect(vm.attendanceSummary.presentCount == 1)
    }
}

// MARK: - TodayViewModel Calendar Tests

@Suite("TodayViewModel Calendar Tests", .serialized)
@MainActor
struct TodayViewModelCalendarTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            WorkPlanItem.self,
            Note.self,
            Document.self,
            Reminder.self,
            CalendarEvent.self,
            GroupTrack.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("setCalendar normalizes date")
    func setCalendarNormalizesDate() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)
        let newCalendar = Calendar(identifier: .gregorian)
        vm.setCalendar(newCalendar)

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: vm.date)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }
}

// MARK: - TodayViewModel Work Schedule Tests

@Suite("TodayViewModel Work Schedule Tests", .serialized)
@MainActor
struct TodayViewModelWorkScheduleTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            WorkPlanItem.self,
            Note.self,
            Document.self,
            Reminder.self,
            CalendarEvent.self,
            GroupTrack.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("reload fetches work scheduled for today")
    func reloadFetchesWorkScheduledForToday() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let work = makeTestWorkModel(
            title: "Math Practice",
            workType: .practice,
            status: .active,
            studentID: student.id.uuidString
        )
        context.insert(work)

        let planItem = WorkPlanItem(workID: work.id, scheduledDate: testDate)
        context.insert(planItem)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.todaysSchedule.count == 1)
        #expect(vm.todaysSchedule.first?.work.title == "Math Practice")
    }

}

// MARK: - TodayViewModel Recent Notes Tests

@Suite("TodayViewModel Recent Notes Tests", .serialized)
@MainActor
struct TodayViewModelRecentNotesTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            WorkPlanItem.self,
            Note.self,
            Document.self,
            Reminder.self,
            CalendarEvent.self,
            GroupTrack.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("recentNotes starts empty")
    func recentNotesStartsEmpty() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.recentNotes.isEmpty)
    }

    @Test("recentNoteStudentsByID starts empty")
    func recentNoteStudentsByIDStartsEmpty() throws {
        let container = try makeTodayViewModelContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.recentNoteStudentsByID.isEmpty)
    }
}

#endif
