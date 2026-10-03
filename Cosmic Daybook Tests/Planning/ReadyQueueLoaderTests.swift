import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The ready queue's loader, which Today and the Groups page each own: it
/// publishes the queue the synchronous build returns together with the
/// snapshot the Groups builders read, rebuilds only when an input moved, and
/// a confirmation saved on the page moves a child to Ready.
@Suite("Ready queue loader")
@MainActor
struct ReadyQueueLoaderTests {
    private typealias Fixture = RecordIndexRowPathFixture

    private func lesson(named name: String, in context: NSManagedObjectContext) throws -> CDLesson {
        try #require(context.safeFetch(CDFetchRequest(CDLesson.self)).first { $0.name == name })
    }

    @Test("Publishes the synchronous queue with the snapshot it was built from")
    func publishesQueueAndSnapshot() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        try Fixture.seedReadyClassroom(in: context)
        let loader = ReadyQueueLoader(context: context)
        #expect(loader.snapshot == nil)

        loader.refreshIfNeeded()
        await loader.settled()

        let expected = ReadyQueueLoader.buildItems(lessons: nil, in: context)
        #expect(!expected.isEmpty)
        #expect(loader.items == expected)
        #expect(loader.publishCount == 1)
        let snapshot = try #require(loader.snapshot)
        #expect(snapshot.items == expected)
        #expect(snapshot.roster.children.count == 2)
        let distributive = try lesson(named: "Distributive Law", in: context)
        let distributiveID = try #require(distributive.id).uuidString
        let position = try #require(snapshot.order.position(of: distributiveID))
        #expect(position.stepLabel == "2 of 2")
    }

    /// Counts are compared within one synchronous stretch: the import signal
    /// is process-wide, and a suite running alongside may post it while a
    /// rebuild is off the main thread, which rightly marks the queue stale.
    @Test("Rebuilds only when an input moved")
    func rebuildsOnlyOnChange() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        try Fixture.seedReadyClassroom(in: context)
        let loader = ReadyQueueLoader(context: context)

        loader.refreshIfNeeded()
        #expect(loader.buildCount == 1)
        loader.refreshIfNeeded()
        #expect(loader.buildCount == 1)
        await loader.settled()
        #expect(loader.snapshot?.roster.children.count == 2)

        // A new child is an input.
        _ = CoreDataTestHelpers.seedStudent(in: context, firstName: "Lior", lastName: "Katz")
        #expect(CoreDataTestHelpers.save(context))
        let beforeSave = loader.buildCount
        loader.refreshIfNeeded()
        #expect(loader.buildCount == beforeSave + 1)
        loader.refreshIfNeeded()
        #expect(loader.buildCount == beforeSave + 1)
        await loader.settled()
        #expect(loader.snapshot?.roster.children.count == 3)
        #expect(loader.items == ReadyQueueLoader.buildItems(lessons: nil, in: context))

        loader.refreshIfNeeded()
        let beforeInvalidate = loader.buildCount
        loader.invalidate()
        loader.refreshIfNeeded()
        #expect(loader.buildCount == beforeInvalidate + 1)
        await loader.settled()
    }

    @Test("An empty roster publishes an empty snapshot, not none")
    func emptyRosterPublishesEmptySnapshot() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let loader = ReadyQueueLoader(context: context)
        loader.refreshIfNeeded()
        await loader.settled()
        let snapshot = try #require(loader.snapshot)
        #expect(snapshot.items.isEmpty)
        #expect(ReadyGroups.build(from: snapshot) { _ in 0 }.lessons.isEmpty)
    }

    @Test("Confirming the child on a group card moves her to Ready on the next build")
    func confirmMovesChildToReady() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Triangle", area: "Geometry", sequence: "Shapes")
        first.orderInSequence = 10
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Square", area: "Geometry", sequence: "Shapes")
        second.orderInSequence = 20
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        let noa = CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Cohen")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Gold")
        let given = PresentationFactory.makePresented(
            lesson: first, students: [maya, noa, eli],
            presentedAt: try CoreDataTestHelpers.day("2026-03-11"), context: context
        )
        given.confirmStudent(try #require(maya.id))
        given.confirmStudent(try #require(noa.id))
        #expect(CoreDataTestHelpers.save(context))

        let loader = ReadyQueueLoader(context: context)
        loader.refreshIfNeeded()
        await loader.settled()
        let squareID = try #require(second.id).uuidString
        let firstSnapshot = try #require(loader.snapshot)
        let before = try #require(ReadyGroups.build(from: firstSnapshot) { _ in 1 }.group(for: squareID))
        #expect(before.ready.map(\.child.name) == ["Maya S", "Noa C"])
        let waiting = try #require(before.unconfirmed.first)
        #expect(waiting.child.name == "Eli G")

        // What the card's Confirm does.
        let object = try context.existingObject(with: waiting.assignmentID)
        let assignment = try #require(object as? CDLessonAssignment)
        let eliID = try #require(waiting.child.uuid)
        assignment.confirmStudent(eliID)
        #expect(CoreDataTestHelpers.save(context))
        loader.refreshIfNeeded()
        await loader.settled()

        let secondSnapshot = try #require(loader.snapshot)
        let after = try #require(ReadyGroups.build(from: secondSnapshot) { _ in 1 }.group(for: squareID))
        #expect(after.ready.map(\.child.name) == ["Eli G", "Maya S", "Noa C"])
        #expect(after.unconfirmed.isEmpty)
    }

    @Test("Today hands its queue and counters to its loader")
    func todayDelegates() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        try Fixture.seedReadyClassroom(in: context)
        let viewModel = TodayViewModel(context: context)
        viewModel.refreshReadyForNextIfNeeded()
        await viewModel.readyQueue.settled()
        #expect(viewModel.readyForNext == viewModel.readyQueue.items)
        #expect(viewModel.readyForNextBuildCount == viewModel.readyQueue.buildCount)
        #expect(viewModel.readyForNextPublishCount == 1)
        #expect(viewModel.readyQueue.snapshot?.items == viewModel.readyForNext)
    }
}
