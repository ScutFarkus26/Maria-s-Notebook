import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11 #61: a section header dropped on the next section, or
/// on the last one, left the order as it was.
@Suite("Scope map: dragging a section header (bug hunt 10-11)")
struct ScopeMapSectionDragFix1011ATests {

    private let names = ["Introduction", "Practice", "Extensions"]

    @Test("A section dropped on the next one moves below it")
    func dropOnNextMovesDown() {
        #expect(LessonsScopeThreadFocusView.sectionOrder(names, moving: "Introduction", onto: "Practice")
                == ["Practice", "Introduction", "Extensions"])
    }

    @Test("A section dropped on the last one moves to last place")
    func dropOnLastMovesToEnd() {
        #expect(LessonsScopeThreadFocusView.sectionOrder(names, moving: "Introduction", onto: "Extensions")
                == ["Practice", "Extensions", "Introduction"])
    }

    @Test("A section dropped on an earlier one moves above it")
    func dropOnEarlierMovesUp() {
        #expect(LessonsScopeThreadFocusView.sectionOrder(names, moving: "Extensions", onto: "Introduction")
                == ["Extensions", "Introduction", "Practice"])
        #expect(LessonsScopeThreadFocusView.sectionOrder(names, moving: "extensions", onto: "practice")
                == ["Introduction", "Extensions", "Practice"])
    }

    @Test("A drop naming a section that isn't there changes nothing")
    func unknownSectionIsRefused() {
        #expect(LessonsScopeThreadFocusView.sectionOrder(names, moving: "Games", onto: "Practice") == nil)
    }
}
