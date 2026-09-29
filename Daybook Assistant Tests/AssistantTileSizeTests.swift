import Foundation
import Testing
@testable import Daybook_Assistant

// Phone tiles grow to fill a tall screen, never below the SE's size and
// never into slabs.
@Suite("Assistant phone tile size")
struct AssistantTileSizeTests {

    typealias Tile = AssistantAttendanceTile

    @Test("A Pro Max's room makes 22 children roomy tiles")
    func proMaxFills() {
        // Roughly a 14 Pro Max's grid: 398 wide, about 685 tall.
        let height = Tile.fittedPhoneHeight(visibleHeight: 685, columns: 3, count: 22, spacing: 8)
        #expect(height == 78)
        #expect(height >= Tile.roomyHeight)
        // Eight rows and their gaps still fit.
        #expect(height * 8 + 8 * 7 <= 685)
    }

    @Test("Too little room keeps the SE size, and the grid scrolls")
    func neverBelowSE() {
        #expect(Tile.fittedPhoneHeight(visibleHeight: 300, columns: 3, count: 22, spacing: 8) == Tile.phoneHeight)
    }

    @Test("A small class stops at the tallest size")
    func capped() {
        #expect(Tile.fittedPhoneHeight(visibleHeight: 685, columns: 3, count: 6, spacing: 8) == Tile.tallestPhoneHeight)
    }

    @Test("No children or no columns falls back to the SE size")
    func empty() {
        #expect(Tile.fittedPhoneHeight(visibleHeight: 685, columns: 3, count: 0, spacing: 8) == Tile.phoneHeight)
        #expect(Tile.fittedPhoneHeight(visibleHeight: 685, columns: 0, count: 22, spacing: 8) == Tile.phoneHeight)
    }
}
