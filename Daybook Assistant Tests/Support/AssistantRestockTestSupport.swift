import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

/// Every suite that sets this phone's identity (`ClassroomIdentity`) or runs
/// the name list's writes (`ClassroomNames.setMyName`,
/// `AssistantNameStore.setInList` / `writeWaitingName`) across an `await`,
/// nested here so they run one at a time. What they share is process-wide:
/// the identity in `UserDefaults.standard`, `AssistantNameStore.writesHeld`,
/// and `ClassroomNames`' gate, `nameSets`, `lookupOut` and `knownZones`.
/// Swift Testing runs suites side by side even with
/// `-parallel-testing-enabled NO`, and `.serialized` on a suite orders only
/// its own tests, so while one suite's test waited another could change who
/// the phone was or overtake its name (the notebook's `ClassroomNamesSuites`,
/// 2026-10-10). A test that sets and puts back the identity without waiting
/// can't be overtaken and stays out. A new suite that waits with any of this
/// set goes in here too (`extension AssistantIdentitySuites`).
@Suite("Assistant identity and names, one suite at a time", .serialized)
@MainActor
enum AssistantIdentitySuites {}

/// Shared by the Restock tab's suites: the guide and Ana, a staple the guide
/// put on the shelf, Ana's tab, and a save that notes what it put into the
/// classroom share.
@MainActor
enum AssistantRestockTestSupport {
    static let guide = RestockAuthor(role: .leadGuide, recordName: "_guide")
    static let ana = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana")

    @discardableResult
    static func staple(
        _ name: String,
        place: String = "Bathrooms",
        source: RestockSource = .office,
        level: RestockLevel = .stocked,
        in context: NSManagedObjectContext
    ) throws -> CDSupply {
        let details = RestockService.StapleDetails(name: name, place: place, source: source)
        let added = try #require(RestockService.addStaple(details, level: level, by: guide, in: context))
        #expect(context.safeSave())
        return added.object
    }

    /// A row in the classroom's list of names, as the share brings it.
    @discardableResult
    static func person(
        _ recordName: String,
        _ name: String,
        role: CDClassroomMembership.ClassroomRole = .assistant,
        at time: Date = Date(),
        in context: NSManagedObjectContext
    ) -> CDClassroomPerson {
        let person = CDClassroomPerson(context: context)
        person.recordName = recordName
        person.role = role
        person.displayName = name
        person.createdAt = time
        person.modifiedAt = time
        #expect(context.safeSave())
        return person
    }

    /// Runs `body` with this phone's identity set to `recordName` and
    /// `name` and no name waiting, then puts back what was there.
    static func asIdentity<T>(_ recordName: String?, named name: String?, _ body: () throws -> T) rethrows -> T {
        let previous = (
            ClassroomIdentity.currentUserRecordName, ClassroomIdentity.displayName, ClassroomIdentity.nameWaitingAs
        )
        defer {
            ClassroomIdentity.currentUserRecordName = previous.0
            ClassroomIdentity.displayName = previous.1
            ClassroomIdentity.nameWaitingAs = previous.2
        }
        ClassroomIdentity.currentUserRecordName = recordName
        ClassroomIdentity.displayName = name
        ClassroomIdentity.nameWaitingAs = nil
        return try body()
    }

    /// `asIdentity`, for a body that waits (the name list's writes do).
    /// Only from a suite nested in `AssistantIdentitySuites`, so no other
    /// suite's identity lands while it waits.
    static func asIdentity<T>(
        _ recordName: String?,
        named name: String?,
        _ body: () async throws -> T
    ) async rethrows -> T {
        let previous = (
            ClassroomIdentity.currentUserRecordName, ClassroomIdentity.displayName, ClassroomIdentity.nameWaitingAs
        )
        defer {
            ClassroomIdentity.currentUserRecordName = previous.0
            ClassroomIdentity.displayName = previous.1
            ClassroomIdentity.nameWaitingAs = previous.2
        }
        ClassroomIdentity.currentUserRecordName = recordName
        ClassroomIdentity.displayName = name
        ClassroomIdentity.nameWaitingAs = nil
        return try await body()
    }

    /// Ana's tab. A long save delay, so each test saves when it says (`flush`).
    static func model(
        in context: NSManagedObjectContext,
        now: Date = Date(),
        author: RestockAuthor = ana,
        save: AssistantRestockModel.Save? = nil
    ) -> AssistantRestockModel {
        let model = AssistantRestockModel(
            context: context, container: nil, author: { author }, saveDelay: .seconds(600), now: { now }, save: save
        )
        model.load()
        return model
    }

    /// What each of the tab's saves put into the classroom share.
    @MainActor
    final class ShareRecorder {
        private(set) var created: [[NSManagedObject]] = []

        func save(_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool {
            self.created.append(created)
            return context.safeSave()
        }
    }
}
