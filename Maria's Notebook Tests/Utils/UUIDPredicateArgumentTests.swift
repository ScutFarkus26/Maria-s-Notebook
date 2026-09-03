import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Documents how a `UUID` attribute compares against a `String` predicate
/// argument in each store type the app uses. Several foreign keys are stored
/// as `uuidString` and were historically compared straight against the
/// `id` attribute without parsing them back into a `UUID`.
///
/// Serialized because a mismatched argument can raise an uncaught
/// Objective-C exception inside Core Data, which takes the whole test
/// process down; running one case at a time keeps the attribution honest.
@Suite(.serialized)
@MainActor
struct UUIDPredicateArgumentTests {

    enum Store: String {
        case inMemory, sqlite

        /// Returns a context plus the owner that keeps its stores alive for the
        /// duration of the test.
        @MainActor
        func makeContext() throws -> (context: NSManagedObjectContext, owner: AnyObject?) {
            switch self {
            case .inMemory:
                let stack = try CoreDataTestHelpers.makeInMemoryStack()
                return (stack.viewContext, stack)
            case .sqlite:
                return (try CoreDataTestHelpers.makeSplitStoreContext(), nil)
            }
        }
    }

    private func seededLesson(in context: NSManagedObjectContext) throws -> (CDLesson, UUID) {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Predicate Probe")
        let id = try #require(lesson.id)
        try context.save()
        return (lesson, id)
    }

    private func fetch(_ argument: CVarArg, in context: NSManagedObjectContext) -> CDLesson? {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", argument)
        request.fetchLimit = 1
        return context.safeFetchFirst(request)
    }

    // MARK: - Safe in every store

    @Test("A UUID argument matches", arguments: [Store.inMemory, .sqlite])
    func uuidArgument(store: Store) throws {
        let (context, owner) = try store.makeContext()
        defer { withExtendedLifetime(owner) {} }
        let (lesson, id) = try seededLesson(in: context)
        #expect(fetch(id as CVarArg, in: context) === lesson)
    }

    @Test("The canonical helper matches from a parsed uuidString", arguments: [Store.inMemory, .sqlite])
    func helperFromParsedString(store: Store) throws {
        let (context, owner) = try store.makeContext()
        defer { withExtendedLifetime(owner) {} }
        let (lesson, id) = try seededLesson(in: context)
        let parsed = try #require(UUID(uuidString: id.uuidString))
        #expect(context.object(CDLesson.self, id: parsed) === lesson)
    }

    // MARK: - String arguments, one store per test so a crash is attributable

    @Test("SQLite: a uuidString argument compared against a UUID attribute")
    func sqliteStringArgument() throws {
        let (context, owner) = try Store.sqlite.makeContext()
        defer { withExtendedLifetime(owner) {} }
        let (lesson, id) = try seededLesson(in: context)
        #expect(fetch(id.uuidString, in: context) === lesson)
    }

    /// The in-memory store compares the string against the UUID without
    /// coercing it, so the lookup silently finds nothing. This is the store
    /// the app falls back to when its on-disk stores cannot be opened.
    @Test("In-memory: a uuidString argument matches nothing")
    func inMemoryStringArgument() throws {
        let (context, owner) = try Store.inMemory.makeContext()
        defer { withExtendedLifetime(owner) {} }
        let (_, id) = try seededLesson(in: context)
        #expect(fetch(id.uuidString, in: context) == nil)
    }

    /// Observed 2026-09-03: the SQLite store raises an uncaught Objective-C
    /// exception from `-[NSSQLiteConnection execute]` when the string cannot
    /// be coerced to a UUID, which `safeFetch`'s `do/catch` cannot intercept
    /// and which takes the whole process down. Disabled so the suite stays
    /// runnable; kept as the record of why String foreign keys must be parsed
    /// with `UUID(uuidString:)` before being compared against `id`.
    @Test("SQLite: a string that is not a UUID crashes the process",
          .disabled("Raises an uncaught NSSQLiteConnection exception; see the doc comment"))
    func sqliteGarbageString() throws {
        let (context, owner) = try Store.sqlite.makeContext()
        defer { withExtendedLifetime(owner) {} }
        _ = try seededLesson(in: context)
        #expect(fetch("not-a-uuid", in: context) == nil)
    }

    @Test("In-memory: a string that is not a UUID matches nothing")
    func inMemoryGarbageString() throws {
        let (context, owner) = try Store.inMemory.makeContext()
        defer { withExtendedLifetime(owner) {} }
        _ = try seededLesson(in: context)
        #expect(fetch("not-a-uuid", in: context) == nil)
    }
}
