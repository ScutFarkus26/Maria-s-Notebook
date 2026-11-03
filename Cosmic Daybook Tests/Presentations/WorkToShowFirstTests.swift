import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `WorkToShowFirst`: a child's open work on a lesson earlier in the same
/// sequence as the one about to be given, read for many lessons in one fetch.
@Suite("Work to show first")
@MainActor
struct WorkToShowFirstTests {

    let ada = UUID()
    let ben = UUID()

    /// A lesson in Math › `sequence` at `step`.
    func lesson(
        _ name: String, step: Int, sequence: String = "Addition", in context: NSManagedObjectContext
    ) -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: "Math", sequence: sequence)
        lesson.id = UUID()
        lesson.orderInSequence = Int64(step)
        return lesson
    }

    /// One child's own row on `lesson`, naming nobody else.
    @discardableResult
    func work(
        for child: UUID, on lesson: CDLesson, status: WorkStatus = .active, in context: NSManagedObjectContext
    ) throws -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: lesson.name, studentID: child, lessonID: try #require(lesson.id)
        )
        work.status = status
        return work
    }

    /// Linked copies on `lesson`: one row per child, each naming both, made together.
    private func linkedCopies(
        on lesson: CDLesson, statuses: [UUID: WorkStatus], in context: NSManagedObjectContext
    ) throws -> [UUID: CDWorkModel] {
        let made = Date()
        var rows: [UUID: CDWorkModel] = [:]
        for (owner, status) in statuses {
            let row = try work(for: owner, on: lesson, status: status, in: context)
            row.createdAt = made
            for child in statuses.keys {
                let participant = CDWorkParticipantEntity(context: context)
                participant.id = UUID()
                participant.studentID = child.uuidString
                participant.work = row
            }
            rows[owner] = row
        }
        return rows
    }

    private func find(
        _ lesson: CDLesson, for children: Set<UUID>, lessons: [CDLesson], in context: NSManagedObjectContext
    ) throws -> WorkToShowFirst.ByChild {
        WorkToShowFirst.find(
            lessonID: try #require(lesson.id?.uuidString),
            studentIDs: children,
            sequences: WorkToShowFirst.Sequences(lessons: lessons),
            in: context
        )
    }

    // MARK: - Which work

    @Test("Only open work on an earlier lesson of the same sequence counts")
    func sameSequenceEarlierOnly() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let third = lesson("Dot Game", step: 3, in: context)
        let elsewhere = lesson("Snake Game", step: 1, sequence: "Snake Game", in: context)
        let earlier = try work(for: ada, on: first, in: context)
        try work(for: ada, on: second, in: context)
        try work(for: ada, on: third, in: context)
        try work(for: ada, on: elsewhere, in: context)

        let found = try find(second, for: [ada], lessons: [first, second, third, elsewhere], in: context)

        #expect(found.keys.sorted() == [ada])
        #expect(found[ada]?.map(\.work) == [earlier])
        #expect(found[ada]?.first?.lessonName == "Bead Addition")
        #expect(found[ada]?.first?.step == 1)
    }

    @Test("Closed work is left out, Finished included")
    func closedWorkExcluded() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        for status in WorkStatus.closedCases {
            try work(for: ada, on: first, status: status, in: context)
        }
        try work(for: ben, on: first, status: .done, in: context)
        let review = try work(for: ben, on: first, status: .review, in: context)

        let found = try find(second, for: [ada, ben], lessons: [first, second], in: context)

        #expect(found[ada] == nil)
        // Ben's Finished row is left out beside his open one.
        #expect(found[ben]?.map(\.work) == [review])
    }

    @Test("A child not on the lesson is left out")
    func childNotOnLessonExcluded() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        try work(for: ada, on: first, in: context)
        try work(for: ben, on: first, in: context)

        let found = try find(second, for: [ada], lessons: [first, second], in: context)

        #expect(found.keys.sorted() == [ada])
    }

    @Test("A classmate's open copy is not the child's, her own is")
    func classmatesCopyIsNotHers() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let copies = try linkedCopies(on: first, statuses: [ada: .mastered, ben: .active], in: context)

        let found = try find(second, for: [ada, ben], lessons: [first, second], in: context)

        #expect(found[ada] == nil, "Ben's open copy names Ada but isn't her work")
        #expect(found[ben]?.map(\.work) == [try #require(copies[ben])])
    }

    @Test("A shared row counts for a child until she finishes her part")
    func sharedRowUntilHerPartIsDone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let shared = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Bead chains poster", studentID: ada, lessonID: try #require(first.id)
        )
        shared.studentID = ""
        for (child, done) in [(ada, true), (ben, false)] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.completedAt = done ? Date() : nil
            participant.work = shared
        }

        let found = try find(second, for: [ada, ben], lessons: [first, second], in: context)

        #expect(found[ada] == nil)
        #expect(found[ben]?.map(\.work) == [shared])
        #expect(found[ben]?.first?.workTitle == "Bead chains poster")
    }

    @Test("Earlier lessons come first, and the first lesson has none before it")
    func orderAndFirstLesson() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let third = lesson("Dot Game", step: 3, in: context)
        let onSecond = try work(for: ada, on: second, in: context)
        let onFirst = try work(for: ada, on: first, in: context)
        let lessons = [first, second, third]

        #expect(try find(third, for: [ada], lessons: lessons, in: context)[ada]?.map(\.work) == [onFirst, onSecond])
        #expect(try find(first, for: [ada], lessons: lessons, in: context).isEmpty)
        let sequences = WorkToShowFirst.Sequences(lessons: lessons)
        #expect(WorkToShowFirst.earlierLessonIDs(before: try #require(first.id?.uuidString), in: sequences).isEmpty)
        #expect(WorkToShowFirst.earlierLessonIDs(before: UUID().uuidString, in: sequences).isEmpty)
    }

    @Test("Earlier means a lower step number: lessons tied on one, ordered only by name, aren't earlier")
    func tiesAreNotEarlier() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // A sequence never numbered: every lesson at 0, sorted by name alone.
        let apple = lesson("Apple Addition", step: 0, sequence: "Unordered", in: context)
        let banana = lesson("Banana Addition", step: 0, sequence: "Unordered", in: context)
        try work(for: ada, on: apple, in: context)
        #expect(try find(banana, for: [ada], lessons: [apple, banana], in: context).isEmpty)

        // Two lessons sharing step 1 and one at step 2.
        let bead = lesson("Bead Addition", step: 1, in: context)
        let chain = lesson("Chain Addition", step: 1, in: context)
        let stamp = lesson("Stamp Game Addition", step: 2, in: context)
        let onBead = try work(for: ada, on: bead, in: context)
        let onChain = try work(for: ada, on: chain, in: context)
        let lessons = [bead, chain, stamp]
        #expect(try find(chain, for: [ada], lessons: lessons, in: context).isEmpty, "Bead sorts first by name only")
        let beforeStamp = try find(stamp, for: [ada], lessons: lessons, in: context)[ada]?.map(\.work)
        #expect(Set(try #require(beforeStamp)) == [onBead, onChain])
    }

    @Test("A lesson with no sequence has nothing before it, and asks for nothing")
    func lessonWithNoSequence() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let loose = lesson("Bead Frame", step: 2, sequence: "", in: context)
        try work(for: ada, on: first, in: context)
        let sequences = WorkToShowFirst.Sequences(lessons: [first, loose])

        #expect(WorkToShowFirst.earlierLessonIDs(before: try #require(loose.id?.uuidString), in: sequences).isEmpty)
        #expect(try find(loose, for: [ada], lessons: [first, loose], in: context).isEmpty)
    }

    // MARK: - One fetch

    private func countingContext() throws -> (NSManagedObjectContext, CountingCoordinator) {
        let coordinator = CountingCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        _ = try coordinator.addPersistentStore(type: .inMemory, at: URL(fileURLWithPath: "/dev/null"))
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return (context, coordinator)
    }

    @Test("Many lessons are answered with one fetch, and nothing to ask fetches nothing")
    func oneFetchPerCall() throws {
        let (context, coordinator) = try countingContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let snakeOne = lesson("Snake Game", step: 1, sequence: "Snake Game", in: context)
        let snakeTwo = lesson("Negative Snake", step: 2, sequence: "Snake Game", in: context)
        try work(for: ada, on: first, in: context)
        try work(for: ben, on: snakeOne, in: context)
        try context.save()
        let lessons = [first, second, snakeOne, snakeTwo]
        let requests: [String: WorkToShowFirst.Request] = [
            "addition": .init(lessonID: try #require(second.id?.uuidString), studentIDs: [ada, ben]),
            "snake": .init(lessonID: try #require(snakeTwo.id?.uuidString), studentIDs: [ada, ben]),
            "first": .init(lessonID: try #require(first.id?.uuidString), studentIDs: [ada])
        ]
        coordinator.fetches = 0

        let found = WorkToShowFirst.find(requests, sequences: WorkToShowFirst.Sequences(lessons: lessons), in: context)

        #expect(coordinator.fetches == 1, "rows naming one child need no second read")
        #expect(found["addition"]?.keys.sorted() == [ada])
        #expect(found["snake"]?.keys.sorted() == [ben])
        #expect(found["first"] == nil)

        let nothing = WorkToShowFirst.find(
            ["first": try #require(requests["first"])],
            sequences: WorkToShowFirst.Sequences(lessons: lessons),
            in: context
        )
        #expect(nothing.isEmpty)
        #expect(coordinator.fetches == 1, "a lesson with nothing before it needs no fetch")
    }

    @Test("Closed rows are read only on a lesson where an open row names more than one child")
    func secondFetchOnlyForGroupWork() throws {
        let (context, coordinator) = try countingContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let copies = try linkedCopies(on: first, statuses: [ada: .mastered, ben: .active], in: context)
        try context.save()
        coordinator.fetches = 0

        let found = WorkToShowFirst.find(
            ["lesson": .init(lessonID: try #require(second.id?.uuidString), studentIDs: [ada, ben])],
            sequences: WorkToShowFirst.Sequences(lessons: [first, second]),
            in: context
        )

        #expect(coordinator.fetches == 2, "the open rows, then the lesson's rows to tell the copies apart")
        // Ada's closed copy, read the second time, is what keeps Ben's open one off her list.
        #expect(found["lesson"]?[ada] == nil)
        #expect(found["lesson"]?[ben]?.map(\.work) == [try #require(copies[ben])])
        #expect(found["lesson"]?[ben]?.first?.isHersAlone == true, "his own linked copy")
    }

    // MARK: - Words

    @Test("The card line and the Mac tooltip read plainly")
    func words() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let first = lesson("Bead Addition", step: 1, in: context)
        let second = lesson("Stamp Game Addition", step: 2, in: context)
        let third = lesson("Dot Game", step: 3, in: context)
        try work(for: ada, on: first, in: context)
        try work(for: ada, on: second, in: context)
        let items = try #require(try find(third, for: [ada], lessons: [first, second, third], in: context)[ada])

        #expect(WorkToShowFirst.countLine(2) == "2 to check first")
        #expect(WorkToShowFirst.helpText(for: items) == "Still open from earlier: Bead Addition and 1 more")
        #expect(WorkToShowFirst.helpText(for: Array(items.prefix(1))) == "Still open from earlier: Bead Addition")
        #expect(items[0].summary == "Bead Addition, Working")
    }
}

/// A store coordinator that counts the fetches its contexts run. Every
/// `NSManagedObjectContext.fetch` on a context attached straight to it ends
/// up here; faults filled from the row cache do not.
nonisolated private final class CountingCoordinator: NSPersistentStoreCoordinator, @unchecked Sendable {
    nonisolated(unsafe) var fetches = 0

    override func execute(
        _ request: NSPersistentStoreRequest, with context: NSManagedObjectContext
    ) throws -> Any {
        if request.requestType == .fetchRequestType { fetches += 1 }
        return try super.execute(request, with: context)
    }
}
