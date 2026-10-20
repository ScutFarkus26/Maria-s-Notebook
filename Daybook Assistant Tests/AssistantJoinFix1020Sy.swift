import Foundation
import CoreData
import CloudKit
import Testing
@testable import Daybook_Assistant

// Bug hunt 2026-10-20, the rules behind sync and joining: the class store's
// own failed setup decides a rebuild (#9), another guide's invitation is
// refused while in a class (#11), Leave counts a save from before a relaunch
// (#12), a rebuild keeps the join screen or the sample up (#22), the sample
// doesn't reopen over a join (#21), and a download waits for a joined phone's
// membership (#13).
@Suite("Assistant joining rules 2026-10-20")
@MainActor
struct AssistantJoinFix1020Sy {

    // MARK: - #9 The class store's failed setup

    private func setup(failedFor error: NSError?, at start: Date = Date()) -> AssistantFilingHold.Event {
        AssistantFilingHold.Event(
            type: .setup, succeeded: false, killedDelegate: false, start: start, storeIdentifier: "shared",
            accountUnavailable: error.map(AssistantFilingHold.isAccountUnavailable) ?? false
        )
    }

    @Test("A setup that failed for the account is noted once, and stays noted after the store syncs")
    func accountSetupFailureIsSticky() {
        let hold = AssistantFilingHold()
        let told = Count()
        hold.onSetupFailedForAccount = { told.count += 1 }
        let failedAt = Date()
        let noAccount = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
            NSUnderlyingErrorKey: CKError(.notAuthenticated) as NSError
        ])
        hold.follow(setup(failedFor: noAccount, at: failedAt))
        hold.follow(setup(failedFor: noAccount, at: failedAt.addingTimeInterval(1)))
        #expect(hold.setupFailedForAccount)
        #expect(told.count == 1)

        // The account arrives and an import works: the hold lifts, but the
        // container still can't share.
        hold.follow(.init(
            type: .import, succeeded: true, killedDelegate: false,
            start: failedAt.addingTimeInterval(2), storeIdentifier: "shared"
        ))
        #expect(hold.stopReason == nil)
        #expect(hold.setupFailedForAccount)
    }

    @Test("A setup that failed for the network isn't the account's")
    func networkSetupFailureIsNot() {
        let hold = AssistantFilingHold()
        hold.follow(setup(failedFor: CKError(.networkUnavailable) as NSError))
        hold.follow(setup(failedFor: nil))
        #expect(hold.stopReason != nil, "it still holds filing")
        #expect(!hold.setupFailedForAccount)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_060, userInfo: [
            NSUnderlyingErrorKey: CKError(.accountTemporarilyUnavailable) as NSError
        ])
        #expect(AssistantFilingHold.isAccountUnavailable(wrapped))
        #expect(!AssistantFilingHold.isAccountUnavailable(CKError(.networkFailure) as NSError))
    }

    @Test("A failed setup rebuilds once the account is available; again soon after, it gives up")
    func failedSetupRebuild() {
        let response = AssistantBootstrapper.failedSetupResponse
        #expect(response(true, .available, false) == .rebuild)
        #expect(response(true, .available, true) == .giveUp, "the rebuilt stack failed too, soon after")
        #expect(response(true, .noAccount, false) == .ignore, "not before the account's here")
        #expect(response(true, nil, false) == .ignore)
        #expect(response(false, .available, false) == .ignore)
    }

    // MARK: - #11 Another guide's invitation

    @Test("An invitation from another guide is refused while in a class; one that can't be told isn't")
    func anotherGuidesInvitation() {
        let another = ClassroomSharingService.isAnotherGuide
        #expect(another("_rivera", "_cohen"))
        #expect(!another("_rivera", "_rivera"), "the same guide's new share")
        #expect(!another("unknown", "_cohen"), "no owner written")
        #expect(!another("", "_cohen"))
        #expect(!another("_rivera", nil))
        #expect(!another("_rivera", CKCurrentUserDefaultName))
        let message = ClassroomJoinRefusal.alreadyInAClass.message
        #expect(message == "You're already in a class. Leave it in Classroom first, then open the new invitation.")
    }

    // MARK: - #12 Leave after a relaunch

    @Test("A save with no upload begun after it counts as unsent, across a relaunch")
    func saveBeforeRelaunchIsUnsent() throws {
        let stack = try AssistantTestSupport.makeStack()
        let defaults = AssistantTestSupport.makeDefaults()
        let before = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        let start = Date()
        before.record(.init(isExport: true, start: start, end: start.addingTimeInterval(2), succeeded: true))
        before.saved(at: start.addingTimeInterval(5))
        #expect(before.hasUnsentSave)

        // The app is closed and opened again: the keep-alive starts empty,
        // the record doesn't.
        let after = AssistantSyncRecord(viewContext: stack.viewContext, defaults: defaults)
        #expect(after.hasUnsentSave)
        #expect(AssistantBootstrapper.unsentMarks(waitingForShare: 0, unsentSave: after.hasUnsentSave) == .uncounted)

        after.record(.init(isExport: true, start: start.addingTimeInterval(6), end: start.addingTimeInterval(8),
                           succeeded: true))
        #expect(!after.hasUnsentSave)
    }

    // MARK: - #22, #21, #13 The screen during a rebuild

    @Test("A rebuild shows Starting only on a phone that has joined")
    func rebuildScreen() {
        let starting = AssistantBootstrapper.rebuildShowsStarting
        #expect(starting(true, false, false), "in the class")
        #expect(!starting(false, false, false), "the join screen stays, with its page")
        #expect(!starting(true, false, true), "the Sample Class stays")
        #expect(starting(false, true, false), "a download waiting for its membership")
    }

    @Test("The Sample Class reopens on the join screen, but not over a join")
    func sampleReopens() {
        let reopens = AssistantBootstrapper.reopensSample
        #expect(reopens(true, false))
        #expect(!reopens(true, true))
        #expect(!reopens(false, false))
    }

    @Test("A phone that saw its class's share was in a class; Leave and Rebuild forget it")
    func wasInAClass() {
        let defaults = AssistantTestSupport.makeDefaults()
        #expect(!AssistantClassroomLocalState.wasInAClass(defaults: defaults))
        AssistantClassroomLocalState.noteShareSeen(inZone: "com.apple.coredata.cloudkit.share.ABC", defaults: defaults)
        #expect(AssistantClassroomLocalState.wasInAClass(defaults: defaults))
        AssistantClassroomLocalState.forget(defaults: defaults)
        #expect(!AssistantClassroomLocalState.wasInAClass(defaults: defaults))
    }

    @Test("The account is asked again only while it's unknown and the join screen may show")
    func accountRetryRule() {
        let retries = AssistantBootstrapper.retriesAccountCheck
        #expect(retries(nil, true))
        #expect(retries(.couldNotDetermine, true))
        #expect(!retries(.available, true))
        #expect(!retries(.noAccount, true), "a known problem is shown, not asked about")
        #expect(!retries(nil, false), "in a class")
    }
}

@MainActor
private final class Count {
    var count = 0
}
