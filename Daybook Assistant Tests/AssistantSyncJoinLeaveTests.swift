import Foundation
import CoreData
import CloudKit
import Testing
@testable import Daybook_Assistant

// Bug hunt 2026-10-04, Phase 4: sync that stops for good, Leave that drops
// unsent marks or hides its reason, being taken out of the class, a join
// that hangs, and account checks answered out of order.
@Suite("Assistant sync, joining and leaving")
@MainActor
struct AssistantSyncJoinLeaveTests {

    // MARK: - Mirroring stopped

    // Before: the attacher noted the stopped container and nothing else, so
    // only a relaunch sent again and the line read "Sending to iCloud…".
    @Test("A pass that finds mirroring stopped says which stack, once")
    func mirroringStopIsReported() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let share = FakeShare()
        let attacher = AssistantShareAttacher(
            defaults: AssistantTestSupport.makeDefaults(), sleep: share.sleep, attempt: share.attempt
        )
        let told = Told()
        attacher.onMirroringStopped = { told.containers.append($0) }
        let record = CDAttendanceRecord(context: stack.viewContext)
        record.id = UUID()
        #expect(stack.viewContext.safeSave())

        share.stopsMirroringNextAttempt = true
        attacher.attach([record.objectID], container: stack.container, context: stack.viewContext)
        await attacher.waitUntilIdle()
        // Nothing more runs on that stack, so nothing more is reported.
        attacher.flush(container: stack.container, context: stack.viewContext)
        await attacher.waitUntilIdle()

        #expect(told.containers.count == 1)
        #expect(told.containers.first === stack.container)
    }

    @Test("The first stop on the open stack rebuilds it; a second gives up; others are ignored")
    func mirroringStopResponse() {
        let respond = AssistantBootstrapper.mirroringStopResponse
        #expect(respond(true, true, false) == .rebuild)
        #expect(respond(true, true, true) == .giveUp)
        // A stack rebuilt since, or the app starting, failed or leaving.
        #expect(respond(false, true, false) == .ignore)
        #expect(respond(true, false, false) == .ignore)
    }

    // MARK: - Leave

    // Before: Leave purged at once, whatever hadn't reached the guide.
    @Test("Leave first counts the marks that haven't reached the guide")
    func unsentMarksBeforeLeave() {
        typealias Unsent = AssistantBootstrapper.UnsentMarks
        let unsent = AssistantBootstrapper.unsentMarks
        #expect(unsent(0, false) == nil)
        #expect(unsent(3, false) == .counted(3))
        #expect(unsent(2, true) == .counted(2))
        #expect(unsent(0, true) == .uncounted)
        #expect(Unsent.counted(1).message.hasPrefix("1 mark hasn't reached your guide yet."))
        #expect(Unsent.counted(3).message.hasPrefix("3 marks haven't reached your guide yet."))
        #expect(Unsent.uncounted.message.contains("Wait"))
    }

    // Before: every failure read "Check that this iPhone is online", even
    // "the class hasn't finished arriving" and "several classes".
    @Test("Leave's own reasons show; CloudKit's are translated, also when wrapped")
    func leaveMessages() {
        let message = AssistantClassroomSheet.leaveMessage
        for reason in [ClassroomLeaveError.shareNotReadable, .unclearShare(2), .notSaved] {
            #expect(message(reason) == reason.errorDescription)
        }
        #expect(message(CKError(.networkFailure))
            == "Couldn't leave the classroom. This device couldn't reach iCloud. Check you're online and try again.")
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134_400, userInfo: [
            NSUnderlyingErrorKey: CKError(.notAuthenticated) as NSError
        ])
        #expect(message(wrapped).contains("isn't signed in to iCloud"))
    }

    // MARK: - Taken out of the class

    // Before: an iPhone taken out of the class kept its membership row and
    // read "No students yet… a minute after you join" for good.
    @Test("A share seen here and now gone with the class means taken out; else not")
    func removedFromClass() throws {
        let removed = AssistantBootstrapper.removedFromClass
        #expect(removed(false, true, false))
        // A new iPhone before the class arrives has no share either.
        #expect(!removed(false, false, false))
        #expect(!removed(true, true, false))
        // The class is still here and its share can't be read yet.
        #expect(!removed(false, true, true))

        let defaults = AssistantTestSupport.makeDefaults()
        let zone = "com.apple.coredata.cloudkit.share.DB5879EF-1C2D-4E5F-8A9B-0C1D2E3F4A5B"
        #expect(!AssistantClassroomLocalState.sawShare(inZone: zone, defaults: defaults))
        AssistantClassroomLocalState.noteShareSeen(inZone: zone, defaults: defaults)
        #expect(AssistantClassroomLocalState.sawShare(inZone: zone, defaults: defaults))
        #expect(!AssistantClassroomLocalState.sawShare(inZone: "another-zone", defaults: defaults))
        // Leave and Rebuild from iCloud forget it with the class.
        AssistantClassroomLocalState.forget(defaults: defaults)
        #expect(!AssistantClassroomLocalState.sawShare(inZone: zone, defaults: defaults))
    }

    // MARK: - Joining

    // Before: "Joining your classroom…" stayed up for as long as CloudKit's
    // accept didn't answer, with no button on the page.
    @Test("A join gives up after its timeout; a later join isn't ended by an earlier one")
    func joinTimeout() throws {
        let stack = try AssistantTestSupport.makeStack()
        let service = ClassroomSharingService(container: stack.container, context: stack.viewContext)
        #expect(ClassroomSharingService.joinTimeout == .seconds(60))

        let first = service.beginJoin()
        #expect(service.isJoining)
        service.joinTimedOut(first)
        #expect(!service.isJoining)
        #expect(service.shareError == ClassroomSharingService.joinTimeoutMessage)

        // She opens the invitation again: the first join's late finish and
        // its timeout leave the second alone.
        let second = service.beginJoin()
        #expect(service.shareError == nil)
        service.endJoin(first)
        service.joinTimedOut(first)
        #expect(service.isJoining)
        service.endJoin(second)
        #expect(!service.isJoining)

        // A join that finished in time isn't timed out afterwards.
        let third = service.beginJoin()
        service.endJoin(third)
        service.joinTimedOut(third)
        #expect(service.shareError == nil)
    }

    // MARK: - Account checks

    // Before: whichever answer came last won, however old; a stale
    // "no account" could land after a fresh "available".
    @Test("An account answer that arrives after a newer check began is dropped")
    func staleAccountAnswer() async {
        let answers = AccountAnswers()
        let bootstrapper = AssistantBootstrapper(fetchAccountStatus: { try await answers.next() })
        let first = Task { await bootstrapper.refreshAccountStatus() }
        #expect(await waitUntil { answers.waiting == 1 })
        let second = Task { await bootstrapper.refreshAccountStatus() }
        #expect(await waitUntil { answers.waiting == 2 })

        answers.answer(1, with: .available)
        await second.value
        #expect(bootstrapper.accountStatus == .available)
        answers.answer(0, with: .noAccount)
        await first.value
        #expect(bootstrapper.accountStatus == .available)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

/// What a hook was told.
@MainActor
private final class Told {
    var containers: [NSPersistentCloudKitContainer] = []
}

/// Account checks that answer when a test says, in any order.
@MainActor
private final class AccountAnswers {
    private var continuations: [CheckedContinuation<CKAccountStatus, any Error>] = []
    private(set) var waiting = 0

    func next() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
            waiting += 1
        }
    }

    func answer(_ index: Int, with status: CKAccountStatus) {
        continuations[index].resume(returning: status)
    }
}
