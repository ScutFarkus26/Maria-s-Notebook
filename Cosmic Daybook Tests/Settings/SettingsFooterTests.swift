import Foundation
import Testing
@testable import CosmicDaybook

/// Pins the footer's easter egg (five taps in a row, a pause starts over) and keeps its
/// phrases short, and the star layout steady between redraws.
@Suite("Settings footer")
@MainActor
struct SettingsFooterTests {

    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("Five quick taps toggle; the fifth is the one that counts")
    func fiveQuickTapsHit() {
        var counter = CosmicTapCounter()
        let hits = (0..<5).map { counter.register(at: start.addingTimeInterval(Double($0) * 0.3)) }
        #expect(hits == [false, false, false, false, true])
        #expect(counter.count == 0)
    }

    @Test("A pause longer than the window starts the count over")
    func pauseResets() {
        var counter = CosmicTapCounter()
        for index in 0..<4 {
            _ = counter.register(at: start.addingTimeInterval(Double(index) * 0.3))
        }
        let afterPause = start.addingTimeInterval(0.9 + CosmicTapCounter.window + 0.1)
        let hit = counter.register(at: afterPause)
        #expect(!hit)
        #expect(counter.count == 1)
    }

    @Test("Ten quick taps toggle twice, so five more turn the stars back off")
    func tenTapsToggleTwice() {
        var counter = CosmicTapCounter()
        let hits = (0..<10).filter { counter.register(at: start.addingTimeInterval(Double($0) * 0.2)) }
        #expect(hits == [4, 9])
    }

    @Test("Every phrase is short and ends with a period")
    func phrasesAreShort() {
        #expect(SettingsFooterView.quotes.count >= 3)
        for quote in SettingsFooterView.quotes {
            #expect(quote.split(separator: " ").count <= 8, "Too long: \(quote)")
            #expect(quote.hasSuffix("."))
        }
    }

    @Test("The starfield is the same sky every time, inside its frame")
    func starLayoutIsStable() {
        let first = CosmicStarLayout.makeStars(count: 20, seed: 7)
        let second = CosmicStarLayout.makeStars(count: 20, seed: 7)
        #expect(first.map(\.x) == second.map(\.x))
        #expect(first.map(\.y) == second.map(\.y))
        #expect(first.allSatisfy { (0..<1).contains($0.x) && (0..<1).contains($0.y) })
    }
}
