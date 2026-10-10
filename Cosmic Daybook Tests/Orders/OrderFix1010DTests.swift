import CoreData
import Foundation
import LinkPresentation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, Part 1 #20–23: the Draft Request's address field, a
// need editor saved over a title Restock just read, a page that didn't answer,
// and the recipients the classroom share carries.

@Suite("Orders fixes 2026-10-10 (D): address field, editor title, title retries, shared addresses")
@MainActor
struct OrderFix1010DTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func need(_ path: String, in context: NSManagedObjectContext) throws -> CDOrderItem {
        let link = try #require(URL(string: "https://www.example.com/\(path)"))
        return try #require(OrderService.addLinks([link], in: context).first)
    }

    /// The editor's Save: the Name as it stands, with the rest unchanged.
    private func save(_ item: CDOrderItem, name: String, loaded: String?, quantity: Int = 1, notes: String = "") {
        OrderService.update(
            item, title: name, loadedTitle: loaded, urlString: item.urlString, quantity: quantity, notes: notes
        )
    }

    // MARK: - #20 The draft's address field

    @Test("The address fields stay while she types, even once the address reads as finished")
    func addressFieldStaysWhileTyping() {
        let none = OrderRequestRecipient(name: "", email: "")
        var panel = OrderRequestRecipientPanel(opening: none)
        #expect(!panel.showsSummary)

        // Partway through ".com", "frontdesk@school.co" is already an address;
        // nothing she types moves the panel.
        let partway = OrderRequestRecipient(name: "", email: "frontdesk@school.co")
        #expect(partway.isConfigured)
        #expect(!panel.showsSummary)

        // Done with nothing usable keeps the fields; with an address, the summary.
        panel.done(with: OrderRequestRecipient(name: "", email: "frontdesk@"))
        #expect(!panel.showsSummary)
        panel.done(with: OrderRequestRecipient(name: "", email: "frontdesk@school.com"))
        #expect(panel.showsSummary)
    }

    @Test("A recipient already set opens as the summary, and Change shows the fields until Done")
    func setRecipientOpensAsSummary() {
        let office = OrderRequestRecipient(name: "Ms. Rivera", email: "office@school.org")
        var panel = OrderRequestRecipientPanel(opening: office)
        #expect(panel.showsSummary)
        panel.change()
        #expect(!panel.showsSummary)
        panel.done(with: office)
        #expect(panel.showsSummary)
    }

    // MARK: - #21 The need editor's Name field

    @Test("Saving the editor with an untouched Name keeps a title that landed while it was open")
    func untouchedNameKeepsFetchedTitle() throws {
        let context = try makeContext()
        let item = try need("pencils", in: context)
        let loaded = item.title
        #expect(loaded.isEmpty)

        // Restock reads the page while the editor is open.
        #expect(RestockService.applyFetchedTitle("Crayola Colored Pencils | Amazon", to: item))
        save(item, name: loaded, loaded: loaded, quantity: 3, notes: "24 ct")

        #expect(item.title == "Crayola Colored Pencils")
        #expect(item.quantity == 3)
        #expect(item.notes == "24 ct")
    }

    @Test("A Name she typed or cleared is saved, and the MCP's edit (no loaded name) writes as before")
    func editedNameIsSaved() throws {
        let context = try makeContext()
        let item = try need("rods", in: context)
        item.title = "Rods"

        save(item, name: "Bead rods", loaded: "Rods")
        #expect(item.title == "Bead rods")
        save(item, name: "", loaded: "Bead rods")
        #expect(item.title.isEmpty, "clearing the Name is an edit too")
        item.title = "Rods"
        save(item, name: "Golden bead rods", loaded: nil)
        #expect(item.title == "Golden bead rods")
    }

    // MARK: - #22 A page that didn't answer

    @Test("A page that didn't answer is read again next time; one that answered without a title isn't")
    func noAnswerIsReadAgain() async throws {
        let context = try makeContext()
        let offline = CDOrderItem(context: context)
        offline.urlString = "https://www.example.com/offline-\(UUID().uuidString)"
        let untitled = CDOrderItem(context: context)
        untitled.urlString = "https://www.example.com/untitled-\(UUID().uuidString)"
        #expect(CoreDataTestHelpers.save(context))

        // Offline when Restock first appears.
        await OrderLinkTitleFetcher.fillUntitled([offline], fetch: { _ in .noAnswer }, save: {})
        #expect(offline.title.isEmpty)
        #expect(OrderLinkTitleFetcher.untitledNeeds([offline]) == [offline], "not answered: read again")

        // Back online, the next appearance fills it in.
        var saves = 0
        await OrderLinkTitleFetcher.fillUntitled(
            [offline], fetch: { _ in .title("Elmer's Glue Sticks | Amazon") }, save: { saves += 1 }
        )
        #expect(offline.title == "Elmer's Glue Sticks")
        #expect(saves == 1)

        // A page that answers with no title isn't asked again this launch.
        await OrderLinkTitleFetcher.fillUntitled([untitled], fetch: { _ in .noTitle }, save: {})
        #expect(OrderLinkTitleFetcher.untitledNeeds([untitled]).isEmpty)
    }

    @Test("Only the network being away counts as no answer; a dead link or a refusal is an answer")
    func readErrorsSorted() {
        func urlError(_ code: Int) -> NSError { NSError(domain: NSURLErrorDomain, code: code) }
        func previewError(_ code: LPError.Code, underlying: NSError? = nil) -> NSError {
            NSError(domain: LPErrorDomain, code: code.rawValue,
                    userInfo: underlying.map { [NSUnderlyingErrorKey: $0] } ?? [:])
        }
        let away: [NSError] = [
            urlError(NSURLErrorNotConnectedToInternet),
            urlError(NSURLErrorNetworkConnectionLost),
            urlError(NSURLErrorTimedOut),
            previewError(.metadataFetchTimedOut),
            previewError(.metadataFetchFailed, underlying: urlError(NSURLErrorNotConnectedToInternet))
        ]
        for error in away {
            #expect(OrderLinkTitleFetcher.answer(for: error) == .noAnswer, "\(error)")
        }
        let answered: [NSError] = [
            previewError(.metadataFetchFailed),
            previewError(.metadataFetchNotAllowed),
            urlError(NSURLErrorCannotFindHost),
            urlError(NSURLErrorBadServerResponse),
            previewError(.metadataFetchFailed, underlying: urlError(NSURLErrorCannotConnectToHost))
        ]
        for error in answered {
            #expect(OrderLinkTitleFetcher.answer(for: error) == .noTitle, "\(error)")
        }
    }

    @Test("A page that keeps not answering is read at most three times a launch")
    func unansweredReadsAreCapped() async throws {
        let context = try makeContext()
        let offline = CDOrderItem(context: context)
        offline.urlString = "https://www.example.com/away-\(UUID().uuidString)"
        #expect(CoreDataTestHelpers.save(context))

        var reads = 0
        for _ in 0..<5 {
            await OrderLinkTitleFetcher.fillUntitled([offline], fetch: { _ in
                reads += 1
                return .noAnswer
            }, save: {})
        }
        #expect(OrderLinkTitleFetcher.unansweredReadLimit == 3)
        #expect(reads == 3)
        #expect(OrderLinkTitleFetcher.untitledNeeds([offline]).isEmpty)
    }

    // MARK: - #23 The addresses the share carries

    @Test("The share carries the typed addresses joined with commas, whatever separated them")
    func sharedAddressLine() {
        #expect(AttendanceEmail.sharedAddressLine("office@school.org nurse@school.org")
            == "office@school.org, nurse@school.org")
        #expect(AttendanceEmail.sharedAddressLine("office@school.org;\nnurse@school.org , <head@school.org>")
            == "office@school.org, nurse@school.org, head@school.org")
        #expect(AttendanceEmail.sharedAddressLine("office@school.org and nurse") == "office@school.org")
        #expect(AttendanceEmail.sharedAddressLine(nil).isEmpty)
    }

    @Test("The guide's settings go to the share as clean addresses an older Assistant can read")
    func storedSettingsShareCleanAddresses() {
        let store = SyncedPreferencesStore.shared
        let saved = store.get(key: AttendanceEmailPrefs.toKey)
        defer { store.set(saved, forKey: AttendanceEmailPrefs.toKey) }
        store.set("office@school.org nurse@school.org", forKey: AttendanceEmailPrefs.toKey)

        let shared = AttendanceEmail.storedSettings().toAddresses
        #expect(shared == "office@school.org, nurse@school.org")
        // An Assistant from before spaces counted splits only on commas and
        // semicolons: every piece is still one whole address.
        let olderRead = shared.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(olderRead == ["office@school.org", "nurse@school.org"])
        #expect(olderRead.allSatisfy(AttendanceEmail.isAddress))
    }
}
