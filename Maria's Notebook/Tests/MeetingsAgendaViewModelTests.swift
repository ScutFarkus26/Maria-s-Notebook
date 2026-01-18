#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - MeetingsAgendaViewModel Initialization Tests

@Suite("MeetingsAgendaViewModel Initialization Tests", .serialized)
@MainActor
struct MeetingsAgendaViewModelInitTests {

    @Test("init sets startDate to today")
    func initSetsStartDateToToday() {
        let vm = MeetingsAgendaViewModel()

        let calendar = Calendar.current
        #expect(calendar.isDateInToday(vm.startDate))
    }

    @Test("init sets scrollToDay to nil")
    func initSetsScrollToDayToNil() {
        let vm = MeetingsAgendaViewModel()

        #expect(vm.scrollToDay == nil)
    }

    @Test("init sets modelContext to nil")
    func initSetsModelContextToNil() {
        let vm = MeetingsAgendaViewModel()

        #expect(vm.modelContext == nil)
    }
}

// MARK: - MeetingsAgendaViewModel Days Tests

@Suite("MeetingsAgendaViewModel Days Tests", .serialized)
@MainActor
struct MeetingsAgendaViewModelDaysTests {

    @Test("days returns 7 days")
    func daysReturnsSevenDays() {
        let vm = MeetingsAgendaViewModel()

        #expect(vm.days.count == 7)
    }

    @Test("days starts from startDate")
    func daysStartsFromStartDate() {
        let vm = MeetingsAgendaViewModel()
        let calendar = Calendar.current

        let firstDay = vm.days.first!
        let startOfFirstDay = calendar.startOfDay(for: firstDay)
        let startOfStartDate = calendar.startOfDay(for: vm.startDate)

        #expect(startOfFirstDay == startOfStartDate)
    }

    @Test("days are consecutive")
    func daysAreConsecutive() {
        let vm = MeetingsAgendaViewModel()
        let calendar = Calendar.current

        for i in 0..<6 {
            let currentDay = vm.days[i]
            let nextDay = vm.days[i + 1]
            let expectedNext = calendar.date(byAdding: .day, value: 1, to: currentDay)!

            #expect(calendar.isDate(nextDay, inSameDayAs: expectedNext))
        }
    }

    @Test("days updates when startDate changes")
    func daysUpdatesWhenStartDateChanges() {
        let vm = MeetingsAgendaViewModel()
        let originalFirstDay = vm.days.first!

        vm.startDate = Calendar.current.date(byAdding: .day, value: 7, to: vm.startDate)!
        let newFirstDay = vm.days.first!

        #expect(!Calendar.current.isDate(originalFirstDay, inSameDayAs: newFirstDay))
    }
}

// MARK: - MeetingsAgendaViewModel Day ID Tests

@Suite("MeetingsAgendaViewModel Day ID Tests", .serialized)
@MainActor
struct MeetingsAgendaViewModelDayIDTests {

    @Test("dayID returns consistent format")
    func dayIDReturnsConsistentFormat() {
        let vm = MeetingsAgendaViewModel()
        let date = TestCalendar.date(year: 2025, month: 6, day: 15)

        let dayID = vm.dayID(date)

        #expect(dayID == "2025-06-15")
    }

    @Test("dayID handles single digit months and days")
    func dayIDHandlesSingleDigits() {
        let vm = MeetingsAgendaViewModel()
        let date = TestCalendar.date(year: 2025, month: 1, day: 5)

        let dayID = vm.dayID(date)

        #expect(dayID == "2025-01-05")
    }

    @Test("dayID is unique for different dates")
    func dayIDIsUniqueForDifferentDates() {
        let vm = MeetingsAgendaViewModel()
        let date1 = TestCalendar.date(year: 2025, month: 6, day: 15)
        let date2 = TestCalendar.date(year: 2025, month: 6, day: 16)

        let id1 = vm.dayID(date1)
        let id2 = vm.dayID(date2)

        #expect(id1 != id2)
    }

    @Test("dayID is same for same date different times")
    func dayIDIsSameForSameDateDifferentTimes() {
        let vm = MeetingsAgendaViewModel()
        let date1 = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 9, minute: 0)
        let date2 = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 17, minute: 30)

        let id1 = vm.dayID(date1)
        let id2 = vm.dayID(date2)

        #expect(id1 == id2)
    }
}

// MARK: - MeetingsAgendaViewModel Navigation Tests

@Suite("MeetingsAgendaViewModel Navigation Tests", .serialized)
@MainActor
struct MeetingsAgendaViewModelNavigationTests {

    @Test("move advances startDate by specified days")
    func moveAdvancesStartDate() {
        let vm = MeetingsAgendaViewModel()
        let originalDate = vm.startDate

        vm.move(by: 7)

        let expected = Calendar.current.date(byAdding: .day, value: 7, to: originalDate)!
        #expect(Calendar.current.isDate(vm.startDate, inSameDayAs: expected))
    }

    @Test("move can go backwards")
    func moveCanGoBackwards() {
        let vm = MeetingsAgendaViewModel()
        let originalDate = vm.startDate

        vm.move(by: -7)

        let expected = Calendar.current.date(byAdding: .day, value: -7, to: originalDate)!
        #expect(Calendar.current.isDate(vm.startDate, inSameDayAs: expected))
    }

