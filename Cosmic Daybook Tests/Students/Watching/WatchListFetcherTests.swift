import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `WatchListFetcher` reads the three sources with the same predicates the
/// `@FetchRequest`s use, and its todo predicate agrees with the builder.
@Suite("WatchList Fetcher")
@MainActor
struct WatchListFetcherTests {

    private struct Seed {
        let context: NSManagedObjectContext
        let alice: UUID
        let ben: UUID
        let flaggedNote: CDNote
        let watchTodo: CDTodoItem
        let activeGoal: CDStudentFocusItem
    }

    private func seed() throws -> Seed {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let alice = try #require(
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Alice", lastName: "Levi").id
        )
        let ben = try #require(
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Katz").id
        )

        let flagged = CoreDataTestHelpers.seedNote(in: context, body: "Alice needs the carries shown again.")
        flagged.scope = .student(alice)
        flagged.needsFollowUp = true
        let unflagged = CoreDataTestHelpers.seedNote(in: context, body: "Alice finished the map.")
        unflagged.scope = .student(alice)

        let watch = CDTodoItem(context: context)
        watch.title = "WATCH Alice with the stamp game"
        watch.resolvedStudentIDs = [alice]
        let call = CDTodoItem(context: context)
        call.title = "Call parents"
        call.resolvedStudentIDs = [alice]

        let meetingID = UUID()
        let active = FocusItemService.create(
            studentID: alice, text: "Finish racks and tubes", meetingID: meetingID, sortOrder: 0, context: context
        )
        let resolved = FocusItemService.create(
            studentID: alice, text: "Pick a civilization", meetingID: meetingID, sortOrder: 1, context: context
        )
        FocusItemService.resolve(resolved, inMeetingID: meetingID)
        CoreDataTestHelpers.save(context)

        return Seed(
            context: context, alice: alice, ben: ben,
            flaggedNote: flagged, watchTodo: watch, activeGoal: active
        )
    }

    @Test("fetchAll returns the flagged note, the Watch todo and the active goal — nothing else")
    func fetchAllReturnsThreeRows() throws {
        let seed = try seed()
        let items: [WatchItem] = WatchListFetcher.fetchAll(in: seed.context)
        #expect(items.count == 3)
        let noteID: UUID = try #require(seed.flaggedNote.id)
        let todoID: UUID = try #require(seed.watchTodo.id)
        let goalID: UUID = try #require(seed.activeGoal.id)
        let expectedIDs: Set<UUID> = [noteID, todoID, goalID]
        let expectedKinds: Set<WatchItemKind> = [.flaggedNote, .watchTodo, .goal]
        #expect(Set(items.map(\.sourceID)) == expectedIDs)
        #expect(Set(items.map(\.kind)) == expectedKinds)
    }

    @Test("fetch(for:) gives Alice three rows and Ben none")
    func fetchForStudent() throws {
        let seed = try seed()
        #expect(WatchListFetcher.fetch(for: seed.alice, in: seed.context).count == 3)
        #expect(WatchListFetcher.fetch(for: seed.ben, in: seed.context).isEmpty)
    }

    @Test("The todo predicate is case-insensitive and agrees with the builder")
    func todoPredicateMatchesBuilder() throws {
        let seed = try seed()
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = WatchListFetcher.watchTodoPredicate
        let fetched = seed.context.safeFetch(request)
        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "WATCH Alice with the stamp game")
        for todo in seed.context.safeFetch(CDFetchRequest(CDTodoItem.self)) {
            let byPredicate = fetched.contains { $0.objectID == todo.objectID }
            #expect(byPredicate == WatchListBuilder.isWatchTodo(title: todo.title))
        }
    }

    @Test("enrolledIDs leaves out a withdrawn child")
    func enrolledIDs() throws {
        let seed = try seed()
        let gone = CoreDataTestHelpers.seedStudent(
            in: seed.context, firstName: "Naomi", lastName: "Levin", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.save(seed.context)
        let ids = WatchListFetcher.enrolledIDs(in: seed.context)
        #expect(ids == [seed.alice, seed.ben])
        #expect(!ids.contains(try #require(gone.id)))
    }
}
