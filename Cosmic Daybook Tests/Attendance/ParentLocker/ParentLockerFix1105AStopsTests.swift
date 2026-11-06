import Foundation
import Testing
@testable import CosmicDaybook

/// What stops the engine's send, as the 2026-11-05 bug hunt found it (report
/// "ParentLocker in the Assistant bug hunt 2026-11-05", #5, #6, #13, #14):
/// one class that won't load, a sign-out found by the send, Undo's last
/// second, and whether anything of Close Arrival's send has gone. Over the
/// fake site, clock and keychain.
@Suite("ParentLocker fixes 2026-11-05: what stops a send")
@MainActor
struct ParentLockerFix1105AStopsTests {

    typealias Device = ParentLockerTestDevice
    typealias Marks = Fix1105AMarks

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    // MARK: - #5 One class that won't load

    @Test("One class that won't load doesn't stop the other; the day waits until both are in (#5)")
    func oneClassFailsTheOtherSaves() async {
        let device = Fix1105ADevice(site: site, clock: clock, marks: Marks.closed)
        device.wire.rosterFailures[5101] = [.unreachable]
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(saves == ["save 5102"])
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.sync.status.state == .retrying)

        clock.advance(by: ParentLockerSync.retryWaits[0])
        await device.sync.runDue()
        #expect(saves == ["save 5102", "save 5101"], "the class that went is up to date")
        #expect(device.store.recordedSends.count == 1)
        #expect(device.sync.status.state == .upToDate)
    }

    @Test("A class ParentLocker refuses to list doesn't stop the other, and the class stays owed (#5)")
    func oneClassRefusedTheOtherSaves() async {
        let device = Fix1105ADevice(site: site, clock: clock, marks: Marks.closed)
        device.wire.rosterFailures[5101] = [.refused(message: "error")]
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(saves == ["save 5102"])
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.unsent.load()?.wholeClass == true)
    }

    @Test("A class whose list says signed out still signs in again, and a changed page still stops the send (#5)")
    func signedOutAndChangedPageStillStop() async {
        let device = Fix1105ADevice(site: site, clock: clock, marks: Marks.closed)
        device.wire.rosterFailures[5102] = [.signedOut]
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(site.signIns == 1)
        #expect(saves == ["save 5101", "save 5102"])
        #expect(device.store.recordedSends.count == 1)

        let other = FakeParentLocker()
        let changed = Fix1105ADevice(site: other, clock: clock, marks: Marks.closed)
        changed.wire.rosterFailures[5102] = [.pageChanged]
        changed.sync.closeArrivalSend(on: clock.now, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await changed.sync.runDue()
        #expect(other.saves.isEmpty)
        #expect(changed.sync.status.state == .pageChanged)
    }

    @Test("Match Names reads the classes that load and names the one it couldn't (#5)")
    func matchNamesNamesTheUnreadClass() async throws {
        let device = Fix1105ADevice(site: site, clock: clock)
        device.wire.rosterFailures[5101] = [.unreachable]
        let read = try await device.sync.loadRosters(day: Device.morning)
        #expect(read.rosters.map(\.course.courseID) == [5102])
        #expect(read.unread.map(\.name) == ["Girls Middle School"])
        #expect(ParentLockerMatchView.unreadLine(read.unread) == """
            Couldn't read Girls Middle School from ParentLocker, so its children may show as not matched. \
            Close Match Names and open it again to try again.
            """)

        device.wire.rosterFailures = [5101: [.unreachable], 5102: [.unreachable]]
        await #expect(throws: ParentLockerError.unreachable) { try await device.sync.loadRosters(day: Device.morning) }
    }

    // MARK: - #6 Signed out

    @Test("Close Arrival & Send that finds her signed out waits for a sign-in, then goes (#6)")
    func signedOutKeepsCloseArrival() async throws {
        let secrets = FakeParentLockerSecrets()
        let phone = Device(site: site, clock: clock, role: .assistant, secrets: secrets, marks: Marks.closed)
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        // Sign Out on her other phone: the password goes from both.
        try secrets.deletePassword(site: FakeParentLocker.host)
        clock.advance(by: Marks.sendsAfter)
        await phone.sync.runDue()
        #expect(phone.sync.status.state == .signedOut)
        #expect(phone.sync.awaitsSignIn)
        #expect(phone.unsent.load()?.wholeClass == true)

        try await phone.sync.signIn(email: "aide@school.test", password: site.password)
        await phone.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(phone.store.recordedSends.count == 1)
    }

    @Test("Undo still stops a Close Arrival & Send that found her signed out (#6)")
    func undoAfterSignedOut() async throws {
        let secrets = FakeParentLockerSecrets()
        let phone = Device(site: site, clock: clock, role: .assistant, secrets: secrets, marks: Marks.closed)
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        try secrets.deletePassword(site: FakeParentLocker.host)
        clock.advance(by: Marks.sendsAfter)
        await phone.sync.runDue()

        phone.sync.cancelCloseArrivalSend()
        phone.store.state.arrivalClosed = false
        phone.store.state.marks[Device.bea] = nil
        #expect(!phone.sync.awaitsSignIn)
        try await phone.sync.signIn(email: "aide@school.test", password: site.password)
        await phone.sync.runDue()
        #expect(saves.isEmpty)
    }

    @Test("Other changes owed still clear on Sign Out (#6)")
    func signOutClearsOtherChanges() async throws {
        let device = Device(site: site, clock: clock, sent: true, marks: Marks.everyonePresent)
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        site.failuresLeft = 1
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(device.unsent.load()?.children == [Device.wren])
        try device.sync.signOut()
        #expect(device.unsent.load() == nil)
    }

    // MARK: - #13 Undo and the send due together

    @Test("Close Arrival & Send goes a second after its Undo ends, so an Undo at that moment stops it (#13)")
    func sendGoesASecondAfterUndo() async {
        let device = Device(site: site, clock: clock, marks: Marks.closed)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        #expect(device.sync.undoEndsAt == Device.morning.addingTimeInterval(6))
        #expect(device.sync.nextWake == Device.morning.addingTimeInterval(7))
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(saves.isEmpty, "Undo is still offered")
        device.sync.cancelCloseArrivalSend()
        device.store.state.arrivalClosed = false
        device.store.state.marks[Device.bea] = nil
        clock.advance(by: 1)
        await device.sync.runDue()
        #expect(saves.isEmpty)

        // Siri's has no Undo to wait out.
        let siri = Device(site: FakeParentLocker(), clock: clock, marks: Marks.closed)
        siri.sync.closeArrivalSend(on: clock.now, after: 0)
        #expect(siri.sync.nextWake == clock.now)
    }

    @Test("Signing in inside Undo's window sends a second after it ends (#13)")
    func signInInsideTheWindow() async throws {
        let secrets = FakeParentLockerSecrets(password: nil, cookie: nil)
        let phone = Device(site: site, clock: clock, role: .assistant, secrets: secrets, marks: Marks.closed)
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 2)
        try await phone.sync.signIn(email: "aide@school.test", password: site.password)
        #expect(phone.sync.nextWake == Device.morning.addingTimeInterval(7))
    }

    // MARK: - #14 Whether anything of Close Arrival's send has gone

    @Test("The sync says while Close Arrival's send hasn't reached ParentLocker, until a class of it has (#14)")
    func closeArrivalUnsent() async {
        let device = Fix1105ADevice(site: site, clock: clock, marks: Marks.closed)
        #expect(!device.sync.closeArrivalSendUnsent)
        site.failuresLeft = 1
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        #expect(device.sync.closeArrivalSendUnsent, "waiting out its Undo")
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(device.sync.status.state == .retrying)
        #expect(device.sync.closeArrivalSendUnsent, "waiting to retry, with nothing gone")

        // The retry saves one class and can't load the other: it has gone, in part.
        device.wire.rosterFailures[5102] = [.unreachable]
        clock.advance(by: ParentLockerSync.retryWaits[0])
        await device.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(!device.sync.closeArrivalSendUnsent)
    }

    @Test("A send whose reply was lost counts as gone; Undo and a send that goes clear it too (#14)")
    func closeArrivalUnsentEnds() async {
        let device = Fix1105ADevice(site: site, clock: clock, marks: Marks.closed)
        device.wire.lostReplies = [5101]
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(device.sync.status.state == .retrying)
        #expect(!device.sync.closeArrivalSendUnsent, "ParentLocker may have it")

        let undone = Device(site: FakeParentLocker(), clock: clock, marks: Marks.closed)
        undone.sync.closeArrivalSend(on: clock.now, after: 6)
        #expect(undone.sync.closeArrivalSendUnsent)
        undone.sync.cancelCloseArrivalSend()
        #expect(!undone.sync.closeArrivalSendUnsent)

        let other = FakeParentLocker()
        let sent = Device(site: other, clock: clock, marks: Marks.closed)
        sent.sync.closeArrivalSend(on: clock.now, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await sent.sync.runDue()
        #expect(other.saves.count == 2)
        #expect(!sent.sync.closeArrivalSendUnsent)
    }

    @Test("A Close Arrival & Send waiting for a sign-in hasn't gone (#14)")
    func closeArrivalUnsentWaitingForSignIn() async {
        let phone = Device(
            site: site, clock: clock, role: .assistant,
            secrets: FakeParentLockerSecrets(password: nil, cookie: nil), marks: Marks.closed
        )
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        // Past the moment it would have gone (review of the 2026-11-05 fixes, E12).
        await phone.sync.runDue()
        #expect(site.requests.isEmpty)
        #expect(phone.sync.awaitsSignIn)
        #expect(phone.sync.closeArrivalSendUnsent)
    }
}
