import CloudKit
import Foundation
import Testing
@testable import CosmicDaybook

// The 2026-11-02 sync, sharing and backup hunt's Remove Last Year findings in Settings:
// the sheet checks before it reads (#36), the provisional start (#39), and the card and the
// finished run's words for records held twice (#38) and deletes iCloud hasn't confirmed (#41).

@Suite("Remove Last Year sheet and card")
@MainActor
struct ClassroomReleaseSheetHunt1102Tests {

    @Test("The sheet checks what stops the run before reading the share, and shows only that")
    func blockerBeforeRead() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let model = ClassroomReleaseModel(dependencies: AppDependencies(coreDataStack: stack)) { false }
        await model.load()
        // On an iPhone the run is the Mac's: nothing is read, and the reason is all it shows.
        #expect(model.stage == .blocked("Remove last year from the share on your Mac."))
    }

    @Test("Removing last year waits for the school-year start to reach this Mac")
    func provisionalStartBlocks() {
        let start = Date()
        #expect(ClassroomShareRelease.scopeBlocker(ClassroomShareScope(cutoff: start, isProvisional: true))
            == "Your school-year start hasn't reached this Mac yet. Open Settings › School year, then try again.")
        #expect(ClassroomShareRelease.scopeBlocker(ClassroomShareScope(cutoff: start)) == nil)
    }

    @Test("Records a stopped run left twice keep the card up, saying so, until they're one again")
    func cardShowsHeldTwice() {
        typealias Card = ClassroomLastYearCard
        #expect(Card.isShown(waiting: 0, heldTwice: 2, stoppedEarlier: false, running: false))
        #expect(!Card.isShown(waiting: 0, heldTwice: 0, stoppedEarlier: false, running: false))
        #expect(Card.title(waiting: 0, heldTwice: 2, running: false) == "2 items are in your notebook twice")
        #expect(Card.title(waiting: 0, heldTwice: 1, running: false) == "1 item is in your notebook twice")
        // Records still to leave the share are counted first; the twice-held ones go with them.
        #expect(Card.title(waiting: 3, heldTwice: 1, running: false)
            == "3 items from before this school year are still shared")
    }

    @Test("The finished run says what a cleanup did and what iCloud hasn't confirmed")
    func finishedLines() {
        var report = ClassroomShareRelease.Report()
        #expect(ClassroomReleaseSheet.twinsCleanedLine(report) == nil)
        #expect(ClassroomReleaseSheet.unconfirmedLine(report) == nil)
        report.twinsCleaned = 2
        report.unconfirmed = 1
        let twins = ClassroomReleaseSheet.twinsCleanedLine(report)
        let unconfirmed = ClassroomReleaseSheet.unconfirmedLine(report)
        #expect(twins?.hasPrefix("2 items that were in your notebook twice") == true)
        #expect(unconfirmed?.hasPrefix("iCloud hasn't confirmed yet that 1 item") == true)
    }

    @Test("The new reasons a run stops read plainly, as the others do: no CloudKit, record or store words")
    func newStopReasonsArePlain() {
        let missing = CloudKitServerCheck.ZoneMissing(found: [:], inMissingZones: [])
        let messages = [ClassroomShareRelease.RunError.changedDuringRun, .sharedOriginalGone]
            .map { $0.errorDescription ?? "" }
            + [ClassroomShareRelease.stopMessage(for: missing).message]
        for message in messages {
            #expect(!message.isEmpty)
            for jargon in ["CKError", "CloudKit", "record", "store", "zone"] {
                #expect(!message.localizedCaseInsensitiveContains(jargon), "\(message)")
            }
        }
        let stop = ClassroomShareRelease.stopMessage(for: missing)
        #expect(stop.message.hasPrefix("iCloud no longer has your classroom share"))
    }
}
