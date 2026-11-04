import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17: Today in the Sample Class (#30) and the "N children
/// need a lesson" card while Today stays open (#41).
@Suite("Today (fix 10-17 St)")
@MainActor
struct TodayFix1017StTests {

    /// What each piece of EventKit work was asked to do, in order.
    @MainActor
    private final class Calls {
        var names: [String] = []
    }

    // MARK: - #30 Sample Class

    @Test("In the Sample Class, Today's calendar sync does nothing")
    func sampleClassLeavesEventKitAlone() async {
        for isSample in [true, false] {
            let calls = Calls()
            let sync = TodayEventKitSync(
                isSampleClassroom: isSample,
                calendar: { calls.names.append("calendar") }
            )
            await sync.syncCalendarEvents()
            #expect(calls.names == (isSample ? [] : ["calendar"]), "sample: \(isSample)")
        }
    }

    @Test("Today knows the Sample Class from its graph")
    func liveSyncKnowsTheSampleClass() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let sample = AppDependencies(coreDataStack: stack, isSampleClassroom: true)
        #expect(TodayEventKitSync(dependencies: sample).isSampleClassroom)
        #expect(!TodayEventKitSync(dependencies: try CoreDataTestHelpers.makeDependencies()).isSampleClassroom)
    }

    // MARK: - #41 Needs-a-lesson card

    @Test("A lesson given while Today stays open moves the needs-a-lesson count on the next reload")
    func reloadRecountsNeedsLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads", area: "Math", sequence: "Decimal"
        )
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "C")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "R")
        #expect(CoreDataTestHelpers.save(context))

        // What an appearance does.
        let viewModel = TodayViewModel(context: context)
        viewModel.reload()
        viewModel.reloadDerivedCountsIfNeeded(calendar: AppCalendar.shared)
        #expect(viewModel.needsLessonCount == 2)

        // Given in another window or on another device: the save reloads Today.
        _ = PresentationFactory.makePresented(lesson: lesson, students: [noa], context: context)
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        #expect(viewModel.needsLessonCount == 1)

        // Nothing it reads moved: the next reload doesn't count again.
        let builds = viewModel.derivedCountsBuildCount
        viewModel.reload()
        #expect(viewModel.derivedCountsBuildCount == builds)
    }
}
