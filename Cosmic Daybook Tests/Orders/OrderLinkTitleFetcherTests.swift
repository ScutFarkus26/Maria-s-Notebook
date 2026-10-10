import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Which needs get their page's title filled in when Restock appears or the
/// request draft opens, and that a page being read by one screen isn't read
/// again by the other (bug hunt 2026-10-09 #22).
@Suite("Order link titles")
@MainActor
struct OrderLinkTitleFetcherTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    @Test("Untitled open needs with a web link are the ones whose titles get filled in")
    func untitledNeeds() throws {
        let context = try makeContext()
        func need(_ title: String, link: String) -> CDOrderItem {
            let item = CDOrderItem(context: context)
            item.title = title
            item.urlString = link
            return item
        }
        let pasted = need("", link: "https://www.example.com/glue")
        let named = need("Glue", link: "https://www.example.com/glue2")
        let noLink = need("", link: "")
        let received = need("", link: "https://www.example.com/tape")
        received.receivedAt = Date()
        let all = [pasted, named, noLink, received]
        #expect(OrderLinkTitleFetcher.untitledNeeds(all).isEmpty, "nothing unsaved is read")
        #expect(CoreDataTestHelpers.save(context))
        #expect(OrderLinkTitleFetcher.untitledNeeds(all) == [pasted])
    }

    @Test("A page being read isn't read again by the other screen, and counts as tried only once it answers")
    func titleReadOnceWhileInFlight() async throws {
        let context = try makeContext()
        let pencils = CDOrderItem(context: context)
        pencils.urlString = "https://www.example.com/pencils"
        let silent = CDOrderItem(context: context)
        silent.urlString = "https://www.example.com/no-title"
        #expect(CoreDataTestHelpers.save(context))

        // Restock starts reading the pencils' page, which hasn't answered yet.
        let gate = PageGate()
        let restock = Task {
            await OrderLinkTitleFetcher.fillUntitled([pencils], fetch: gate.fetch) {}
        }
        await gate.waitUntilAsked()
        #expect(OrderLinkTitleFetcher.untitledNeeds([pencils, silent]) == [silent], "in flight: left to Restock")

        // The draft opens meanwhile: it reads only the page nobody is reading.
        var draftReads: [URL] = []
        await OrderLinkTitleFetcher.fillUntitled([pencils, silent], fetch: { url in
            draftReads.append(url)
            return nil
        }, save: {})
        #expect(draftReads.map(\.absoluteString) == ["https://www.example.com/no-title"])
        #expect(OrderLinkTitleFetcher.untitledNeeds([silent]).isEmpty, "answered with no title: tried")

        var laterReads = 0
        gate.answer("Crayola Colored Pencils | Amazon")
        await restock.value
        #expect(pencils.title == "Crayola Colored Pencils")
        #expect(OrderLinkTitleFetcher.untitledNeeds([pencils]).isEmpty)
        // Once done, nothing is read again.
        await OrderLinkTitleFetcher.fillUntitled([pencils, silent], fetch: { _ in
            laterReads += 1
            return "Again"
        }, save: {})
        #expect(laterReads == 0)
    }
}

/// A page that answers when the test says: `fetch` waits until `answer`.
@MainActor
private final class PageGate {
    private var page: CheckedContinuation<String?, Never>?
    private var asked: CheckedContinuation<Void, Never>?

    func fetch(_ url: URL) async -> String? {
        await withCheckedContinuation { continuation in
            page = continuation
            asked?.resume()
            asked = nil
        }
    }

    /// Returns once `fetch` has been called.
    func waitUntilAsked() async {
        guard page == nil else { return }
        await withCheckedContinuation { asked = $0 }
    }

    func answer(_ title: String?) {
        page?.resume(returning: title)
        page = nil
    }
}
