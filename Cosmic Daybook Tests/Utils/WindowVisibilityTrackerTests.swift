import Testing
@testable import CosmicDaybook

/// What the Mac's window-occlusion probe reports to the view it sits in.
@Suite("Window visibility tracker")
@MainActor
struct WindowVisibilityTrackerTests {

    @Test("Joining a window that is on screen or in the Dock reports its occlusion state")
    func attachToOrderedInWindowReportsItsState() {
        var covered = WindowVisibilityTracker()
        #expect(covered.attached(isOrderedIn: true, isVisible: false) == false)
        #expect(covered.lastReported == false)

        var shown = WindowVisibilityTracker()
        #expect(shown.attached(isOrderedIn: true, isVisible: true) == true)
        #expect(shown.lastReported == true)
    }

    @Test("A window still being built counts as visible until AppKit says otherwise")
    func attachToWindowNotYetShownCountsAsVisible() {
        var tracker = WindowVisibilityTracker()
        #expect(tracker.attached(isOrderedIn: false, isVisible: false) == true)
        #expect(tracker.lastReported == true)
        // Shown and covered at once: AppKit's change is the first real report.
        #expect(tracker.occlusionChanged(isVisible: false) == false)
    }

    @Test("Occlusion changes are reported only when visibility flips")
    func occlusionChangesReportOnlyFlips() {
        var tracker = WindowVisibilityTracker()
        _ = tracker.attached(isOrderedIn: true, isVisible: true)
        #expect(tracker.occlusionChanged(isVisible: true) == nil)
        #expect(tracker.occlusionChanged(isVisible: false) == false)
        #expect(tracker.occlusionChanged(isVisible: false) == nil)
        #expect(tracker.occlusionChanged(isVisible: true) == true)
    }

    @Test("A change that arrives before the join is reported")
    func occlusionChangeBeforeAttachIsReported() {
        var tracker = WindowVisibilityTracker()
        #expect(tracker.occlusionChanged(isVisible: false) == false)
    }

    @Test("Leaving the window makes the state unknown again, which counts as visible")
    func detachRevertsToVisible() {
        var hidden = WindowVisibilityTracker()
        _ = hidden.attached(isOrderedIn: true, isVisible: false)
        #expect(hidden.detached() == true)
        #expect(hidden.lastReported == nil)
        #expect(hidden.detached() == nil)

        var shown = WindowVisibilityTracker()
        _ = shown.attached(isOrderedIn: true, isVisible: true)
        #expect(shown.detached() == nil)
    }

    @Test("Joining again reports even an unchanged value, so a view's leftover state is corrected")
    func reattachAlwaysReports() {
        var tracker = WindowVisibilityTracker()
        _ = tracker.attached(isOrderedIn: true, isVisible: true)
        _ = tracker.detached()
        #expect(tracker.attached(isOrderedIn: true, isVisible: true) == true)
    }
}
