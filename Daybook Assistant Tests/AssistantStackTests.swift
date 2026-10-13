import Foundation
import Testing
@testable import Daybook_Assistant

// A hosted test run opened the simulator's own class: a test's attendance
// screen told Siri its names, the system asked the app's entity queries for
// them, and they open `AssistantStack`. Its CloudKit setup failed without an
// iCloud account, and the filing hold that started stopped every share
// attacher that reads it, so the attacher's tests failed or hung, depending
// on when the failure arrived (2026-10-13).
@Suite("Assistant stack in a test run")
@MainActor
struct AssistantStackTests {

    @Test("A test run never opens the iPhone's own class, so Siri's lookups find nothing and no filing hold starts")
    func testRunOpensNothing() async {
        #expect(throws: AssistantStack.OpenError.hostedTestRun) { try AssistantStack.shared() }
        // What the system asks once `updateAppShortcutParameters()` has run.
        await #expect(throws: SiriAttendanceError.self) { try await StudentEntityQuery().suggestedEntities() }
        await #expect(throws: AssistantStack.OpenError.self) { try await SupplyEntityQuery().suggestedEntities() }
        #expect(!AssistantStack.isOpen)
        #expect(AssistantStack.filingStopReason == nil)
    }
}
