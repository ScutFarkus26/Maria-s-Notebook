#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

@Suite("TodayViewModel.LevelFilter Tests")
struct TodayViewModelLevelFilterTests {

    // MARK: - LevelFilter Raw Values

    @Test("LevelFilter.all has correct rawValue")
    func levelFilterAllRawValue() {
        let filter = TodayViewModel.LevelFilter.all

        #expect(filter.rawValue == "All")
    }

    @Test("LevelFilter.lower has correct rawValue")
    func levelFilterLowerRawValue() {
        let filter = TodayViewModel.LevelFilter.lower

        #expect(filter.rawValue == "Lower")
    }

    @Test("LevelFilter.upper has correct rawValue")
    func levelFilterUpperRawValue() {
        let filter = TodayViewModel.LevelFilter.upper

        #expect(filter.rawValue == "Upper")
    }

    // MARK: - LevelFilter ID

    @Test("LevelFilter id equals rawValue")
    func levelFilterIdEqualsRawValue() {
        for filter in TodayViewModel.LevelFilter.allCases {
            #expect(filter.id == filter.rawValue)
        }
    }

    // MARK: - LevelFilter.matches Tests

    @Test("LevelFilter.all matches lower level")
    func allMatchesLower() {
        let filter = TodayViewModel.LevelFilter.all

        #expect(filter.matches(.lower) == true)
    }

    @Test("LevelFilter.all matches upper level")
    func allMatchesUpper() {
        let filter = TodayViewModel.LevelFilter.all

        #expect(filter.matches(.upper) == true)
    }

    @Test("LevelFilter.lower matches lower level")
    func lowerMatchesLower() {
        let filter = TodayViewModel.LevelFilter.lower

        #expect(filter.matches(.lower) == true)
    }

    @Test("LevelFilter.lower does not match upper level")
    func lowerDoesNotMatchUpper() {
        let filter = TodayViewModel.LevelFilter.lower

        #expect(filter.matches(.upper) == false)
    }

    @Test("LevelFilter.upper matches upper level")
    func upperMatchesUpper() {
        let filter = TodayViewModel.LevelFilter.upper

        #expect(filter.matches(.upper) == true)
    }

    @Test("LevelFilter.upper does not match lower level")
    func upperDoesNotMatchLower() {
        let filter = TodayViewModel.LevelFilter.upper

        #expect(filter.matches(.lower) == false)
    }

    // MARK: - LevelFilter CaseIterable

    @Test("LevelFilter has 3 cases")
    func levelFilterHasThreeCases() {
        #expect(TodayViewModel.LevelFilter.allCases.count == 3)
    }

    @Test("LevelFilter allCases contains all expected values")
    func levelFilterAllCasesComplete() {
        let allCases = TodayViewModel.LevelFilter.allCases

        #expect(allCases.contains(.all))
        #expect(allCases.contains(.lower))
        #expect(allCases.contains(.upper))
    }
}

@Suite("TodayViewModel.AttendanceSummary Tests")
struct TodayViewModelAttendanceSummaryTests {

    @Test("AttendanceSummary default values are zero")
    func defaultValuesAreZero() {
        let summary = TodayViewModel.AttendanceSummary()

        #expect(summary.presentCount == 0)
        #expect(summary.absentCount == 0)
        #expect(summary.leftEarlyCount == 0)
    }

    @Test("AttendanceSummary stores custom values")
    func storesCustomValues() {
        let summary = TodayViewModel.AttendanceSummary(
            presentCount: 15,
            absentCount: 3,
            leftEarlyCount: 2
        )

        #expect(summary.presentCount == 15)
        #expect(summary.absentCount == 3)
        #expect(summary.leftEarlyCount == 2)
    }
}

@Suite("ContractScheduleItem Tests")
@MainActor
struct ContractScheduleItemTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WorkModel.self,
            WorkPlanItem.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("ContractScheduleItem id comes from planItem")
    func idComesFromPlanItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", studentID: "student123", lessonID: "lesson456")
        let planItem = WorkPlanItem(workID: work.id, scheduledDate: Date())

        context.insert(work)
        context.insert(planItem)

        let item = ContractScheduleItem(work: work, planItem: planItem)

        #expect(item.id == planItem.id)
    }

    @Test("ContractScheduleItem stores work and planItem")
    func storesWorkAndPlanItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Addition Practice", studentID: "student123", lessonID: "lesson456")
        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let planItem = WorkPlanItem(workID: work.id, scheduledDate: scheduledDate)

        context.insert(work)
        context.insert(planItem)

        let item = ContractScheduleItem(work: work, planItem: planItem)

        #expect(item.work.title == "Addition Practice")
        #expect(item.planItem.scheduledDate == scheduledDate)
    }
}

