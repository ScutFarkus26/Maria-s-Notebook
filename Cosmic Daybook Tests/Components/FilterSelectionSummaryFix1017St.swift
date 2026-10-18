import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, #44: a filter chip said "1 Students" once the chosen
/// child was gone from the menu. It counts only the chosen ids still among
/// the items.
@Suite("Filter chip summary (fix 10-17 St)")
struct FilterSelectionSummaryFix1017StTests {

    private struct Child {
        let id: UUID
        let name: String
    }

    private let summary = FilterSelectionSummary(allLabel: "All Students")
    private let maya = Child(id: UUID(), name: "Maya S")
    private let eli = Child(id: UUID(), name: "Eli R")

    private func text(_ selection: Set<UUID>) -> String {
        summary.text(for: selection, items: [maya, eli], id: { $0.id }, label: { $0.name })
    }

    @Test("A chosen child who is gone isn't counted")
    func goneChildIsNotCounted() {
        let gone = UUID()
        #expect(text([gone]) == "All Students")
        #expect(text([gone, maya.id]) == "Maya S")
        #expect(text([gone, maya.id, eli.id]) == "2 Students")
    }

    @Test("Children still in the menu read as before")
    func presentChildrenReadAsBefore() {
        #expect(text([]) == "All Students")
        #expect(text([eli.id]) == "Eli R")
        #expect(text([maya.id, eli.id]) == "2 Students")
    }
}
