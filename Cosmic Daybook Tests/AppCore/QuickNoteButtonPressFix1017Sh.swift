// Bug hunt 2026-10-17 #34 and #38: a tap on the floating + that drifted 2
// points moved the button instead of opening quick capture, and a press the
// system cancelled could still open the radial menu with no finger down.

import CoreGraphics
import Testing
@testable import CosmicDaybook

@Suite("Floating button press (Fix1017Sh)")
@MainActor
struct QuickNoteButtonPressFix1017ShTests {
    @Test("A press that drifts less than the long-press slop is a tap")
    func driftWithinSlopIsTap() {
        #expect(QuickNoteButtonPress.isTap(.zero, hasMoved: false))
        #expect(QuickNoteButtonPress.isTap(CGSize(width: 3, height: 4), hasMoved: false))
        #expect(QuickNoteButtonPress.isTap(CGSize(width: 0, height: -9.5), hasMoved: false))
        #expect(!QuickNoteButtonPress.isTap(CGSize(width: 6, height: 8), hasMoved: false))
    }

    @Test("A press that dragged the button and came back is not a tap")
    func draggedAndBackIsNotTap() {
        #expect(!QuickNoteButtonPress.isTap(CGSize(width: 1, height: 0), hasMoved: true))
    }

    @Test("The radial menu opens only for a finger still down and still")
    func menuNeedsAFingerDown() {
        #expect(QuickNoteButtonPress.opensMenu(translation: .zero, hasMoved: false))
        #expect(QuickNoteButtonPress.opensMenu(translation: CGSize(width: 5, height: 0), hasMoved: false))
        // A press the system cancelled: no finger is down.
        #expect(!QuickNoteButtonPress.opensMenu(translation: nil, hasMoved: false))
        // Dragged out past the slop and back: still a move.
        #expect(!QuickNoteButtonPress.opensMenu(translation: .zero, hasMoved: true))
        #expect(!QuickNoteButtonPress.opensMenu(translation: CGSize(width: 10, height: 0), hasMoved: false))
    }
}