    @Test("move by zero does not change startDate")
    func moveByZeroNoChange() {
        let vm = MeetingsAgendaViewModel()
        let originalDate = vm.startDate

        vm.move(by: 0)

        #expect(Calendar.current.isDate(vm.startDate, inSameDayAs: originalDate))
    }

    @Test("resetToToday sets startDate to today")
    func resetToTodaySetsToToday() {
        let vm = MeetingsAgendaViewModel()

        // Move away from today
        vm.move(by: 30)
        #expect(!Calendar.current.isDateInToday(vm.startDate))

        // Reset
        vm.resetToToday()

        #expect(Calendar.current.isDateInToday(vm.startDate))
    }

    @Test("resetToToday uses start of day")
    func resetToTodayUsesStartOfDay() {
        let vm = MeetingsAgendaViewModel()
        vm.resetToToday()

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        #expect(vm.startDate == startOfToday)
    }
}

// MARK: - MeetingsAgendaViewModel Meetings Fetch Tests

@Suite("MeetingsAgendaViewModel Meetings Fetch Tests", .serialized)
@MainActor
struct MeetingsAgendaViewModelMeetingsFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentMeeting.self,
            Note.self,
        ])
    }

    @Test("meetings returns empty when modelContext is nil")
    func meetingsReturnsEmptyWhenNoContext() {
        let vm = MeetingsAgendaViewModel()
        vm.modelContext = nil

        let meetings = vm.meetings(for: Date())

        #expect(meetings.isEmpty)
    }

    @Test("meetings returns meetings for specific date")
    func meetingsReturnsMeetingsForDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let targetDate = TestCalendar.date(year: 2025, month: 6, day: 15, hour: 10)
        let meeting = StudentMeeting(studentID: student.id, date: targetDate)
        context.insert(meeting)
        try context.save()

        let vm = MeetingsAgendaViewModel()
        vm.modelContext = context

        let meetings = vm.meetings(for: TestCalendar.date(year: 2025, month: 6, day: 15))

        #expect(meetings.count == 1)
        #expect(meetings.first?.id == meeting.id)
    }

    @Test("meetings excludes meetings from other dates")
    func meetingsExcludesOtherDates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let todayMeeting = StudentMeeting(
            studentID: student.id,
            date: TestCalendar.date(year: 2025, month: 6, day: 15, hour: 10)
        )
        let tomorrowMeeting = StudentMeeting(
            studentID: student.id,
            date: TestCalendar.date(year: 2025, month: 6, day: 16, hour: 10)
        )
        context.insert(todayMeeting)
        context.insert(tomorrowMeeting)
        try context.save()

        let vm = MeetingsAgendaViewModel()
        vm.modelContext = context

        let meetings = vm.meetings(for: TestCalendar.date(year: 2025, month: 6, day: 15))

        #expect(meetings.count == 1)
        #expect(meetings.first?.id == todayMeeting.id)
    }

    @Test("meetings returns sorted by date")
    func meetingsReturnsSortedByDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let targetDate = TestCalendar.date(year: 2025, month: 6, day: 15)
        let laterMeeting = StudentMeeting(
            studentID: student.id,
            date: TestCalendar.date(year: 2025, month: 6, day: 15, hour: 14)
        )
        let earlierMeeting = StudentMeeting(
            studentID: student.id,
            date: TestCalendar.date(year: 2025, month: 6, day: 15, hour: 9)
        )
        context.insert(laterMeeting)
        context.insert(earlierMeeting)
        try context.save()

        let vm = MeetingsAgendaViewModel()
        vm.modelContext = context

        let meetings = vm.meetings(for: targetDate)

        #expect(meetings.count == 2)
        #expect(meetings[0].date < meetings[1].date)
    }

    @Test("meetings returns empty for date with no meetings")
    func meetingsReturnsEmptyForEmptyDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vm = MeetingsAgendaViewModel()
        vm.modelContext = context

        let meetings = vm.meetings(for: TestCalendar.date(year: 2025, month: 6, day: 15))

        #expect(meetings.isEmpty)
    }

    @Test("meetings includes all meetings within 24 hour window")
    func meetingsIncludesAll24HourWindow() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)

        let earlyMorning = StudentMeeting(
            studentID: student.id,
            date: TestCalendar.date(year: 2025, month: 6, day: 15, hour: 0, minute: 5)
        )
        let lateNight = StudentMeeting(
            studentID: student.id,
            date: TestCalendar.date(year: 2025, month: 6, day: 15, hour: 23, minute: 55)
        )
        context.insert(earlyMorning)
        context.insert(lateNight)
        try context.save()

        let vm = MeetingsAgendaViewModel()
        vm.modelContext = context

        let meetings = vm.meetings(for: TestCalendar.date(year: 2025, month: 6, day: 15))

        #expect(meetings.count == 2)
    }
}

// MARK: - MeetingsAgendaViewModel Scroll To Day Tests

@Suite("MeetingsAgendaViewModel Scroll To Day Tests", .serialized)
@MainActor
struct MeetingsAgendaViewModelScrollTests {

    @Test("scrollToDay can be set")
    func scrollToDayCanBeSet() {
        let vm = MeetingsAgendaViewModel()
        let targetDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        vm.scrollToDay = targetDate

        #expect(vm.scrollToDay == targetDate)
    }

    @Test("scrollToDay can be cleared")
    func scrollToDayCanBeCleared() {
        let vm = MeetingsAgendaViewModel()
        vm.scrollToDay = Date()

        vm.scrollToDay = nil

        #expect(vm.scrollToDay == nil)
    }
}

#endif
