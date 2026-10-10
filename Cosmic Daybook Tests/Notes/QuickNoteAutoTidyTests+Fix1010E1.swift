import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #16. Quick Note's auto-tidy swapped in the whole
// text, which put the cursor at the end of the note while she was writing
// in the middle of it. The tidy now carries the cursor with the text.

@Suite("Quick Note auto-tidy keeps the cursor (Fix1010E1)")
@MainActor
struct QuickNoteAutoTidyTests {

    private func tidy(_ pairs: [(String, String)]) -> [TextReplacement] {
        pairs.map { TextReplacement(originalText: $0.0, replacement: $0.1) }
    }

    @Test("A tidied name before the cursor shifts it by the change in length")
    func shiftsAfterEarlierChange() throws {
        // "maya read| with leo" — the cursor after "read".
        let text = "maya read with leo"
        let result = try #require(QuickNoteAutoTidy.apply(tidy([("maya", "Maya S")]), to: text, cursor: 9))
        #expect(result.text == "Maya S read with leo")
        #expect(result.cursor == 11)
    }

    @Test("A tidied name after the cursor leaves it where it is")
    func staysBeforeLaterChange() throws {
        let text = "Read with leo today"
        let result = try #require(QuickNoteAutoTidy.apply(tidy([("leo", "Leo A")]), to: text, cursor: 4))
        #expect(result.text == "Read with Leo A today")
        #expect(result.cursor == 4)
    }

    @Test("A cursor inside the tidied word ends up after the new word")
    func insideMovesToEnd() throws {
        let result = try #require(QuickNoteAutoTidy.apply(tidy([("maya", "Maya S")]), to: "maya read", cursor: 2))
        #expect(result.cursor == 6)
    }

    @Test("Nothing to change gives nothing back, and text already tidy isn't touched")
    func noChange() {
        #expect(QuickNoteAutoTidy.apply(tidy([("Maya S", "Maya S")]), to: "Maya S read", cursor: 3) == nil)
        #expect(QuickNoteAutoTidy.apply(tidy([("maya", "Maya S")]), to: "Leo read", cursor: 3) == nil)
    }

    @Test("The cursor round-trips through a text selection, emoji and all")
    func selectionRoundTrip() throws {
        let text = "Great job 👍 maya"
        let selection = QuickNoteAutoTidy.selection(at: text.utf16.count, in: text)
        let offset = try #require(QuickNoteAutoTidy.cursorOffset(of: selection, in: text))
        #expect(offset == text.utf16.count)
        let result = try #require(QuickNoteAutoTidy.apply(tidy([("maya", "Maya S")]), to: text, cursor: offset))
        #expect(result.text == "Great job 👍 Maya S")
        #expect(result.cursor == result.text.utf16.count)
    }
}
