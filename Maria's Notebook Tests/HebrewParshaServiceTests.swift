import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("HebrewParshaService")
@MainActor
final class HebrewParshaServiceTests {

    // MARK: - Canonical Keys

    @Test("allParshaKeys contains 54 canonical keys in annual-cycle order")
    func allKeysCount() {
        #expect(HebrewParshaService.allParshaKeys.count == 54)
        #expect(HebrewParshaService.allParshaKeys.first == "bereishit")
        #expect(HebrewParshaService.allParshaKeys.last == "vzot-haberachah")
    }

    @Test("every canonical key has a display name")
    func everyKeyHasDisplayName() {
        for key in HebrewParshaService.allParshaKeys {
            let name = HebrewParshaService.displayName(forKey: key)
            #expect(!name.isEmpty)
            #expect(name != key)
        }
    }

    // MARK: - Display Names

    @Test("doubled parshiot display names use an en-dash")
    func doubledParshiotDisplayNames() {
        #expect(HebrewParshaService.displayName(forKey: "vayakhel-pekudei").contains("\u{2013}"))
        #expect(HebrewParshaService.displayName(forKey: "tazria-metzora").contains("\u{2013}"))
        #expect(HebrewParshaService.displayName(forKey: "matot-masei").contains("\u{2013}"))
    }

    @Test("unknown key falls back to capitalized form")
    func unknownKeyFallsBack() {
        #expect(HebrewParshaService.displayName(forKey: "not-a-parsha") == "Not-A-Parsha")
    }

    // MARK: - Shabbat of Week

