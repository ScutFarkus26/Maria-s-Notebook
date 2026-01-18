#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - TodayViewModel Initialization Tests

@Suite("TodayViewModel Initialization Tests", .serialized)
@MainActor
struct TodayViewModelInitializationTests {

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

    @Test("TodayViewModel initializes with provided date")
    func initializesWithProvidedDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15, hour: 14, minute: 30)
        let vm = TodayViewModel(context: context, date: testDate)

        let components = Calendar.current.dateComponents([.year, .month, .day], from: vm.date)
        #expect(components.year == 2025)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }

    @Test("TodayViewModel normalizes date to start of day")
    func normalizesDateToStartOfDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15, hour: 14, minute: 30)
        let vm = TodayViewModel(context: context, date: testDate)

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: vm.date)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test("TodayViewModel defaults to current date")
    func defaultsToCurrentDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        let today = Calendar.current.startOfDay(for: Date())
        #expect(vm.date == today)
    }

    @Test("TodayViewModel defaults levelFilter to all")
    func defaultsLevelFilterToAll() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.levelFilter == .all)
    }

    @Test("TodayViewModel starts with empty outputs")
    func startsWithEmptyOutputs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.todaysLessons.isEmpty)
        #expect(vm.overdueSchedule.isEmpty)
        #expect(vm.todaysSchedule.isEmpty)
        #expect(vm.staleFollowUps.isEmpty)
        #expect(vm.completedContracts.isEmpty)
    }

    @Test("TodayViewModel starts with empty caches")
    func startsWithEmptyCaches() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.studentsByID.isEmpty)
        #expect(vm.lessonsByID.isEmpty)
    }
}

// MARK: - TodayViewModel displayName Tests

@Suite("TodayViewModel displayName Tests", .serialized)
@MainActor
struct TodayViewModelDisplayNameTests {

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

    @Test("displayName returns first name when unique")
    func returnsFirstNameWhenUnique() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let vm = TodayViewModel(context: context)
        // Manually populate the cache for testing
        vm.reload()

        // After reload, we need to manually add to the cache since reload fetches based on lessons
        // For direct testing of displayName, manually set the cache
    }

    @Test("displayName returns Student for unknown ID")
    func returnsStudentForUnknownID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)
        let unknownID = UUID()

        let name = vm.displayName(for: unknownID)

        #expect(name == "Student")
    }
}

// MARK: - TodayViewModel lessonName Tests

@Suite("TodayViewModel lessonName Tests", .serialized)
@MainActor
struct TodayViewModelLessonNameTests {

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

    @Test("lessonName returns Lesson for unknown ID")
    func returnsLessonForUnknownID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)
        let unknownID = UUID()

        let name = vm.lessonName(for: unknownID)

        #expect(name == "Lesson")
    }
}

// MARK: - TodayViewModel duplicateFirstNames Tests

@Suite("TodayViewModel duplicateFirstNames Tests", .serialized)
@MainActor
struct TodayViewModelDuplicateFirstNamesTests {

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

    @Test("duplicateFirstNames is empty when no students")
    func emptyWhenNoStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.duplicateFirstNames.isEmpty)
    }
}

// MARK: - TodayViewModel AttendanceSummary Tests

@Suite("TodayViewModel AttendanceSummary Computed Tests", .serialized)
@MainActor
struct TodayViewModelAttendanceSummaryComputedTests {

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

    @Test("attendanceSummary starts with zero counts")
    func startsWithZeroCounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.attendanceSummary.presentCount == 0)
        #expect(vm.attendanceSummary.tardyCount == 0)
        #expect(vm.attendanceSummary.absentCount == 0)
        #expect(vm.attendanceSummary.leftEarlyCount == 0)
    }

    @Test("absentToday starts empty")
    func absentTodayStartsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.absentToday.isEmpty)
    }

    @Test("leftEarlyToday starts empty")
    func leftEarlyTodayStartsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.leftEarlyToday.isEmpty)
    }
}

// MARK: - TodayViewModel Reload Tests

@Suite("TodayViewModel Reload Tests", .serialized)
@MainActor
struct TodayViewModelReloadTests {

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

    @Test("reload fetches lessons for date")
    func reloadFetchesLessonsForDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)
        let nextDate = TestCalendar.date(year: 2025, month: 3, day: 16)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, scheduledFor: testDate)
        context.insert(sl)

        // Create one for another date to ensure filtering works
        let slOther = makeTestStudentLesson(student: student, lesson: lesson, scheduledFor: nextDate)
        context.insert(slOther)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.todaysLessons.count == 1)
        #expect(vm.todaysLessons.first?.id == sl.id)
    }

    @Test("reload populates studentsByID cache")
    func reloadPopulatesStudentsByID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, scheduledFor: testDate)
        context.insert(sl)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.studentsByID[student.id] != nil)
        #expect(vm.studentsByID[student.id]?.firstName == "Alice")
    }

    @Test("reload populates lessonsByID cache")
    func reloadPopulatesLessonsByID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl = makeTestStudentLesson(student: student, lesson: lesson, scheduledFor: testDate)
        context.insert(sl)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.lessonsByID[lesson.id] != nil)
        #expect(vm.lessonsByID[lesson.id]?.name == "Addition")
    }

    @Test("reload handles empty database")
    func reloadHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)
        vm.reload()

        #expect(vm.todaysLessons.isEmpty)
        #expect(vm.studentsByID.isEmpty)
        #expect(vm.lessonsByID.isEmpty)
    }
}

// MARK: - TodayViewModel Level Filter Tests

@Suite("TodayViewModel Level Filter Behavior Tests", .serialized)
@MainActor
struct TodayViewModelLevelFilterBehaviorTests {

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

