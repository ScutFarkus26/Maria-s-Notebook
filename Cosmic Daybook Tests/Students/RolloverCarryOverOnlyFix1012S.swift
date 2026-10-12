import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12 #54: a rollover run only to sort out last year's plans
// can be reviewed and applied, and the Done screen reports what it did. Also
// #59's message: a failed carried-over sweep says it didn't save. These need
// the new entry points (`canReview`, `appliedSummaryText`, `applyErrorMessage`),
// so they don't compile against the old code.
@Suite("Carry-over-only rollover and the sweep's message (bug hunt fixes 10-12)", .serialized)
@MainActor
struct RolloverCarryOverOnlyFix1012S {

    private func makeContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        SchoolCalendarService.shared.invalidateCache()
        return context
    }

    private func makeStore() -> SchoolYearStore {
        let store = SchoolYearStore()
        store.publish = { _, _, _ in }
        return store
    }

    private func seedCarriedOverEntry(
        for student: CDStudent, lesson: CDLesson, on date: Date, in context: NSManagedObjectContext
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = date
        entry.sequenceGroupKey = "Geometry::Polygons"
        entry.statusRaw = YearPlanEntryStatus.planned.rawValue
        return entry
    }

    @Test("#54 a rollover that only skips carried-over plans can be reviewed, applied and reported")
    func carryOverOnlyRollover() throws {
        let context = try makeContext()
        let store = makeStore()
        let current = store.current
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        // Closing out last year: its entries are the carried-over ones.
        let effective = AppCalendar.shared.date(byAdding: .day, value: -1, to: current.start) ?? current.start
        let entry = seedCarriedOverEntry(
            for: ora, lesson: lesson, on: AppCalendar.addingDays(-60, to: current.start), in: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = SchoolYearRolloverViewModel()
        viewModel.load(students: [ora], store: store)
        viewModel.plan.effectiveDate = effective
        #expect(viewModel.changeCount == 0)
        #expect(!viewModel.canReview(context: context, store: store))

        viewModel.setCarryOver(.skip, for: try #require(ora.id))
        #expect(viewModel.canReview(context: context, store: store))
        #expect(viewModel.applyButtonTitle == "Apply Rollover")

        viewModel.apply(context: context, store: store)
        #expect(viewModel.phase == .done)
        #expect(entry.status == .skipped)
        #expect(viewModel.appliedSummaryText == "Skipped 1 carried-over year-plan entry.")
    }

    @Test("#54 guard: a rollover with roster changes still counts them on the button and the Done screen")
    func rosterChangesStillCounted() throws {
        let context = try makeContext()
        let store = makeStore()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo", level: .lower)
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = SchoolYearRolloverViewModel()
        viewModel.load(students: [ora], store: store)
        viewModel.setOutcome(.promote(to: .upper), for: ora)
        #expect(viewModel.canReview(context: context, store: store))
        #expect(viewModel.applyButtonTitle == "Apply Rollover (1)")
        viewModel.apply(context: context, store: store)
        #expect(viewModel.appliedSummaryText == "Applied 1 change.")
    }

    @Test("#59 a failed sweep save says so")
    func failedSweepSaysSo() throws {
        let key = UserDefaultsKeys.yearPlanCarryOverSweepYear
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: key)
        defer { defaults.set(saved, forKey: key) }

        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        let lastYear = YearPlanStaleness.previousSchoolYear()
        _ = seedCarriedOverEntry(
            for: ora, lesson: lesson, on: AppCalendar.addingDays(40, to: lastYear.start), in: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = CarriedOverPlanSweepViewModel()
        viewModel.load(context: context, showTestStudents: true, testStudentNames: "")
        viewModel.setChoice(.skip, for: try #require(ora.id))
        let poison = CDNoteStudentLink(context: context)
        poison.setValue(nil, forKey: "noteID")
        viewModel.apply(context: context)
        #expect(viewModel.applyErrorMessage == SettingsCopy.CarriedOverSweep.saveFailed)

        // With the cause gone, Apply works and clears the message.
        context.delete(poison)
        viewModel.apply(context: context)
        #expect(viewModel.applyErrorMessage == nil)
        #expect(viewModel.phase == .done)
        #expect(viewModel.skippedEntries == 1)
    }

    @Test("#51 Watching's roster takes the test-student setting it is given")
    func watchingRosterTakesSetting() throws {
        let context = try makeContext()
        let real = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        let test = CoreDataTestHelpers.seedStudent(in: context, firstName: "Testy", lastName: "McTest")
        #expect(CoreDataTestHelpers.save(context))
        let realID = try #require(real.id)
        let testID = try #require(test.id)

        let hidden = WatchListFetcher.enrolledIDs(
            in: context, showTestStudents: false, testStudentNames: "Testy McTest"
        )
        #expect(hidden == [realID])
        let shown = WatchListFetcher.enrolledIDs(
            in: context, showTestStudents: true, testStudentNames: "Testy McTest"
        )
        #expect(shown == [realID, testID])
    }
}
