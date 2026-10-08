import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Links trimmed to the product page and titles cut to a name, so the office
/// email stops printing ~560 characters of Amazon search tracking. Only the
/// link and title change: the email's wording stays as `OrderServiceTests`
/// pins it.
@Suite("Order link cleaner")
@MainActor
struct OrderLinkCleanerTests {

    /// The live charger order's link as the 2026-10-03 Restock canvas shows it
    /// (the canvas elides the middle of its `dib` token).
    static let chargerLink = "https://www.amazon.com/Anker-Charger-Foldable-iPhone-Included/dp/B0B2MMB4LJ/"
        + "ref=sr_1_3_pp?crid=H5229TGO5444&dib=eyJ2IjoiMSJ9.xdCNsw1pVHX3a6l0_ryeQtGk-h1aMX3MMOU3ILAPw8mYMVbXy_"
        + "vUkKp_DDbZPlRcG82i0W25Ahnht32vFgY7yMOytyV7LE0_VRd9O09coqTBohK7E62ffQ92CtV7iyUGILga4bKLgLNmqL43Bur"
        + "byOmcJmDeIQs0v5MYEPkZh33YyxcNqpJq8LquZl-yRl0fyWgdG9L0RGsIvALqwd7lQz0gOb6EwStdH_Q5oTDuT34"
        + "&keywords=anker&qid=1790172666&sr=8-3&th=1"
    static let chargerTitle = "Anker Nano Phone Charger, 30W Portble and Foldable USB C GaN Charger | "
        + "For iPhone 18 Pro/17/17 Plus/17 Pro Max/16/16 Plus/16 Pro Max/15 Pro"

    /// The live hub order's product number in a search-result link of the same
    /// shape (its full text wasn't kept).
    static let hubLink = "https://www.amazon.com/ABFCRTTW-Desktop-Aluminium-Extender-Multiport/dp/B0F8BBBGBM/"
        + "ref=sr_1_1_sspa?crid=2Q9RXOWFQ3JHU&keywords=usb+hub+7+port&qid=1790172702&sr=8-1-spons&psc=1"
    static let hubTitle = "ABFCRTTW 4FT 7-Port USB Hub 3.0 for Desktop, Aluminium USB Extender Hub | "
        + "5Gbps USB Multiport Adapter with 4 USB-A & 3 USB-C Ports , USB"

    // MARK: - Links

    @Test("An Amazon product link becomes the bare product page")
    func amazonLinks() {
        #expect(OrderLinkCleaner.clean(Self.chargerLink) == "https://www.amazon.com/dp/B0B2MMB4LJ")
        #expect(OrderLinkCleaner.clean(Self.hubLink) == "https://www.amazon.com/dp/B0F8BBBGBM")
        #expect(OrderLinkCleaner.clean(" https://smile.amazon.com/gp/product/b0f8bbbgbm?psc=1 ")
            == "https://www.amazon.com/dp/B0F8BBBGBM")
        #expect(OrderLinkCleaner.clean("http://amazon.com/dp/B0B2MMB4LJ") == "https://www.amazon.com/dp/B0B2MMB4LJ")
    }

    @Test("Anywhere else only the tracking goes, and the rest of the link is left exactly as it was")
    func trackingParameters() {
        let tracked = "https://www.example.com/p?id=7&utm_source=news&UTM_Medium=email&fbclid=x#top"
        #expect(OrderLinkCleaner.clean(tracked) == "https://www.example.com/p?id=7#top")
        #expect(OrderLinkCleaner.clean("https://www.example.com/p?utm_source=x&gclid=y")
            == "https://www.example.com/p")
        let plain = "https://shop.example.com/search?q=glue%20sticks&page=2"
        #expect(OrderLinkCleaner.clean(plain) == plain)
        // Not a product page, and not Amazon's US store: nothing to trim.
        let search = "https://www.amazon.com/s?k=glue&ref=nb_sb"
        #expect(OrderLinkCleaner.clean(search) == search)
        #expect(OrderLinkCleaner.clean("https://www.amazon.co.uk/dp/B0B2MMB4LJ?th=1")
            == "https://www.amazon.co.uk/dp/B0B2MMB4LJ?th=1")
    }

    @Test("Text that isn't a web link comes back trimmed")
    func notLinks() {
        #expect(OrderLinkCleaner.clean("  glue sticks  ") == "glue sticks")
        let mail = "mailto:office@school.org?utm_source=x"
        #expect(OrderLinkCleaner.clean(mail) == mail)
        #expect(OrderLinkCleaner.clean("") == "")
    }

    // MARK: - Titles

    @Test("A title is cut at its first bar, then at the last comma or dash before 60 characters")
    func shortTitles() {
        #expect(OrderLinkCleaner.shortTitle(Self.chargerTitle) == "Anker Nano Phone Charger")
        #expect(OrderLinkCleaner.shortTitle(Self.hubTitle) == "ABFCRTTW 4FT 7-Port USB Hub 3.0 for Desktop")
        #expect(OrderLinkCleaner.shortTitle("Glue Sticks | Elmer's | School Supplies") == "Glue Sticks")
        #expect(OrderLinkCleaner.shortTitle(
            "Crayola Colored Pencils - 24 Count, Pre-sharpened, Assorted Colors, School Supplies For Kids"
        ) == "Crayola Colored Pencils - 24 Count, Pre-sharpened")
        let unbroken = "Extra Large Washable Classroom Tempera Paint Set With Twelve Bright Colors"
        #expect(OrderLinkCleaner.shortTitle(unbroken) == unbroken, "no place to cut: it stays whole")
        #expect(OrderLinkCleaner.shortTitle("  Stapler  ") == "Stapler")
    }

    // MARK: - Where it runs

    @Test("Adding a link stores it clean, and its tracked twin counts as the same link")
    func addingCleansLinks() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let charger = try #require(URL(string: Self.chargerLink))
        let item = try #require(OrderService.addLinks([charger], in: context).first)
        #expect(item.urlString == "https://www.amazon.com/dp/B0B2MMB4LJ")
        #expect(item.source == .order)
        let bare = try #require(URL(string: "https://www.amazon.com/dp/B0B2MMB4LJ"))
        #expect(OrderService.addLinks([bare], in: context).isEmpty, "already on the list")
    }

    @Test("The request email prints the clean link and the short title, and nothing else changes")
    func emailUsesCleanLinkAndShortTitle() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // Stored the way the two live orders were, before the cleaner existed.
        let item = CDOrderItem(context: context)
        item.urlString = Self.chargerLink
        item.title = Self.chargerTitle
        item.quantity = 2
        let line = OrderRequestLine(item)
        #expect(line.link == "https://www.amazon.com/dp/B0B2MMB4LJ")
        #expect(line.title == "Anker Nano Phone Charger")
        let body = OrderRequestMessage.body(for: [line], recipientName: "Maria", signOff: "Danny")
        #expect(body == """
            Hi Maria,

            Could you please order this for my classroom?

            1. Anker Nano Phone Charger — https://www.amazon.com/dp/B0B2MMB4LJ
                Quantity: 2

            Thank you!
            Danny
            """)
        #expect(OrderRequestMessage.subject(for: [line]) == "Order request: Anker Nano Phone Charger")
    }
}
