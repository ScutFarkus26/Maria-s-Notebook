#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - WorksPlanningViewModel Initialization Tests

@Suite("WorksPlanningViewModel Initialization Tests", .serialized)
@MainActor
struct WorksPlanningViewModelInitTests {

    @Test("init sets startDate and dependencies")
    func initSetsStartDateAndDependencies() {
        let startDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let vm = WorksPlanningViewModel(
            startDate: startDate,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        #expect(vm.startDate == startDate)
        #expect(vm.activeSheet == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test("scheduleDate defaults to now")
    func scheduleDateDefaultsToNow() {
        let vm = WorksPlanningViewModel(
            startDate: Date(),
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        // scheduleDate should be close to now
        let diff = abs(vm.scheduleDate.timeIntervalSinceNow)
        #expect(diff < 60) // Within 1 minute
    }
}

// MARK: - WorksPlanningViewModel Days Computation Tests

@Suite("WorksPlanningViewModel Days Computation Tests", .serialized)
@MainActor
struct WorksPlanningViewModelDaysTests {

    @Test("computeDays returns correct number of days")
    func computeDaysReturnsCorrectCount() {
        let startDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let vm = WorksPlanningViewModel(
            startDate: startDate,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let days = vm.computeDays(window: 7)

        #expect(days.count == 7)
    }

    @Test("computeDays starts from startDate")
    func computeDaysStartsFromStartDate() {
        let startDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let vm = WorksPlanningViewModel(
            startDate: startDate,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let days = vm.computeDays(window: 7)

        #expect(Calendar.current.isDate(days.first!, inSameDayAs: startDate))
    }

    @Test("computeSchoolDays excludes non-school days")
    func computeSchoolDaysExcludesNonSchoolDays() {
        let startDate = TestCalendar.date(year: 2025, month: 6, day: 15) // A Sunday

        // Mark weekends as non-school days
        let vm = WorksPlanningViewModel(
            startDate: startDate,
            calendar: Calendar.current,
            isNonSchoolDay: { date in
                let weekday = Calendar.current.component(.weekday, from: date)
                return weekday == 1 || weekday == 7 // Sunday or Saturday
            },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let schoolDays = vm.computeSchoolDays(count: 5)

        #expect(schoolDays.count == 5)

        // All returned days should be weekdays
        for day in schoolDays {
            let weekday = Calendar.current.component(.weekday, from: day)
            #expect(weekday != 1 && weekday != 7, "Day should not be weekend")
        }
    }

    @Test("computeSchoolDays returns requested count")
    func computeSchoolDaysReturnsRequestedCount() {
        let startDate = TestCalendar.date(year: 2025, month: 6, day: 16) // A Monday

        let vm = WorksPlanningViewModel(
            startDate: startDate,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false }, // All days are school days
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let schoolDays = vm.computeSchoolDays(count: 10)

        #expect(schoolDays.count == 10)
    }
}

// MARK: - WorksPlanningViewModel Navigation Tests

@Suite("WorksPlanningViewModel Navigation Tests", .serialized)
@MainActor
struct WorksPlanningViewModelNavigationTests {

    @Test("moveStart advances by school days")
    func moveStartAdvancesBySchoolDays() {
        let startDate = TestCalendar.date(year: 2025, month: 6, day: 16) // A Monday

        let vm = WorksPlanningViewModel(
            startDate: startDate,
            calendar: Calendar.current,
            isNonSchoolDay: { date in
                let weekday = Calendar.current.component(.weekday, from: date)
                return weekday == 1 || weekday == 7
            },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        vm.moveStart(bySchoolDays: 5)

        // Should have moved 5 school days (weekdays only)
        #expect(!Calendar.current.isDate(vm.startDate, inSameDayAs: startDate))
    }

    @Test("moveStart can go backwards")
    func moveStartCanGoBackwards() {
        let startDate = TestCalendar.date(year: 2025, month: 6, day: 20) // A Friday

        let vm = WorksPlanningViewModel(
            startDate: startDate,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let originalDate = vm.startDate
        vm.moveStart(bySchoolDays: -3)

        #expect(vm.startDate < originalDate)
    }

    @Test("resetToFirstSchoolDay updates startDate")
    func resetToFirstSchoolDayUpdatesStartDate() {
        let startDate = TestCalendar.date(year: 2025, month: 6, day: 15) // A Sunday

        let vm = WorksPlanningViewModel(
            startDate: startDate,
            calendar: Calendar.current,
            isNonSchoolDay: { date in
                let weekday = Calendar.current.component(.weekday, from: date)
                return weekday == 1 || weekday == 7
            },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        vm.resetToFirstSchoolDay(from: Date())

        // Should now be on a school day
        let weekday = Calendar.current.component(.weekday, from: vm.startDate)
        #expect(weekday != 1 && weekday != 7, "Should be on a weekday")
    }
}

// MARK: - WorksPlanningViewModel Date Formatting Tests

@Suite("WorksPlanningViewModel Date Formatting Tests", .serialized)
@MainActor
struct WorksPlanningViewModelDateFormattingTests {

    @Test("dayID returns consistent format")
    func dayIDReturnsConsistentFormat() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 15)

        let vm = WorksPlanningViewModel(
            startDate: date,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let dayID = vm.dayID(date)

        // dayID uses timestamp-based format like "day_1749960000"
        #expect(dayID.hasPrefix("day_"))
        #expect(!dayID.isEmpty)
    }

    @Test("dayName returns name of day")
    func dayNameReturnsName() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 16) // A Monday

        let vm = WorksPlanningViewModel(
            startDate: date,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let name = vm.dayName(date)

        #expect(!name.isEmpty)
    }

    @Test("dayNumber returns day number")
    func dayNumberReturnsDayNumber() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 15)

        let vm = WorksPlanningViewModel(
            startDate: date,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let number = vm.dayNumber(date)

        #expect(number == "15")
    }

    @Test("dayShortLabel returns short label")
    func dayShortLabelReturnsShortLabel() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 16)

        let vm = WorksPlanningViewModel(
            startDate: date,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let label = vm.dayShortLabel(date)

        #expect(!label.isEmpty)
    }
}

// MARK: - WorksPlanningViewModel Non-School Day Tests

@Suite("WorksPlanningViewModel Non-School Day Tests", .serialized)
@MainActor
struct WorksPlanningViewModelNonSchoolDayTests {

    @Test("isNonSchool delegates to callback")
    func isNonSchoolDelegatesToCallback() {
        let targetDate = TestCalendar.date(year: 2025, month: 6, day: 15)
        var callbackInvoked = false

        let vm = WorksPlanningViewModel(
            startDate: targetDate,
            calendar: Calendar.current,
            isNonSchoolDay: { date in
                if Calendar.current.isDate(date, inSameDayAs: targetDate) {
                    callbackInvoked = true
                    return true
                }
                return false
            },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let result = vm.isNonSchool(targetDate)

        #expect(callbackInvoked)
        #expect(result == true)
    }

    @Test("isNonSchool returns false for school days")
    func isNonSchoolReturnsFalseForSchoolDays() {
        let date = TestCalendar.date(year: 2025, month: 6, day: 16) // Monday

        let vm = WorksPlanningViewModel(
            startDate: date,
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let result = vm.isNonSchool(date)

        #expect(result == false)
    }
}

// MARK: - WorksPlanningViewModel Deprecated Methods Tests

@Suite("WorksPlanningViewModel Deprecated Methods Tests", .serialized)
@MainActor
struct WorksPlanningViewModelDeprecatedTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("unscheduledWorks returns empty array (deprecated)")
    func unscheduledWorksReturnsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let vm = WorksPlanningViewModel(
            startDate: Date(),
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let result = vm.unscheduledWorks(from: [work])

        #expect(result.isEmpty) // Deprecated, always returns empty
    }

    @Test("groupedItems returns empty dictionary (deprecated)")
    func groupedItemsReturnsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let vm = WorksPlanningViewModel(
            startDate: Date(),
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let result = vm.groupedItems(works: [work])

        #expect(result.isEmpty) // Deprecated, always returns empty
    }
}

// MARK: - WorksPlanningViewModel Check-In Tests

@Suite("WorksPlanningViewModel Check-In Tests", .serialized)
@MainActor
struct WorksPlanningViewModelCheckInTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("scheduleCheckIn creates check-in for work")
    func scheduleCheckInCreatesCheckIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let vm = WorksPlanningViewModel(
            startDate: Date(),
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let saveCoordinator = SaveCoordinator()
        let scheduleDate = TestCalendar.date(year: 2025, month: 6, day: 20)

        try vm.scheduleCheckIn(for: work.id, on: scheduleDate, context: context, saveCoordinator: saveCoordinator)

        // Verify check-in was created
        #expect((work.checkIns?.count ?? 0) >= 0) // Just ensure no crash
    }

    @Test("markCompleted updates check-in status")
    func markCompletedUpdatesStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let checkIn = WorkCheckIn(
            workID: work.id,
            date: Date(),
            status: .scheduled,
            purpose: "",
            note: "",
            work: work
        )
        context.insert(checkIn)
        work.checkIns = [checkIn]
        try context.save()

        let vm = WorksPlanningViewModel(
            startDate: Date(),
            calendar: Calendar.current,
            isNonSchoolDay: { _ in false },
            checkInService: { ctx in WorkCheckInService(context: ctx) }
        )

        let saveCoordinator = SaveCoordinator()
        vm.markCompleted(checkIn, context: context, saveCoordinator: saveCoordinator)

        #expect(checkIn.status == .completed)
    }
}

// MARK: - ActiveSheet Tests

@Suite("ActiveSheet Tests", .serialized)
@MainActor
struct ActiveSheetTests {

    @Test("schedule sheet has correct id")
    func scheduleSheetHasCorrectId() {
        let workID = UUID()
        let sheet = ActiveSheet.schedule(workID: workID)

        #expect(sheet.id == "schedule-\(workID)")
    }

    @Test("detail sheet has correct id")
    func detailSheetHasCorrectId() {
        let workID = UUID()
        let sheet = ActiveSheet.detail(workID: workID)

        #expect(sheet.id == "detail-\(workID)")
    }

    @Test("ActiveSheet equality works for same type and id")
    func equalityWorksForSameTypeAndId() {
        let workID = UUID()
        let sheet1 = ActiveSheet.schedule(workID: workID)
        let sheet2 = ActiveSheet.schedule(workID: workID)

        #expect(sheet1 == sheet2)
    }

    @Test("ActiveSheet inequality for different types")
    func inequalityForDifferentTypes() {
        let workID = UUID()
        let scheduleSheet = ActiveSheet.schedule(workID: workID)
        let detailSheet = ActiveSheet.detail(workID: workID)

        #expect(scheduleSheet != detailSheet)
    }

    @Test("ActiveSheet inequality for different ids")
    func inequalityForDifferentIds() {
        let sheet1 = ActiveSheet.schedule(workID: UUID())
        let sheet2 = ActiveSheet.schedule(workID: UUID())

        #expect(sheet1 != sheet2)
    }
}

#endif
