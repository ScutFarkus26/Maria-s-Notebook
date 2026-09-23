import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Today keeps its ready queue between reloads and rebuilds it only when one
/// of the entities it reads changes. These pin that the kept queue is always
/// the one a fresh build returns, and that the gate skips attendance taps.
@Suite("Today ready queue cache")
@MainActor
struct TodayReadyForNextCacheTests {

    private struct Fixture {
        let first: CDLesson
        let second: CDLesson
        let third: CDLesson
        let avital: CDStudent
        let noa: CDStudent
    }

    private func seed(in context: NSManagedObjectContext) throws -> Fixture {
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Commutative", area: "Math", sequence: "Laws")
        first.orderInSequence = 10
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Distributive", area: "Math", sequence: "Laws")
        second.orderInSequence = 20
        let third = CoreDataTestHelpers.seedLesson(in: context, name: "Associative", area: "Math", sequence: "Laws")
        third.orderInSequence = 30
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "B")
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "C")
        let given = PresentationFactory.makePresented(
            lesson: first, students: [avital, noa],
            presentedAt: try CoreDataTestHelpers.day("2026-03-11"), context: context
        )
        given.confirmStudent(try #require(avital.id))
        #expect(CoreDataTestHelpers.save(context))
        return Fixture(first: first, second: second, third: third, avital: avital, noa: noa)
    }

    private func fresh(_ context: NSManagedObjectContext) -> [ReadyForNextItem] {
        TodayViewModel.buildReadyForNext(lessons: nil, in: context)
    }

    @Test("The kept queue equals a fresh build after each kind of change")
    func keptQueueMatchesFreshBuild() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let fixture = try seed(in: context)
        let viewModel = TodayViewModel(context: context)

        viewModel.reload()
        #expect(viewModel.readyForNext.count == 1)
        #expect(viewModel.readyForNext == fresh(context))

        // Confirm Noa too: a presented-assignment edit on the view context.
        let assignment = try #require(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).first)
        assignment.confirmStudent(try #require(fixture.noa.id))
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        #expect(viewModel.readyForNext.count == 2)
        #expect(viewModel.readyForNext == fresh(context))

        // An unsaved edit in the same turn as the reload is still seen.
        PresentationPlanner.planDraft(lesson: fixture.second, students: [fixture.avital], purpose: nil, in: context)
        viewModel.reload()
        #expect(viewModel.readyForNext.count == 1)
        #expect(viewModel.readyForNext == fresh(context))
        #expect(CoreDataTestHelpers.save(context))

        // A save on a background context sharing the coordinator.
        let background = stack.newBackgroundContext()
        let noaID = try #require(fixture.noa.id)
        background.performAndWait {
            let request = CDFetchRequest(CDStudent.self)
            request.predicate = NSPredicate(format: "id == %@", noaID as CVarArg)
            let noa = background.safeFetch(request).first
            noa?.enrollmentStatus = .withdrawn
            _ = background.safeSave()
        }
        // The view context merges the background save asynchronously.
        let deadline = Date().addingTimeInterval(10)
        while fixture.noa.enrollmentStatus != .withdrawn, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(fixture.noa.enrollmentStatus == .withdrawn)
        viewModel.reload()
        #expect(viewModel.readyForNext.isEmpty)
        #expect(viewModel.readyForNext == fresh(context))
    }

    @Test("Attendance taps and repeat reloads do not rebuild the queue; a record change does")
    func gateSkipsUnrelatedReloads() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let fixture = try seed(in: context)
        let viewModel = TodayViewModel(context: context)

        viewModel.reload()
        #expect(viewModel.readyForNextBuildCount == 1)
        viewModel.reload()
        #expect(viewModel.readyForNextBuildCount == 1)

        CoreDataTestHelpers.seedAttendance(in: context, studentID: try #require(fixture.avital.id), date: Date())
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        #expect(viewModel.readyForNextBuildCount == 1)
        #expect(viewModel.readyForNext == fresh(context))

        fixture.third.orderInSequence = 15
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        #expect(viewModel.readyForNextBuildCount == 2)
        #expect(viewModel.readyForNext == fresh(context))
        #expect(viewModel.readyForNext.first?.nextLessonID == fixture.third.id?.uuidString)

        viewModel.invalidateReadyForNext()
        viewModel.reload()
        #expect(viewModel.readyForNextBuildCount == 3)
    }

    @Test("The catalog path gives the same queue as the fetch path")
    func catalogPathMatchesFetch() throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        _ = try seed(in: context)
        let viewModel = TodayViewModel(context: context)
        viewModel.lessonCatalog = dependencies.lessonCatalog

        viewModel.reload()
        #expect(viewModel.readyForNext.count == 1)
        #expect(viewModel.readyForNext == fresh(context))
        #expect(
            TodayViewModel.buildReadyForNext(lessons: dependencies.lessonCatalog.all, in: context)
                == fresh(context)
        )
    }
}
