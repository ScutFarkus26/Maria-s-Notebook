import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Today's ready queue reads and folds its record index off the main thread
/// and publishes on the main actor. These pin that the background read builds
/// the index the view context builds, that Today publishes exactly what the
/// synchronous build returns, that an unsaved record edit keeps the build on
/// the view context, and that a rebuild overtaken by a newer one never
/// publishes over it.
@Suite("Today ready queue off the main thread")
@MainActor
struct TodayReadyForNextBackgroundTests {
    private typealias Index = PresentationRecordIndex
    private typealias Fixture = RecordIndexRowPathFixture

    enum Store {
        case inMemory, sqlite
    }

    private func makeContext(_ store: Store) throws -> (context: NSManagedObjectContext, owner: AnyObject?) {
        switch store {
        case .inMemory:
            let stack = try CoreDataTestHelpers.makeInMemoryStack()
            return (stack.viewContext, stack)
        case .sqlite:
            return (try CoreDataTestHelpers.makeSplitStoreContext(), nil)
        }
    }

    private func expectSameIndex(_ background: Index, _ onContext: Index) {
        #expect(background.givenByLesson == onContext.givenByLesson)
        #expect(background.givenByStudent == onContext.givenByStudent)
        #expect(background.openPlanByLesson == onContext.openPlanByLesson)
        #expect(background.latestPresentedAssignmentByLesson == onContext.latestPresentedAssignmentByLesson)
    }

    private func fresh(_ context: NSManagedObjectContext) -> [ReadyForNextItem] {
        TodayViewModel.buildReadyForNext(lessons: nil, in: context)
    }

    // MARK: - Fixtures

    /// Four sub-areas of six lessons, as each sub-area's lesson ids in order.
    private func seedSequences(in context: NSManagedObjectContext) throws -> [[String]] {
        try (0..<4).map { sequence in
            try (0..<6).map { step in
                let lesson = CoreDataTestHelpers.seedLesson(
                    in: context, name: "Lesson \(sequence)-\(step)",
                    area: "Area\(sequence % 2)", sequence: "Seq\(sequence)"
                )
                lesson.orderInSequence = Int64(step * 10)
                return try #require(lesson.id).uuidString
            }
        }
    }

    /// Twelve enrolled children and one who has left, each partway along each
    /// of four sub-areas: given its lessons up to a step that differs by child
    /// and sub-area, mastered or confirmed on that step for most, the next
    /// step already planned for some, and work still open on the step for
    /// others. A queue of a few dozen items, some of them held at "almost
    /// ready". Returns the departed child's id.
    @discardableResult
    private func seedClassroom(in context: NSManagedObjectContext) throws -> String {
        let enrolled = (0..<12).map {
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Child\($0)", lastName: "L")
        }
        let departed = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Gone", lastName: "L", enrollmentStatus: .withdrawn
        )
        let sequences = try seedSequences(in: context)
        let start = try CoreDataTestHelpers.day("2025-09-01")
        func day(_ offset: Int) -> Date { start.addingTimeInterval(Double(offset) * 86_400) }

