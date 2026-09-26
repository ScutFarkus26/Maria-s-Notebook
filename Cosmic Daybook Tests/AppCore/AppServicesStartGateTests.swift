import Testing
@testable import CosmicDaybook

// MARK: - App services start once per process
//
// Every main window's `.task` asks `AppServicesLauncher` to start the app-wide
// services, and on the Mac an MCP-only launch asks from the app delegate.
// Before 2026-09-25 only the store bootstrap was guarded, so each extra window
// reconfigured sync monitoring, restarted the backup loop, re-registered for
// pushes, re-applied the Claude Desktop setting and ran another Spotlight pass.
// The rule lives in `AppServicesStartGate`: the first caller with a loaded store
// starts them, everyone after it is turned away, and a failed store latches
// nothing, so a later caller is judged afresh, as a later window's startup was.

@Suite("App services start gate")
struct AppServicesStartGateTests {

    @Test("The first caller starts the services and every later caller is turned away")
    func firstCallerStarts() {
        var gate = AppServicesStartGate()
        #expect(gate.claim(storeLoaded: true) == .start)
        #expect(gate.claim(storeLoaded: true) == .alreadyStarted)
        #expect(gate.claim(storeLoaded: true) == .alreadyStarted)
        #expect(gate.hasStarted)
    }

    @Test("Five main windows start the services once")
    func manyWindowsStartOnce() {
        var gate = AppServicesStartGate()
        let decisions = (0..<5).map { _ in gate.claim(storeLoaded: true) }
        #expect(decisions.filter { $0 == .start }.count == 1)
        #expect(decisions.first == .start)
    }

    @Test("A store that failed to load starts nothing and latches nothing")
    func failedStoreDoesNotLatch() {
        var gate = AppServicesStartGate()
        #expect(gate.claim(storeLoaded: false) == .storeUnavailable)
        #expect(gate.claim(storeLoaded: false) == .storeUnavailable)
        #expect(!gate.hasStarted)
        // Once the store is there, the next caller still gets to start them.
        #expect(gate.claim(storeLoaded: true) == .start)
    }

    @Test("Services that started stay started, whatever a later caller sees")
    func startedStaysStarted() {
        var gate = AppServicesStartGate()
        #expect(gate.claim(storeLoaded: true) == .start)
        #expect(gate.claim(storeLoaded: false) == .alreadyStarted)
    }
}
