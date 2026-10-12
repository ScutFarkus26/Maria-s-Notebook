import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-12 #43: under this year's lens the Projects list keeps
/// every open project, so the Dormant section — open projects untouched since
/// the year began — can appear at all.
@Suite("Projects year lens, bug hunt 2026-10-12")
@MainActor
struct ProjectYearLensFix1012WTests {

    private var thisYear: DateRange {
        let start = ProjectActivity.currentYearStart()
        return DateRange(start: start, end: AppCalendar.shared.date(byAdding: .year, value: 1, to: start) ?? start)
    }

    private func project(
        lastTouched: Date, isActive: Bool = true, in context: NSManagedObjectContext
    ) -> CDProject {
        let project = CDProject(context: context)
        project.title = "Ancient Egypt"
        project.isActive = isActive
        project.createdAt = AppCalendar.addingDays(-60, to: lastTouched)
        project.modifiedAt = lastTouched
        return project
    }

    @Test("An open project untouched since last year stays listed this year, as Dormant")
    func dormantProjectListedThisYear() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let range = thisYear
        let quiet = project(lastTouched: AppCalendar.addingDays(-90, to: range.start), in: context)

        guard case .dormant = ProjectActivity.status(of: quiet) else {
            Issue.record("the project should read as dormant")
            return
        }
        #expect(quiet.overlaps(range), "the Dormant section is where the guide finds it")
    }

    @Test("A completed project from last year stays out of this year")
    func closedProjectFromLastYearStaysOut() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let range = thisYear
        let done = project(lastTouched: AppCalendar.addingDays(-90, to: range.start), isActive: false, in: context)

        #expect(!done.overlaps(range))
    }

    @Test("An open project stays out of an earlier year it wasn't touched in")
    func openProjectStaysOutOfEarlierYears() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let range = thisYear
        let lastYear = DateRange(
            start: AppCalendar.shared.date(byAdding: .year, value: -1, to: range.start) ?? range.start,
            end: range.start
        )
        // Open, but untouched since the year before last year.
        let quiet = project(lastTouched: AppCalendar.addingDays(-90, to: lastYear.start), in: context)

        #expect(!quiet.overlaps(lastYear), "only the year being lived in keeps every open project")
    }

    @Test("An open project made after a year ended stays out of it")
    func projectMadeLaterStaysOut() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let range = thisYear
        let lastYear = DateRange(
            start: AppCalendar.shared.date(byAdding: .year, value: -1, to: range.start) ?? range.start,
            end: range.start
        )
        let fresh = project(lastTouched: Date(), in: context)
        fresh.createdAt = Date()

        #expect(!fresh.overlaps(lastYear))
        #expect(fresh.overlaps(range))
    }
}
