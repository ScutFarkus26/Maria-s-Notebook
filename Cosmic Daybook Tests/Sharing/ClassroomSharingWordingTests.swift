import CloudKit
import Foundation
import Testing
@testable import CosmicDaybook

/// What Settings › Classroom says after setting up sharing, and why a set-up pass
/// stopped: plain words, never CloudKit's codes or terms.
@Suite("Classroom sharing wording")
struct ClassroomSharingWordingTests {

    @Test("Why an attach pass stopped is a plain phrase with no codes")
    func stopReasonsArePlain() {
        let dead = NSError(domain: NSCocoaErrorDomain, code: 134_406)
        let timedOut = NSError(domain: NSCocoaErrorDomain, code: 134_060)
        #expect(ClassroomShareAttach.stopReason(for: dead) == "iCloud stopped syncing")
        #expect(ClassroomShareAttach.stopReason(for: timedOut) == "iCloud took too long to answer")
        #expect(ClassroomShareAttach.stopReason(for: NSError(domain: CKErrorDomain, code: 4)) == nil)
    }

    @Test("A setup that stopped partway says how many and what to do")
    func setupSummaryStoppedPartway() {
        let report = ClassroomShareSetupReport(
            created: true, attached: 214, failed: 3, stoppedBecause: "iCloud stopped syncing",
            needsRelaunch: true, contents: nil
        )
        #expect(report.summary == "Classroom shared. 214 items added. 3 couldn't be added because "
            + "iCloud stopped syncing. Quit and reopen the app, then try again.")
    }

    @Test("A finished setup says only what was added")
    func setupSummaryFinished() {
        let report = ClassroomShareSetupReport(
            created: false, attached: 1, failed: 0, stoppedBecause: nil, contents: nil
        )
        #expect(report.summary == "1 item added.")
    }

    @Test("A failed join says what to do next, by cause")
    func joinAdvice() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let signedOut = NSError(domain: CKErrorDomain, code: CKError.Code.notAuthenticated.rawValue)
        let gone = NSError(domain: CKErrorDomain, code: CKError.Code.zoneNotFound.rawValue)
        #expect(ClassroomSharingService.joinAdvice(for: offline).contains("online"))
        #expect(ClassroomSharingService.joinAdvice(for: signedOut).contains("Sign in"))
        #expect(ClassroomSharingService.joinAdvice(for: gone) == "Ask the lead guide for a new invitation.")
        // Wrapped, as joins often fail (bug hunt 2026-10-04): it used to say
        // to ask for a new invitation when the fix was getting online.
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
            NSUnderlyingErrorKey: CKError(.partialFailure, userInfo: [
                CKPartialErrorsByItemIDKey: ["share": CKError(.networkUnavailable)]
            ]) as NSError
        ])
        #expect(ClassroomSharingService.joinAdvice(for: wrapped)
            == "Check you're online, then open the invitation again.")
    }

    @Test("What the share holds names marks, never a model type")
    func shareContentsWording() {
        #expect(ClassroomShareSetupReport.describe(1, "AttendanceRecord") == "1 attendance mark")
        #expect(ClassroomShareSetupReport.describe(2, "SomethingNew") == "2 other items")
    }

    @Test("Every reason a removal run stops reads plainly: no CloudKit, record or store words")
    func releaseStopReasonsArePlain() {
        let errors: [ClassroomShareRelease.RunError] = [
            .stopped("Classroom share export failed (CKError 12)"), .timedOut("the private copies"),
            .copyVanished, .originalVanished, .copyLandedInShare, .originalNotMirrored, .storeUnavailable
        ]
        for error in errors {
            let message = error.errorDescription ?? ""
            #expect(!message.isEmpty)
            for jargon in ["CKError", "CloudKit", "record", "store", "build", "group"] {
                #expect(!message.localizedCaseInsensitiveContains(jargon), "\(error): \(message)")
            }
            #expect(!error.details.isEmpty)
        }
    }

    @Test("A raw iCloud error that stops a removal run is translated, its text kept for Details")
    func releaseRawErrorTranslated() {
        let raw = NSError(domain: "CKErrorDomain", code: 4, userInfo: [NSLocalizedDescriptionKey: "Network failure"])
        let stop = ClassroomShareRelease.stopMessage(for: raw)
        #expect(!stop.message.contains("CKErrorDomain"))
        #expect(!stop.message.contains("Network failure"))
        #expect(stop.details.contains("CKErrorDomain 4"))
    }

    @Test("A finished removal says how many children and marks stopped being shared")
    func removalMovedLine() {
        var report = ClassroomShareRelease.Report()
        report.studentsMoved = 1
        report.attendanceMoved = 412
        #expect(ClassroomReleaseSheet.movedLine(report)
            == "1 child and 412 attendance marks are no longer shared. They're still in your notebook.")
    }
}
