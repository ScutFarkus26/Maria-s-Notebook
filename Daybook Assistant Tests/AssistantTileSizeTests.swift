import Foundation
import Testing
@testable import Daybook_Assistant

// Phone tiles grow to fill a tall screen, never below the SE's size and
// never into slabs.
@Suite("Assistant phone tile size")
struct AssistantTileSizeTests {

    typealias Tile = AttendanceTile

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

// Grouped by level, tiles may shrink below the SE size to make room for the
// headings, but no further than a tap target.
@Suite("Assistant grouped tile size")
struct AssistantGroupedTileSizeTests {

    @Test("A lower minimum lets 22 children and two headings fit an SE")
    func groupedFitsSE() {
        // The SE's grid less two 20-point headings with their gaps: 8 lines.
        let height = AttendanceTile.fittedPhoneHeight(
            visibleHeight: 490 - 56, columns: 3, count: 24, spacing: 8,
            minimum: AssistantAttendanceView.smallestGroupedTileHeight
        )
        #expect(height < AttendanceTile.phoneHeight)
        #expect(height >= AssistantAttendanceView.smallestGroupedTileHeight)
        #expect(height * 8 + 8 * 7 <= 490 - 56)
    }

    @Test("It never goes below the grouped minimum")
    func groupedFloor() {
        let height = AttendanceTile.fittedPhoneHeight(
            visibleHeight: 200, columns: 3, count: 24, spacing: 8,
            minimum: AssistantAttendanceView.smallestGroupedTileHeight
        )
        #expect(height == AssistantAttendanceView.smallestGroupedTileHeight)
    }
}
