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
}
