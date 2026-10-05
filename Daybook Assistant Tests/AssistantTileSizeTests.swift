import Foundation
import Testing
@testable import Daybook_Assistant

// Phone tiles grow to fill a tall screen, never below the SE's size and
// never into slabs. The SE itself shrinks a little so 22 fit.
@Suite("Assistant phone tile size")
struct AssistantTileSizeTests {

    typealias Tile = AttendanceTile
    typealias Screen = AssistantAttendanceView

    @Test("An SE fits 22 children in eight rows below the count, above iOS 26's bottom bar")
    func seFitsTwentyTwo() {
        // About 413 points between the count and the bottom bar on iOS 26.
        let height = Screen.phoneTileHeight(gridHeight: 413, columns: 3, lines: 8, levelBlocks: 0, isSE: true)
        let gap = Screen.phoneGridSpacing(isSE: true)
        #expect(height == Screen.smallestSETileHeight)
        #expect(height < Tile.phoneHeight)
        #expect(height * 8 + gap * 7 <= 413)
    }

    @Test("An SE with room keeps its usual tiles and never grows past them")
    func seRoomyClass() {
        let smallClass = Screen.phoneTileHeight(gridHeight: 413, columns: 3, lines: 6, levelBlocks: 0, isSE: true)
        #expect(smallClass == Tile.phoneHeight)
        let tallRoom = Screen.phoneTileHeight(gridHeight: 900, columns: 3, lines: 8, levelBlocks: 0, isSE: true)
        #expect(tallRoom == Tile.phoneHeight)
    }

    @Test("An SE with a bigger class stops shrinking at its smallest tile, and scrolls")
    func seFloor() {
        let height = Screen.phoneTileHeight(gridHeight: 413, columns: 3, lines: 10, levelBlocks: 0, isSE: true)
        #expect(height == Screen.smallestSETileHeight)
    }

    @Test("Other phones keep the usual gap, and their least is the usual tile")
    func otherPhonesUnchanged() {
        #expect(Screen.phoneGridSpacing(isSE: false) == 8)
        let cramped = Screen.phoneTileHeight(gridHeight: 300, columns: 3, lines: 8, levelBlocks: 0, isSE: false)
        #expect(cramped == Tile.phoneHeight)
        let proMax = Screen.phoneTileHeight(gridHeight: 685, columns: 3, lines: 8, levelBlocks: 0, isSE: false)
        #expect(proMax == 78)
    }

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

    @Test("Grouped on a taller phone, two headings shrink the tiles but keep a tap target")
    func groupedShrinks() {
        // Two 20-point headings with their gaps (52 points) and 8 lines.
        let height = AssistantAttendanceView.phoneTileHeight(
            gridHeight: 490, columns: 3, lines: 8, levelBlocks: 2, isSE: false
        )
        #expect(height < AttendanceTile.phoneHeight)
        #expect(height >= AssistantAttendanceView.smallestGroupedTileHeight)
        #expect(height * 8 + 8 * 7 + 52 <= 490)
    }

    @Test("Grouped on an SE, tiles go down to the grouped minimum, below the SE's own")
    func groupedOnSE() {
        let height = AssistantAttendanceView.phoneTileHeight(
            gridHeight: 413, columns: 3, lines: 8, levelBlocks: 2, isSE: true
        )
        #expect(height == AssistantAttendanceView.smallestGroupedTileHeight)
        #expect(height < AssistantAttendanceView.smallestSETileHeight)
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
