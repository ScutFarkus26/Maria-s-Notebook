import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Today's ready queue: `reload()` fills `readyForNext` from the record, and
/// a next lesson the guide has since planned takes the child back out of it.
@Suite("Today Ready For Next")
@MainActor
struct TodayViewModelReadyForNextTests {

    private struct Fixture {
        let commutative: CDLesson
        let distributive: CDLesson
        let avital: CDStudent
    }

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    /// Avital was confirmed on the Commutative Law; the Distributive Law after
    /// it in the same sub-area is untouched.
    private func seed(in context: NSManagedObjectContext) throws -> Fixture {
        let commutative = CoreDataTestHelpers.seedLesson(
            in: context, name: "Commutative Law", area: "Math", sequence: "Laws"
        )
        commutative.orderInSequence = 10
        let distributive = CoreDataTestHelpers.seedLesson(
            in: context, name: "Distributive Law", area: "Math", sequence: "Laws"
        )
        distributive.orderInSequence = 20

        let avital = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Avital", lastName: "Beyderman"
        )
        let given = PresentationFactory.makePresented(
            lesson: commutative, students: [avital],
            presentedAt: try day("2026-03-11"), context: context
        )
        given.confirmStudent(try #require(avital.id))
        #expect(CoreDataTestHelpers.save(context))
        return Fixture(commutative: commutative, distributive: distributive, avital: avital)
    }

    @Test("reload fills the queue with the child whose next lesson is untouched")
    func reloadFillsTheQueue() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)

        let viewModel = TodayViewModel(context: context)
        viewModel.reload()

        #expect(viewModel.readyForNext.count == 1)
        let item = try #require(viewModel.readyForNext.first)
        #expect(item.studentID == (try #require(fixture.avital.id).uuidString))
        #expect(item.nextLessonID == (try #require(fixture.distributive.id).uuidString))
        #expect(item.basis == .confirmed)
        #expect(item.tier == .ready)
    }

    @Test("Planning that next lesson for her empties the queue on the next reload")
    func draftingTheNextLessonEmptiesTheQueue() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)

        let viewModel = TodayViewModel(context: context)
        viewModel.reload()
        #expect(viewModel.readyForNext.count == 1)

        PresentationPlanner.planDraft(
            lesson: fixture.distributive,
            students: [fixture.avital],
            purpose: nil,
            in: context
        )
        #expect(CoreDataTestHelpers.save(context))

        viewModel.reload()
        #expect(viewModel.readyForNext.isEmpty)
    }

    @Test("A withdrawn child is not in Today's queue")
    func withdrawnChildIsNotInTheQueue() throws {
        let context = try makeContext()
        let fixture = try seed(in: context)
        fixture.avital.enrollmentStatus = .withdrawn
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = TodayViewModel(context: context)
        viewModel.reload()

        #expect(viewModel.readyForNext.isEmpty)
    }
}
