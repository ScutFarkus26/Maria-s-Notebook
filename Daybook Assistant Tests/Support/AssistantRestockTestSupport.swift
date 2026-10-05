import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

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
