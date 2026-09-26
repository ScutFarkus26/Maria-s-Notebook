import Testing
@testable import CosmicDaybook

/// The decision behind `onChangeWhenVisible` / `onReceiveWhenVisible`.
@Suite("When-visible gate")
@MainActor
struct WhenVisibleGateTests {

    @Test("Runs while visible; while hidden only marks stale and catches up once on appear")
    func gateDefersWhileHidden() {
        var gate = WhenVisibleGate()
        #expect(gate.appear(catchUp: true) == false)
        #expect(gate.request() == true)

        gate.disappear()
        #expect(gate.request() == false)
        #expect(gate.request() == false)
        #expect(gate.isStale == true)

        #expect(gate.appear(catchUp: true) == true)
        #expect(gate.isStale == false)
        gate.disappear()
        #expect(gate.appear(catchUp: true) == false)
    }

    @Test("A screen that reloads on its own appear skips the catch-up")
    func gateWithoutCatchUp() {
        var gate = WhenVisibleGate()
        _ = gate.appear(catchUp: false)
        gate.disappear()
        #expect(gate.request() == false)
        #expect(gate.appear(catchUp: false) == false)
        #expect(gate.isStale == false)
        #expect(gate.request() == true)
    }

    // MARK: - Hidden by the window (Mac occlusion)

    @Test("A window nobody has reported on counts as visible")
    func unknownWindowCountsAsVisible() {
        var gate = WhenVisibleGate()
        #expect(gate.isWindowVisible == true)
        _ = gate.appear(catchUp: true)
        #expect(gate.isVisible == true)
        #expect(gate.request() == true)
    }

    @Test("While the window can't be seen every trigger only marks stale; it catches up once when it comes back")
    func occludedWindowDefersAndCatchesUpOnce() {
        var gate = WhenVisibleGate()
        _ = gate.appear(catchUp: true)
        #expect(gate.request() == true)

        #expect(gate.windowVisibilityChanged(false) == false)
        #expect(gate.isVisible == false)
        // Three saves while minimized: three reloads before, none now.
        #expect(gate.request() == false)
        #expect(gate.request() == false)
        #expect(gate.request() == false)
        #expect(gate.isStale == true)

        // Restored: exactly one catch-up.
        #expect(gate.windowVisibilityChanged(true) == true)
        #expect(gate.isStale == false)
        #expect(gate.windowVisibilityChanged(true) == false)
        #expect(gate.request() == true)
    }

    @Test("A window that comes back with nothing missed runs nothing")
    func occludedWindowWithoutRequestsSkipsCatchUp() {
        var gate = WhenVisibleGate()
        _ = gate.appear(catchUp: true)
        #expect(gate.windowVisibilityChanged(false) == false)
        #expect(gate.windowVisibilityChanged(true) == false)
        #expect(gate.isStale == false)
    }

    @Test("The window catch-up runs even for a screen that reloads on its own appear")
    func occlusionCatchUpIgnoresCatchUpOnAppear() {
        // Its own `.task` / `.onAppear` doesn't run again when the window is
        // un-minimized, so the gate has to.
        var gate = WhenVisibleGate()
        _ = gate.appear(catchUp: false)
        _ = gate.windowVisibilityChanged(false)
        #expect(gate.request() == false)
        #expect(gate.windowVisibilityChanged(true) == true)
        #expect(gate.isStale == false)
    }

    @Test("Hidden both ways: the window coming back runs nothing until the screen appears again")
    func disappearedScreenWaitsForItsOwnAppear() {
        var gate = WhenVisibleGate()
        _ = gate.appear(catchUp: true)
        gate.disappear()
        _ = gate.windowVisibilityChanged(false)
        #expect(gate.request() == false)

        #expect(gate.windowVisibilityChanged(true) == false)
        #expect(gate.isStale == true)
        #expect(gate.appear(catchUp: true) == true)
        #expect(gate.isStale == false)
    }

    @Test("Appearing in a window nobody can see keeps the catch-up for when the window comes back")
    func appearInOccludedWindowDefersCatchUp() {
        var gate = WhenVisibleGate()
        _ = gate.windowVisibilityChanged(false)
        #expect(gate.request() == false)

        #expect(gate.appear(catchUp: true) == false)
        #expect(gate.isStale == true)
        #expect(gate.request() == false)

        #expect(gate.windowVisibilityChanged(true) == true)
        #expect(gate.isStale == false)
        #expect(gate.request() == true)
    }

    @Test("Appearing in a covered window without catch-up leaves the reload to the screen's own appear")
    func appearInOccludedWindowWithoutCatchUp() {
        var gate = WhenVisibleGate()
        _ = gate.windowVisibilityChanged(false)
        #expect(gate.request() == false)

        // The screen's own `.task` / `.onAppear` reloads here, covered or not.
        #expect(gate.appear(catchUp: false) == false)
        #expect(gate.isStale == false)
        #expect(gate.windowVisibilityChanged(true) == false)
    }
}