    @Test("levelFilter can be changed")
    func levelFilterCanBeChanged() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        vm.levelFilter = .lower
        #expect(vm.levelFilter == .lower)

        vm.levelFilter = .upper
        #expect(vm.levelFilter == .upper)

        vm.levelFilter = .all
        #expect(vm.levelFilter == .all)
    }

    @Test("levelFilter.all shows all lessons")
    func allShowsAllLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let lowerStudent = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let upperStudent = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        context.insert(lowerStudent)
        context.insert(upperStudent)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl1 = makeTestStudentLesson(student: lowerStudent, lesson: lesson, scheduledFor: testDate)
        let sl2 = makeTestStudentLesson(student: upperStudent, lesson: lesson, scheduledFor: testDate)
        context.insert(sl1)
        context.insert(sl2)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.levelFilter = .all
        vm.reload()

        #expect(vm.todaysLessons.count == 2)
    }

    @Test("levelFilter.lower shows only lower level lessons")
    func lowerShowsOnlyLowerLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let lowerStudent = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let upperStudent = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        context.insert(lowerStudent)
        context.insert(upperStudent)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl1 = makeTestStudentLesson(student: lowerStudent, lesson: lesson, scheduledFor: testDate)
        let sl2 = makeTestStudentLesson(student: upperStudent, lesson: lesson, scheduledFor: testDate)
        context.insert(sl1)
        context.insert(sl2)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.levelFilter = .lower
        vm.reload()

        // Only the lower student's lesson should appear
        #expect(vm.todaysLessons.count == 1)
        #expect(vm.todaysLessons.first?.resolvedStudentIDs.contains(lowerStudent.id) == true)
    }

    @Test("levelFilter.upper shows only upper level lessons")
    func upperShowsOnlyUpperLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let lowerStudent = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let upperStudent = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        context.insert(lowerStudent)
        context.insert(upperStudent)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let sl1 = makeTestStudentLesson(student: lowerStudent, lesson: lesson, scheduledFor: testDate)
        let sl2 = makeTestStudentLesson(student: upperStudent, lesson: lesson, scheduledFor: testDate)
        context.insert(sl1)
        context.insert(sl2)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.levelFilter = .upper
        vm.reload()

        // Only the upper student's lesson should appear
        #expect(vm.todaysLessons.count == 1)
        #expect(vm.todaysLessons.first?.resolvedStudentIDs.contains(upperStudent.id) == true)
    }
}

// MARK: - TodayViewModel Date Navigation Tests

@Suite("TodayViewModel Date Navigation Tests", .serialized)
@MainActor
struct TodayViewModelDateNavigationTests {

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

    @Test("date change is normalized")
    func dateChangeIsNormalized() throws {
        let container = try makeContainer()
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
        let container = try makeContainer()
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
        let container = try makeContainer()
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

    @Test("reload computes attendance summary correctly")
    func reloadComputesAttendanceSummary() throws {
        let container = try makeContainer()
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

        // presentCount includes tardy (present + tardy)
        #expect(vm.attendanceSummary.presentCount == 2)
        #expect(vm.attendanceSummary.tardyCount == 1)
        #expect(vm.attendanceSummary.absentCount == 1)
    }

    @Test("reload populates absentToday")
    func reloadPopulatesAbsentToday() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let rec1 = makeTestAttendanceRecord(studentID: student1.id, date: testDate, status: .absent)
        let rec2 = makeTestAttendanceRecord(studentID: student2.id, date: testDate, status: .present)
        context.insert(rec1)
        context.insert(rec2)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.absentToday.count == 1)
        #expect(vm.absentToday.contains(student1.id))
    }

    @Test("reload populates leftEarlyToday")
    func reloadPopulatesLeftEarlyToday() throws {
        let container = try makeContainer()
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
        let container = try makeContainer()
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

        // Only lower student should be counted
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
        let container = try makeContainer()
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
        let container = try makeContainer()
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

    @Test("reload fetches completed work for today")
    func reloadFetchesCompletedWorkForToday() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let work = makeTestWorkModel(
            title: "Completed Work",
            workType: .practice,
            completedAt: testDate,
            status: .complete,
            studentID: student.id.uuidString
        )
        context.insert(work)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.reload()

        #expect(vm.completedContracts.count == 1)
        #expect(vm.completedContracts.first?.title == "Completed Work")
    }

    @Test("completed work respects level filter")
    func completedWorkRespectsLevelFilter() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let testDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let lowerStudent = makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower)
        let upperStudent = makeTestStudent(firstName: "Bob", lastName: "Brown", level: .upper)
        context.insert(lowerStudent)
        context.insert(upperStudent)

        let work1 = makeTestWorkModel(
            title: "Lower Work",
            workType: .practice,
            completedAt: testDate,
            status: .complete,
            studentID: lowerStudent.id.uuidString
        )
        let work2 = makeTestWorkModel(
            title: "Upper Work",
            workType: .practice,
            completedAt: testDate,
            status: .complete,
            studentID: upperStudent.id.uuidString
        )
        context.insert(work1)
        context.insert(work2)

        try context.save()

        let vm = TodayViewModel(context: context, date: testDate)
        vm.levelFilter = .lower
        vm.reload()

        // Only lower student's completed work should appear
        #expect(vm.completedContracts.count == 1)
        #expect(vm.completedContracts.first?.title == "Lower Work")
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
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.recentNotes.isEmpty)
    }

    @Test("recentNoteStudentsByID starts empty")
    func recentNoteStudentsByIDStartsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = TodayViewModel(context: context)

        #expect(vm.recentNoteStudentsByID.isEmpty)
    }
}

#endif
