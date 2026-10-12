import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review 2026-10-11 (c): the rollover in spring closes out this year (#1). The
// second test is a guard for (c) #7: `status`'s setter already stamps
// `modifiedAt`, so a revived skipped row was stamped all along.
@Suite("Rollover and year plan (review fixes 10-11)", .serialized)
@MainActor
struct ReviewFixes1011CTests {

    private let cal = AppCalendar.shared

    private func makeStore() -> SchoolYearStore {
        let store = SchoolYearStore()
        store.publish = { _, _, _ in }
        return store
    }

    @Test("In spring the default closes out this year, on its last day, without a warning")
    func springRolloverClosesThisYear() {
        let store = makeStore()
        let current = store.current
        // Early June of a year starting in late August: past the middle of the
        // year, before its last 60 days.
        let spring = cal.date(byAdding: .day, value: -80, to: current.end) ?? current.end
        let effective = SchoolYearRolloverViewModel.defaultEffectiveDate(today: spring, store: store)
        let lastDay = cal.date(byAdding: .day, value: -1, to: current.end) ?? current.end
        #expect(cal.isDate(effective, inSameDayAs: lastDay))

        let viewModel = SchoolYearRolloverViewModel()
        viewModel.plan = RolloverPlan(effectiveDate: effective)
        #expect(viewModel.outgoingYear(store: store).beginYear == current.beginYear)
        #expect(viewModel.incomingYear(store: store, today: spring).beginYear == current.beginYear + 1)
        #expect(!viewModel.closesYearInProgress(store: store, today: spring))

        // Today's own date in spring closes this year too, and isn't questioned.
        viewModel.plan = RolloverPlan(effectiveDate: spring)
        #expect(!viewModel.closesYearInProgress(store: store, today: spring))

        // An autumn date of this year still asks.
        viewModel.plan = RolloverPlan(effectiveDate: cal.date(byAdding: .day, value: 46, to: current.start) ?? current.start)
        #expect(viewModel.closesYearInProgress(store: store, today: spring))
    }

    // Guard: passes on the old code too.
    @Test("A skipped entry planned again is stamped as edited")
    func revivedEntryIsStamped() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        SchoolCalendarService.shared.invalidateCache()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Lev")
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads 1", area: "Math", sequence: "Golden Beads"
        )
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(student.id).uuidString
        entry.lessonID = try #require(lesson.id).uuidString
        entry.plannedDate = cal.date(from: DateComponents(year: 2026, month: 10, day: 5))
        entry.status = .skipped
        entry.modifiedAt = Date.distantPast
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = AddSequenceViewModel()
        viewModel.selectedLesson = lesson
        viewModel.startDate = cal.date(from: DateComponents(year: 2026, month: 11, day: 2)) ?? Date()
        await viewModel.computePreview(student: student, context: context)
        let before = Date()
        viewModel.scheduleAll(student: student, context: context)

        #expect(entry.status == .planned)
        #expect((entry.modifiedAt ?? .distantPast) >= before.addingTimeInterval(-1))
    }
}
