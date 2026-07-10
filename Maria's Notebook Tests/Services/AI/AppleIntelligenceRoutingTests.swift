import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("Apple Intelligence Routing")
struct AppleIntelligenceRoutingTests {
    @Test("Every app AI area defaults to Apple Intelligence")
    func allFeatureDefaultsUseAppleIntelligence() {
        for feature in AIFeatureArea.allCases {
            #expect(feature.defaultModel == .localFirstAuto)
        }
    }

    @Test("Automatic mode does not advertise a hidden third-party fallback")
    func automaticModeStaysInAppleBoundary() {
        let automatic = AIModelOption.localFirstAuto

        #expect(automatic.displayName == "Apple Intelligence (Auto)")
        #expect(automatic.isPrivate)
        #expect(!automatic.requiresAPIKey)
        #expect(!automatic.subtitle.localizedCaseInsensitiveContains("Claude"))
    }

    @Test("Desktop placement actions use clear reversible labels")
    func companionPlacementLabels() {
        #expect(NotebookCompanionPanel.PlacementAction.moveToDesktop.title == "Move to Desktop")
        #expect(NotebookCompanionPanel.PlacementAction.returnToApp.title == "Return to App")
    }
}
