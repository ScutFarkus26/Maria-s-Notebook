import Foundation
import Testing
@testable import Daybook_Assistant

// Down puts the alphabet down the columns of a row-by-row grid.
@Suite("Assistant grid order")
struct AssistantGridOrderTests {

    @Test("Across leaves the alphabetical list as it is")
    func acrossUnchanged() {
        let names = Array(0..<22)
        #expect(AssistantGridOrder.across.arranged(names, columns: 3) == names)
    }

    @Test("Down fills each column top to bottom, the first a child longer")
    func downUneven() {
        // 22 in three columns: 8, 7, 7, so the grid reads
        //  0  8 15
        //  1  9 16
        //  ...
        //  6 14 21
        //  7
        let grid = AssistantGridOrder.down.arranged(Array(0..<22), columns: 3)
        #expect(grid.count == 22)
        #expect(Array(grid.prefix(6)) == [0, 8, 15, 1, 9, 16])
        #expect(Array(grid.suffix(4)) == [6, 14, 21, 7])
        #expect(Set(grid) == Set(0..<22))
    }

    @Test("Down with full columns, and with two short ones")
    func downEvenAndShort() {
        #expect(AssistantGridOrder.down.arranged(Array(0..<6), columns: 3) == [0, 2, 4, 1, 3, 5])
        // 7 in three: 3, 2, 2.
        #expect(AssistantGridOrder.down.arranged(Array(0..<7), columns: 3) == [0, 3, 5, 1, 4, 6, 2])
    }

    @Test("A class no longer than one row is the same either way")
    func oneRow() {
        #expect(AssistantGridOrder.down.arranged([0, 1, 2], columns: 3) == [0, 1, 2])
        #expect(AssistantGridOrder.down.arranged([0, 1, 2], columns: 1) == [0, 1, 2])
    }

    @Test("An unknown setting reads as across")
    func resolved() {
        #expect(AssistantGridOrder.resolved("sideways") == .across)
        #expect(AssistantGridOrder.resolved("down") == .down)
    }
}

// Group by Level: one block per level, in the front-desk email's order.
@Suite("Assistant level groups")
struct AssistantLevelGroupsTests {

    @Test("Blocks run Upper, Adolescent, Lower, each keeping its order")
    func order() {
        let children: [(String, CDStudent.Level)] = [
            ("Ari", .lower), ("Ben", .adolescent), ("Cal", .upper), ("Dov", .adolescent), ("Eli", .upper)
        ]
        let groups = AssistantLevelGroups.grouped(children) { $0.1 }
        #expect(groups.map(\.level) == [.upper, .adolescent, .lower])
        #expect(groups.map { $0.items.map(\.0) } == [["Cal", "Eli"], ["Ben", "Dov"], ["Ari"]])
    }

    @Test("Empty levels are left out")
    func emptyLevels() {
        let groups = AssistantLevelGroups.grouped([("Ari", CDStudent.Level.upper)]) { $0.1 }
        #expect(groups.map(\.level) == [.upper])
        #expect(AssistantLevelGroups.grouped([(String, CDStudent.Level)]()) { $0.1 }.isEmpty)
    }
}