    @Test("shabbatOfWeek returns the same day when given a Saturday")
    func shabbatOnSaturday() {
        let calendar = Calendar(identifier: .gregorian)
        // 2026-04-25 is a Saturday.
        let components = DateComponents(year: 2026, month: 4, day: 25)
        let saturday = calendar.date(from: components)!
        let result = HebrewParshaService.shabbatOfWeek(containing: saturday, calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: saturday))
    }

    @Test("shabbatOfWeek advances from Sunday to the next Saturday")
    func shabbatFromSunday() {
        let calendar = Calendar(identifier: .gregorian)
        // 2026-04-19 is a Sunday.
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 19))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 4, day: 25))!
        let result = HebrewParshaService.shabbatOfWeek(containing: sunday, calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: expected))
    }

    @Test("shabbatOfWeek advances from Wednesday to the next Saturday")
    func shabbatFromWednesday() {
        let calendar = Calendar(identifier: .gregorian)
        // 2026-04-22 is a Wednesday.
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 22))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 4, day: 25))!
        let result = HebrewParshaService.shabbatOfWeek(containing: wednesday, calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: expected))
    }

    @Test("shabbatOfWeek advances from Friday to the next day")
    func shabbatFromFriday() {
        let calendar = Calendar(identifier: .gregorian)
        // 2026-04-24 is a Friday.
        let friday = calendar.date(from: DateComponents(year: 2026, month: 4, day: 24))!
        let expected = calendar.date(from: DateComponents(year: 2026, month: 4, day: 25))!
        let result = HebrewParshaService.shabbatOfWeek(containing: friday, calendar: calendar)
        #expect(calendar.isDate(result, inSameDayAs: expected))
    }

    // MARK: - Current Parsha (smoke test)

    @Test("currentParshaKey returns a recognized key when it returns a value")
    func currentParshaKeyIsRecognized() {
        // Exercise the algorithm for a range of dates; if it returns non-nil the key
        // must be one of the canonical keys OR a combined doubled-parsha key.
        let calendar = Calendar(identifier: .gregorian)
        let combined: Set<String> = [
            "vayakhel-pekudei", "tazria-metzora", "acharei-mot-kedoshim",
            "behar-bechukotai", "chukat-balak", "matot-masei", "nitzavim-vayelech"
        ]
        let known = Set(HebrewParshaService.allParshaKeys).union(combined)

        for weekOffset in 0..<52 {
            let date = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: Date())!
            if let key = HebrewParshaService.currentParshaKey(on: date) {
                #expect(known.contains(key), "Unknown parsha key returned: \(key)")
            }
        }
    }

    // MARK: - Golden Dates (Diaspora)
    //
    // Reference data sourced from hebcal.com diaspora schedule. Each anchor exercises
    // a different Hebrew year type from the Four Gates table so a future regression
    // in the doubled-parshah lookup is caught here rather than shipping silently.

    private static let goldenAnchors: [(date: DateComponents, key: String, note: String)] = [
        // 5784 — leap, RH=Sat, Incomplete (year-type "170"): Mat-Mas combine; V-P, T-M, A-K, B-B, Ch-B all split.
        (.init(year: 2024, month: 3, day: 9),  "vayakhel",            "5784 leap '170': V-P split"),
        (.init(year: 2024, month: 4, day: 13), "tazria",              "5784 leap '170': T-M split"),
        (.init(year: 2024, month: 7, day: 13), "chukat",              "5784 leap '170': Ch-B split"),
        (.init(year: 2024, month: 8, day: 3),  "matot-masei",         "5784 leap '170': M-M combine"),
        (.init(year: 2024, month: 9, day: 28), "nitzavim-vayelech",   "5784 leap '170': N-V combine"),
        // 5785 — non-leap, RH=Thu, Complete (year-type "052"): V-P split; N-V split.
        // Note: the Vayelech-after-RH-of-next-year edge case (e.g. 2025-09-27) is
        // intentionally not covered here — the algorithm anchors at Simchat Torah and
        // walks forward, so the 1-3 Saturdays per year that fall between Rosh Hashanah
        // and Simchat Torah are out of scope. The "this week" badge simply shows nothing
        // for those weeks; that's acceptable since no weekly parsha is read on most of
        // them anyway (Yom Kippur, Sukkot, etc.).
        (.init(year: 2025, month: 3, day: 22), "vayakhel",            "5785 non-leap '052': V-P split"),
        (.init(year: 2025, month: 5, day: 3),  "tazria-metzora",      "5785 non-leap '052': T-M combine"),
        (.init(year: 2025, month: 5, day: 10), "acharei-mot-kedoshim","5785 non-leap '052': A-K combine"),
        (.init(year: 2025, month: 5, day: 24), "behar-bechukotai",    "5785 non-leap '052': B-B combine"),
        (.init(year: 2025, month: 7, day: 26), "matot-masei",         "5785 non-leap '052': M-M combine"),
        (.init(year: 2025, month: 9, day: 20), "nitzavim",            "5785 non-leap '052': N-V split"),
        // 5786 — non-leap, RH=Tue, Regular (year-type "0310"): all 7 pairs combine.
        (.init(year: 2026, month: 3, day: 14), "vayakhel-pekudei",    "5786 non-leap '0310': V-P combine"),
        (.init(year: 2026, month: 4, day: 25), "acharei-mot-kedoshim","5786 non-leap '0310': A-K combine"),
        (.init(year: 2026, month: 6, day: 27), "chukat-balak",        "5786 non-leap '0310': Ch-B combine"),
        (.init(year: 2026, month: 9, day: 5),  "nitzavim-vayelech",   "5786 non-leap '0310': N-V combine"),
        // 5787 — leap, RH=Sat, Complete (year-type "1720"): T-M split, A-K split.
        (.init(year: 2027, month: 4, day: 10), "tazria",              "5787 leap '1720': T-M split"),
        (.init(year: 2027, month: 5, day: 1),  "acharei-mot",         "5787 leap '1720': A-K split")
    ]

    @Test("currentParshaKey matches hebcal diaspora schedule on golden anchors")
    func goldenAnchorsMatchHebcal() {
        let cal = Calendar(identifier: .gregorian)
        for anchor in Self.goldenAnchors {
            guard let saturday = cal.date(from: anchor.date) else {
                Issue.record("Could not construct date \(anchor.date)")
                continue
            }
            let key = HebrewParshaService.currentParshaKey(on: saturday)
            #expect(key == anchor.key, "\(anchor.note): expected \(anchor.key), got \(key ?? "nil")")
        }
    }
}
