import Foundation
import Testing
@testable import Maria_s_Notebook

/// The floating button no longer opens a radial menu of create actions — a tap
/// opens the command bar instead. That is only a safe trade while the command
/// bar can still reach every one of the five actions, so pin the mapping.
struct QuickCaptureIntentCoverageTests {

    @Test("The command bar recognises exactly the five quick-capture intents")
    func intentCount() {
        #expect(RecordIntent.allCases.count == 5)
        #expect(PieMenuAction.allCases.count == 5)
    }

    @Test("Every create action is reachable from a command-bar intent")
    func everyActionHasAnIntent() {
        #expect(Set(RecordIntent.allCases.map(\.pieMenuAction)) == Set(PieMenuAction.allCases))
    }

    @Test("An intent and its action show the same symbol")
    func iconsAgree() {
        for intent in RecordIntent.allCases {
            #expect(intent.icon == intent.pieMenuAction.icon, "\(intent) icon differs from its action's")
        }
    }
}