@Suite("ContractFollowUpItem Tests")
@MainActor
struct ContractFollowUpItemTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WorkModel.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("ContractFollowUpItem stores daysSinceTouch")
    func storesDaysSinceTouch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", studentID: "student123", lessonID: "lesson456")
        context.insert(work)

        let item = ContractFollowUpItem(work: work, daysSinceTouch: 5)

        #expect(item.daysSinceTouch == 5)
    }

    @Test("ContractFollowUpItem id comes from work")
    func idComesFromWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", studentID: "student123", lessonID: "lesson456")
        context.insert(work)

        let item = ContractFollowUpItem(work: work, daysSinceTouch: 3)

        #expect(item.id == work.id)
    }

    @Test("ContractFollowUpItem stores work reference")
    func storesWorkReference() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Division Practice", studentID: "student123", lessonID: "lesson456")
        context.insert(work)

        let item = ContractFollowUpItem(work: work, daysSinceTouch: 10)

        #expect(item.work.title == "Division Practice")
        #expect(item.daysSinceTouch == 10)
    }
}

@Suite("TodayViewModel.AttendanceSummary Additional Tests")
struct TodayViewModelAttendanceSummaryAdditionalTests {

    @Test("AttendanceSummary initializes all counters to zero")
    func allCountersZero() {
        let summary = TodayViewModel.AttendanceSummary()

        #expect(summary.presentCount == 0)
        #expect(summary.tardyCount == 0)
        #expect(summary.absentCount == 0)
        #expect(summary.leftEarlyCount == 0)
    }

    @Test("AttendanceSummary can store non-zero values")
    func storesNonZeroValues() {
        let summary = TodayViewModel.AttendanceSummary(
            presentCount: 20,
            tardyCount: 2,
            absentCount: 3,
            leftEarlyCount: 1
        )

        #expect(summary.presentCount == 20)
        #expect(summary.tardyCount == 2)
        #expect(summary.absentCount == 3)
        #expect(summary.leftEarlyCount == 1)
    }

    @Test("AttendanceSummary handles large counts")
    func handlesLargeCounts() {
        let summary = TodayViewModel.AttendanceSummary(
            presentCount: 500,
            tardyCount: 50,
            absentCount: 75,
            leftEarlyCount: 25
        )

        #expect(summary.presentCount == 500)
        #expect(summary.tardyCount == 50)
        #expect(summary.absentCount == 75)
        #expect(summary.leftEarlyCount == 25)
    }

    @Test("AttendanceSummary all values independent")
    func valuesAreIndependent() {
        var summary = TodayViewModel.AttendanceSummary()

        summary.presentCount = 10
        #expect(summary.presentCount == 10)
        #expect(summary.absentCount == 0)

        summary.absentCount = 5
        #expect(summary.absentCount == 5)
        #expect(summary.leftEarlyCount == 0)
    }
}

@Suite("TodayViewModel.LevelFilter Additional Tests")
struct TodayViewModelLevelFilterAdditionalTests {

    @Test("LevelFilter.all is first in allCases")
    func allIsFirst() {
        let allCases = TodayViewModel.LevelFilter.allCases

        #expect(allCases.first == .all)
    }

    @Test("LevelFilter has consistent id and rawValue")
    func idMatchesRawValue() {
        for filter in TodayViewModel.LevelFilter.allCases {
            #expect(filter.id == filter.rawValue)
        }
    }

    @Test("LevelFilter matches returns true for .all with any level")
    func allMatchesAnyLevel() {
        let filter = TodayViewModel.LevelFilter.all

        #expect(filter.matches(.lower) == true)
        #expect(filter.matches(.upper) == true)
    }

    @Test("LevelFilter.lower only matches .lower")
    func lowerOnlyMatchesLower() {
        let filter = TodayViewModel.LevelFilter.lower

        #expect(filter.matches(.lower) == true)
        #expect(filter.matches(.upper) == false)
    }

    @Test("LevelFilter.upper only matches .upper")
    func upperOnlyMatchesUpper() {
        let filter = TodayViewModel.LevelFilter.upper

        #expect(filter.matches(.upper) == true)
        #expect(filter.matches(.lower) == false)
    }

    @Test("LevelFilter allCases iteration")
    func allCasesIteration() {
        let filters = TodayViewModel.LevelFilter.allCases
        var count = 0

        for _ in filters {
            count += 1
        }

        #expect(count == 3)
    }
}
#endif
