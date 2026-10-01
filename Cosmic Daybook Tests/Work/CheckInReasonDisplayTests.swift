import Foundation
import Testing
@testable import CosmicDaybook

/// A check-in's purpose is stored in two spellings: the drop prompt, the work
/// detail's planner, the agenda's bulk check and Today's follow-up write the
/// raw case name ("progressCheck"), the Quick New Work sheet the title
/// ("Progress Check"). Every screen shows it through one helper, so a pill
/// never reads "progressCheck" again, and anything else the guide or a tool
/// typed comes through as written.
@Suite("Check-in purpose display")
@MainActor
struct CheckInReasonDisplayTests {

    @Test("Every raw case name reads as its title")
    func rawNamesReadAsTitles() {
        for reason in CheckInReason.allCases {
            #expect(CheckInReason.displayName(forStoredPurpose: reason.rawValue) == reason.purpose)
        }
        #expect(CheckInReason.displayName(forStoredPurpose: "progressCheck") == "Progress Check")
    }

    @Test("A stored title, in any case or with stray spaces, reads as the title")
    func titlesStayTitles() {
        #expect(CheckInReason.displayName(forStoredPurpose: "Progress Check") == "Progress Check")
        #expect(CheckInReason.displayName(forStoredPurpose: "  due date ") == "Due Date")
        #expect(CheckInReason.displayName(forStoredPurpose: "PROGRESSCHECK") == "Progress Check")
    }

    @Test("Anything else is shown as written, trimmed")
    func freeTextIsUnchanged() {
        #expect(CheckInReason.displayName(forStoredPurpose: "Review Golden Beads") == "Review Golden Beads")
        #expect(
            CheckInReason.displayName(forStoredPurpose: " see the long multiplication laid out ")
                == "see the long multiplication laid out"
        )
        #expect(CheckInReason.displayName(forStoredPurpose: "").isEmpty)
        #expect(CheckInReason.displayName(forStoredPurpose: "   ").isEmpty)
    }

    @Test("Both spellings draw the same icon")
    func iconIgnoresSpelling() {
        for reason in CheckInReason.allCases {
            #expect(
                CheckInReason.iconName(forStoredPurpose: reason.rawValue)
                    == CheckInReason.iconName(forStoredPurpose: reason.purpose),
                "\(reason.rawValue) and \(reason.purpose) draw different icons"
            )
        }
    }
}
