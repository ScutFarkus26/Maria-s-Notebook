import Foundation
import Testing
@testable import CosmicDaybook

/// On the guide's devices Restock names who made a change only when it wasn't
/// her, and a banner counts the Restock records her assistant can't see yet.
@Suite("Restock: who lines and the share banner")
@MainActor
struct RestockWhoLineTests {

    private let guide = RestockTestSupport.guide
    private let ana = RestockTestSupport.ana

    private func at(_ seconds: TimeInterval) -> Date {
        RestockTestSupport.at(seconds)
    }

    // MARK: - A one-off's "added by"

    @Test("Your own one-off carries no label")
    func ownOneOffHasNoLabel() {
        #expect(RestockView.addedByLine(changedByID: "_guide", name: "", viewer: guide) == nil)
        // A guide's change carries no name and, before her ID was known, no ID either.
        #expect(RestockView.addedByLine(changedByID: nil, name: "", viewer: guide) == nil)
    }

    @Test("An assistant's one-off names her")
    func assistantOneOffNamesHer() {
        #expect(RestockView.addedByLine(changedByID: "_ana", name: "Ana", viewer: guide) == "added by Ana")
        #expect(RestockView.addedByLine(changedByID: nil, name: " Ana ", viewer: guide) == "added by Ana")
    }

    @Test("An assistant who gave no name reads as an assistant")
    func namelessAssistantOneOff() {
        #expect(RestockView.addedByLine(changedByID: "_rivka", name: nil, viewer: guide) == "added by an assistant")
    }

    @Test("On an assistant's device, her own one-off has no label and the guide's says so")
    func assistantViewer() {
        #expect(RestockView.addedByLine(changedByID: "_ana", name: "Ana", viewer: ana) == nil)
        #expect(RestockView.addedByLine(changedByID: "_guide", name: "", viewer: ana) == "added by your guide")
    }

    // MARK: - A staple's by-line

    @Test("Your own Low or Out staple shows no by-line")
    func ownStapleHasNoByLine() {
        let line = RestockView.byLine(
            isNeeded: true, changedAt: at(0), changedByID: "_guide", name: "", viewer: guide, now: at(60)
        )
        #expect(line.isEmpty)
    }

    @Test("An assistant's Out staple shows her name and the time today, the day after that")
    func assistantStapleByLine() {
        let today = RestockView.byLine(
            isNeeded: true, changedAt: at(0), changedByID: "_ana", name: "Ana", viewer: guide, now: at(60)
        )
        #expect(today == "Ana · \(DateFormatters.shortTime.string(from: at(0)))")

        let later = at(3 * 86_400)
        let earlier = RestockView.byLine(
            isNeeded: true, changedAt: at(0), changedByID: "_ana", name: "Ana", viewer: guide, now: later
        )
        #expect(earlier == "Ana · \(DateFormatters.shortMonthDay.string(from: at(0)))")
    }

    @Test("A nameless assistant's staple reads \"An assistant\" at the start of the line")
    func namelessAssistantStapleByLine() {
        let line = RestockView.byLine(
            isNeeded: true, changedAt: at(0), changedByID: "_rivka", name: nil, viewer: guide, now: at(60)
        )
        #expect(line == "An assistant · \(DateFormatters.shortTime.string(from: at(0)))")
    }

    @Test("A stocked staple, or one never marked, shows no by-line")
    func stockedStapleHasNoByLine() {
        #expect(RestockView.byLine(
            isNeeded: false, changedAt: at(0), changedByID: "_ana", name: "Ana", viewer: guide, now: at(60)
        ).isEmpty)
        #expect(RestockView.byLine(
            isNeeded: true, changedAt: nil, changedByID: "_ana", name: "Ana", viewer: guide, now: at(60)
        ).isEmpty)
    }

    // MARK: - The share banner

    private func contents(
        inScope: [String: Int],
        shared: [String: Int]
    ) -> ClassroomShareContents {
        var contents = ClassroomShareContents()
        contents.inScope = inScope
        contents.inScopeAndShared = shared
        contents.inShare = shared
        return contents
    }

    @Test("The banner counts only Restock's types, per type")
    func gapCountsRestockTypes() {
        let gap = RestockShareGap(contents(
            inScope: ["Supply": 5, "OrderItem": 2, "SupplyTransaction": 10, "Student": 22, "AttendanceRecord": 400],
            shared: ["Supply": 3, "OrderItem": 2, "SupplyTransaction": 4, "Student": 15, "AttendanceRecord": 100]
        ))
        #expect(gap == RestockShareGap(staples: 2, needs: 0, history: 6))
        #expect(gap.title == "2 shelf items aren't shared with your assistant yet.")
    }

    @Test("A type missing from the read counts as nothing missing, never below zero")
    func gapNeverNegative() {
        let gap = RestockShareGap(contents(inScope: ["Supply": 1], shared: ["Supply": 3]))
        #expect(gap.isEmpty)
        #expect(gap.title == nil)
    }

    @Test("The banner's wording: one, several, staples and needs, history only")
    func bannerWording() {
        #expect(RestockShareGap(staples: 1).title == "1 shelf item isn't shared with your assistant yet.")
        #expect(RestockShareGap(needs: 1).title == "1 list item isn't shared with your assistant yet.")
        #expect(RestockShareGap(staples: 2, needs: 1, history: 9).title
                == "2 shelf items and 1 list item aren't shared with your assistant yet.")
        #expect(RestockShareGap(needs: 3).title == "3 list items aren't shared with your assistant yet.")
        #expect(RestockShareGap(history: 4).title == "Some shelf history isn't shared with your assistant yet.")
        #expect(RestockShareGap().title == nil)
    }

    @Test("The per-type count adds up to the whole-share count Settings shows")
    func perTypeOutsideMatchesTotal() {
        let whole = contents(
            inScope: ["Supply": 5, "OrderItem": 2, "Student": 22],
            shared: ["Supply": 3, "OrderItem": 2, "Student": 15]
        )
        #expect(whole.outside(of: "Supply") == 2)
        #expect(whole.outside(of: "Student") == 7)
        #expect(whole.outside == 9)
    }
}