        for (child, student) in (enrolled + [departed]).enumerated() {
            let studentID = try #require(student.id).uuidString
            for (sequence, steps) in sequences.enumerated() {
                let reached = (child + sequence) % 5
                for step in 0...reached {
                    let row = CDLessonPresentation(context: context)
                    row.studentID = studentID
                    row.lessonID = steps[step]
                    row.presentedAt = day(step * 7 + child)
                    if step == reached, child % 3 == 0 { row.masteredAt = row.presentedAt }
                }
                let given = CDLessonAssignment(context: context)
                given.lessonID = steps[reached]
                given.studentIDs = [studentID]
                given.markPresented(at: day(reached * 7 + child), snapshotLesson: false)
                if child % 2 == 1 { given.confirmedStudentIDs = [studentID] }
                if (child + sequence) % 4 == 0 {
                    let entry = CDYearPlanEntry(context: context)
                    entry.studentID = studentID
                    entry.lessonID = steps[reached + 1]
                }
                if (child * sequence) % 3 == 1 {
                    let work = CDWorkModel(context: context)
                    work.studentID = studentID
                    work.lessonID = steps[reached]
                }
            }
        }
        #expect(CoreDataTestHelpers.save(context))
        return try #require(departed.id).uuidString
    }

    private func readyClassroom(
        in context: NSManagedObjectContext
    ) throws -> (distributive: CDLesson, avital: CDStudent) {
        try Fixture.seedReadyClassroom(in: context)
        let lesson = context.safeFetch(CDFetchRequest(CDLesson.self)).first { $0.name == "Distributive Law" }
        let student = context.safeFetch(CDFetchRequest(CDStudent.self)).first { $0.firstName == "Avital" }
        return (try #require(lesson), try #require(student))
    }

    // MARK: - Equivalence

    @Test(
        "The background read builds the index the view context builds",
        arguments: [Store.inMemory, .sqlite]
    )
    func backgroundReadMatches(store: Store) async throws {
        let (context, owner) = try makeContext(store)
        defer { withExtendedLifetime(owner) {} }
        let record = try Fixture.seedOddRecord(in: context)
        let scale = try Fixture.seedAprilScale(in: context)
        let coordinator = try #require(context.persistentStoreCoordinator)
        #expect(Index.readPath(lessonIDs: nil, in: context) == .columns)

        let scopes: [Set<String>?] = [
            nil, Set(record.students), Set(scale.students), [record.ada, record.cy, record.eve], []
        ]
        for students in scopes {
            let background = await Index.readInBackground(students: students, from: coordinator)
            expectSameIndex(background, Index(students: students, in: context))
        }
    }

    @Test(
        "Today publishes the queue the synchronous build returns",
        arguments: [Store.inMemory, .sqlite]
    )
    func todayPublishesTheSynchronousQueue(store: Store) async throws {
        let (context, owner) = try makeContext(store)
        defer { withExtendedLifetime(owner) {} }
        let departed = try seedClassroom(in: context)
        let expected = fresh(context)
        #expect(expected.count > 10)
        #expect(expected.contains { $0.tier == .ready })
        #expect(expected.contains { $0.tier == .almostReady })
        #expect(!expected.contains { $0.studentID == departed })

        let viewModel = TodayViewModel(context: context)
        viewModel.reload()
        // Started at once, off the main thread: nothing waits for another reload.
        #expect(viewModel.readyForNextTask != nil)
        await viewModel.readyForNextSettled()
        #expect(viewModel.readyForNext == expected)
        #expect(viewModel.readyForNextPublishCount == 1)
    }

    @Test("With the live catalog, Today publishes the queue the synchronous build returns")
    func catalogPathPublishesTheSynchronousQueue() async throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        try seedClassroom(in: context)
        let viewModel = TodayViewModel(context: context)
        viewModel.lessonCatalog = dependencies.lessonCatalog

        viewModel.reload()
        await viewModel.readyForNextSettled()
        #expect(!viewModel.readyForNext.isEmpty)
        #expect(viewModel.readyForNext == fresh(context))
        #expect(
            viewModel.readyForNext == TodayViewModel.buildReadyForNext(
                lessons: dependencies.lessonCatalog.all, in: context
            )
        )
    }

    // MARK: - The View Context's Own Build

    @Test("An unsaved record edit keeps the build on the view context, published at once")
    func pendingEditBuildsOnTheViewContext() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (distributive, avital) = try readyClassroom(in: context)
        let viewModel = TodayViewModel(context: context)
        viewModel.reload()
        await viewModel.readyForNextSettled()
        #expect(viewModel.readyForNext.count == 1)

        // Only the view context can see the unsaved plan.
        PresentationPlanner.planDraft(lesson: distributive, students: [avital], purpose: nil, in: context)
        viewModel.reload()
        #expect(viewModel.readyForNextTask == nil)
        #expect(viewModel.readyForNext.isEmpty)
        #expect(viewModel.readyForNext == fresh(context))
    }

    // MARK: - Overtaken Rebuilds

    @Test("A background rebuild overtaken by the view context's build never publishes over it")
    func overtakenByTheViewContext() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (distributive, avital) = try readyClassroom(in: context)
        let viewModel = TodayViewModel(context: context)

        viewModel.reload()
        let first = try #require(viewModel.readyForNextTask)
        // Before the first read can come back: an unsaved plan, and a reload
        // that builds on the view context and publishes at once.
        PresentationPlanner.planDraft(lesson: distributive, students: [avital], purpose: nil, in: context)
        viewModel.reload()
        #expect(viewModel.readyForNext.isEmpty)
        #expect(viewModel.readyForNextPublishCount == 1)

        await first.value
        #expect(viewModel.readyForNext.isEmpty)
        #expect(viewModel.readyForNextPublishCount == 1)
        #expect(viewModel.readyForNext == fresh(context))
    }

    @Test("An older background rebuild never publishes over a newer one")
    func olderBackgroundRebuildIsDropped() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (_, avital) = try readyClassroom(in: context)
        let viewModel = TodayViewModel(context: context)

        // The first rebuild takes a roster with Avital, who is ready.
        viewModel.reload()
        let first = try #require(viewModel.readyForNextTask)
        // She leaves before it comes back; the second rebuild's roster
        // does not have her.
        avital.enrollmentStatus = .withdrawn
        #expect(CoreDataTestHelpers.save(context))
        viewModel.reload()
        let second = try #require(viewModel.readyForNextTask)
        #expect(first != second)
        #expect(viewModel.readyForNextBuildCount == 2)

        // Whichever finishes first, only the second publishes.
        await first.value
        await second.value
        #expect(viewModel.readyForNext.isEmpty)
        #expect(viewModel.readyForNextPublishCount == 1)
        #expect(viewModel.readyForNext == fresh(context))
    }
}
