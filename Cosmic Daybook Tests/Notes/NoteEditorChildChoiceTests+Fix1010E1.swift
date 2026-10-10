import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #3/#13 follow-up. In the note editor a child she
// deselected came back on the next keystroke that mentioned her, and opening
// a note added the children its own text named. Quick Note's twin is
// QuickNoteSaveTests.removedChipStaysRemoved.

@Suite("Note editor child choice (Fix1010E1)")
@MainActor
struct NoteEditorChildChoiceTests {

    @Test("A child she deselected stays off while she keeps typing")
    func deselectedStaysOff() {
        let sarahK = UUID()
        let leo = UUID()
        var deselected: Set<UUID> = []
        let chosen = NoteEditorChildChoice.choose([leo], from: [sarahK, leo], deselected: &deselected)
        #expect(chosen == [leo])
        #expect(deselected == [sarahK])

        // The name finder reads "Sarah" again and adds her back...
        let kept = NoteEditorChildChoice.afterNameFinder(
            before: chosen, after: [sarahK, leo], deselected: deselected, openedTextNames: []
        )
        // ...and she comes off again.
        #expect(kept == [leo])
    }

    @Test("Typing a more specific name still chooses a child she didn't take off")
    func moreSpecificNameStillChooses() {
        let sarahK = UUID()
        let sarahM = UUID()
        var deselected: Set<UUID> = []
        // "Sarah" chose Sarah K; she took her off.
        let chosen = NoteEditorChildChoice.choose([], from: [sarahK], deselected: &deselected)
        // Then she typed "Sarah M".
        let kept = NoteEditorChildChoice.afterNameFinder(
            before: chosen, after: [sarahM], deselected: deselected, openedTextNames: []
        )
        #expect(kept == [sarahM])
    }

    @Test("Putting a child back forgets that she was taken off")
    func puttingBackForgets() {
        let leo = UUID()
        var deselected: Set<UUID> = []
        _ = NoteEditorChildChoice.choose([], from: [leo], deselected: &deselected)
        let chosen = NoteEditorChildChoice.choose([leo], from: [], deselected: &deselected)
        #expect(deselected.isEmpty)
        let kept = NoteEditorChildChoice.afterNameFinder(
            before: [], after: chosen, deselected: deselected, openedTextNames: []
        )
        #expect(kept == [leo])
    }

    @Test("Children the opened note already names aren't added by an edit; ones already chosen stay")
    func openedTextNames() {
        let maya = UUID()
        let leo = UUID()
        let ora = UUID()
        // Opened with Leo chosen; the note's text also names Maya.
        let kept = NoteEditorChildChoice.afterNameFinder(
            before: [leo], after: [leo, maya, ora], deselected: [], openedTextNames: [maya, leo]
        )
        #expect(kept == [leo, ora], "Ora is newly typed; Maya was only in the old text")
    }
}
