import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Shared by the Restock suites: a guide and an assistant, fixed times, and a
/// staple added by the guide.
@MainActor
enum RestockTestSupport {
    static let guide = RestockAuthor(role: .leadGuide, recordName: "_guide")
    static let ana = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana")

    static func at(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_790_000_000 + seconds)
    }

    static func staple(
        _ name: String,
        place: String = "",
        source: RestockSource = .office,
        link: URL? = nil,
        in context: NSManagedObjectContext
    ) throws -> CDSupply {
        let details = RestockService.StapleDetails(name: name, place: place, source: source, link: link)
        return try #require(RestockService.addStaple(details, by: guide, at: at(0), in: context)).object
    }

    static func allNeeds(in context: NSManagedObjectContext) -> [CDOrderItem] {
        context.safeFetch(CDFetchRequest(CDOrderItem.self))
    }
}
