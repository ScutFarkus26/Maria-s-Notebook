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
