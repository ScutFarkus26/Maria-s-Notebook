import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The work detail and presentation detail sheets now reload practice sessions
/// on `objectsDidChange` filtered to "PracticeSession" (what their removed
/// `@FetchRequest`s reacted to). Pins that the filter sees practice-session
/// inserts and edits, and ignores other entities.
@MainActor
struct PracticeSessionChangeSignalTests {

    private func touched(after change: (NSManagedObjectContext) -> Void) throws -> Set<String> {
        let context = try CoreDataTestHelpers.makeContext()
        let session = CDPracticeSession(context: context)
        _ = CoreDataTestHelpers.seedNote(in: context)
        try context.save()
        _ = session
        let seen = SeenBox()
        let token = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: nil
        ) { note in
            seen.names.formUnion(ManagedObjectChangeScope.touched(["PracticeSession"], in: note.userInfo))
        }
        defer { NotificationCenter.default.removeObserver(token) }
        change(context)
        context.processPendingChanges()
        return seen.names
    }

    @Test func insertIsSeen() throws {
        #expect(try touched { _ = CDPracticeSession(context: $0) } == ["PracticeSession"])
    }

    @Test func editIsSeen() throws {
        let seen = try touched { context in
            let session = context.safeFetch(CDFetchRequest(CDPracticeSession.self)).first
            session?.workItemIDsArray = [UUID().uuidString]
        }
        #expect(seen == ["PracticeSession"])
    }

    @Test func otherEntitiesAreIgnored() throws {
        #expect(try touched { _ = CoreDataTestHelpers.seedNote(in: $0) }.isEmpty)
    }
}

/// Posted synchronously on the test's own thread (queue: nil), so no locking.
private final class SeenBox: @unchecked Sendable {
    var names: Set<String> = []
}
