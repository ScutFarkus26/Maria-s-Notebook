import Foundation
import Testing
@testable import CosmicDaybook

/// The engine's sending, as the 2026-10-13 bug check found it (report
/// "ParentLocker bug check 2026-10-13", B1–B7): Close Arrival & Send kept
/// when its absences change, a refused password not tried again, the
/// guide's backstops, the first change synced in after a launch, Undo's
/// window, and stopping. Over the fake site, clock and keychain.
@Suite("ParentLocker sending fixes")
@MainActor
struct ParentLockerSendingFixesTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    private static let automatic = Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)

    /// The class as Close Arrival finds it: everyone in but Bea, who it marks absent.
    private static let closed: [UUID: ParentLockerPlanner.DayMark] = [
        Device.wren: Device.mark(.present), Device.june: Device.mark(.present),
        Device.marisol: Device.mark(.tardy), Device.odile: Device.mark(.present),
        Device.bea: automatic
    ]

    /// Everyone marked here as ParentLocker already holds them: Present.
    private func settled(_ devices: Device...) {
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        for device in devices {
            for child in Device.children { device.store.state.marks[child.id] = Device.mark(.present) }
        }
    }

    /// One change made on `device`, sent after its 4 s.
    private func change(_ device: Device, _ marks: [UUID: ParentLockerPlanner.DayMark]) async {
        device.marks(marks)
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
    }

    // MARK: - B1 Close Arrival & Send isn't cancelled when its absences change

    @Test("A child marked Late inside Close Arrival's Undo window doesn't cancel the send")
    func lateInsideUndoWindowStillSends() async {
        let device = Device(site: site, clock: clock, marks: Self.closed)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        // Bea walks in: Late, and the day has no automatic absence left.
        clock.advance(by: 3)
        device.store.state.arrivalClosed = false
        device.marks([Device.bea: Device.mark(.tardy)])
        clock.advance(by: 3)
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.mark(41004) == "702")
        #expect(device.store.recordedSends.count == 1)
        #expect(device.sync.status.state == .upToDate)

        // And the changes after it go live.
        await change(device, [Device.wren: Device.mark(.absent, reason: "sick")])
        #expect(site.saves.last?.entries.map(\.studentID) == ["40001"])
    }

    @Test("A child marked Late while Close Arrival's send waits to retry doesn't cancel it")
    func lateDuringRetryStillSends() async {
        let device = Device(site: site, clock: clock, marks: Self.closed)
        site.failuresLeft = 1
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(device.sync.status.state == .retrying)

        device.store.state.arrivalClosed = false
        device.marks([Device.bea: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.retryWaits[0])
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.mark(41004) == "702")
        #expect(device.store.recordedSends.count == 1)
    }

    @Test("Arrival closed here outlasts a relaunch, and what older builds saved still reads")
    func arrivalClosedIsKept() async throws {
        let unsent = ParentLockerMemoryUnsentStore()
        let before = Device(site: site, clock: clock, unsent: unsent, marks: Self.closed)
        before.sync.closeArrivalSend(on: Device.morning, after: 6)
        #expect(unsent.load()?.arrivalClosed == true)
        before.sync.stop()

        // Relaunched before it went, with Bea marked Late since.
        var marks = Self.closed
        marks[Device.bea] = Device.mark(.tardy)
        let after = Device(site: site, clock: clock, unsent: unsent, arrivalClosed: false, marks: marks)
        await after.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.mark(41004) == "702")

        // A 55117e19 build saved no `arrivalClosed`.
        let old = Data(#"{"day":"2026-10-12","children":[],"wholeClass":true}"#.utf8)
        let decoded = try JSONDecoder().decode(ParentLockerUnsent.self, from: old)
        #expect(decoded == ParentLockerUnsent(day: "2026-10-12", children: [], wholeClass: true))
        #expect(!decoded.arrivalClosed)
        #expect(!ParentLockerUnsent(day: "2026-10-12", children: [], wholeClass: false, arrivalClosed: true).isEmpty)
    }

    // MARK: - B2 A refused password

    @Test("A saved password ParentLocker refused isn't tried again by itself until a new one is saved")
    func refusedPasswordNotRetried() async throws {
        let secrets = FakeParentLockerSecrets(cookie: "expired")
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        settled(device)
        site.password = "changed-on-the-site"
        await change(device, [Device.wren: Device.mark(.tardy)])
        #expect(site.signIns == 1)
        #expect(device.sync.status.state == .passwordRefused)

        // The next change, a return to the app, Send Now: none signs in again.
        await change(device, [Device.june: Device.mark(.tardy)])
        device.sync.appReturned()
        await device.sync.runDue()
        await device.sync.sendNow(day: Device.morning)
        #expect(site.signIns == 1)
        #expect(saves.isEmpty)
        #expect(device.sync.savedPasswordRefused)
        #expect(device.sync.status.state == .passwordRefused)
        #expect(device.sync.status.message == "ParentLocker didn't take your saved password. Sign in again.")

        // A new password, saved on another of the guide's devices, is tried.
        let fresh = ParentLockerKeychain.Credential(email: "guide@school.test", password: site.password)
        try secrets.savePassword(fresh, site: FakeParentLocker.host)
        await change(device, [Device.odile: Device.mark(.tardy)])
        #expect(site.signIns == 2)
        #expect(Set(site.saves.flatMap(\.entries).map(\.studentID)) == ["40001", "40002", "41002"])
        #expect(!device.sync.savedPasswordRefused)
        #expect(device.sync.status.state == .upToDate)
    }

    // MARK: - B3 A refused backstop

    @Test("A backstop refused because arrival reopened doesn't stop the next one that day")
    func refusedBackstopDoesNotBlock() async {
        let guide = Device(site: site, clock: clock, arrivalClosed: false)
        // A phone that isn't signed in closes arrival; its absence syncs in.
        guide.store.state.arrivalClosed = true
        guide.imports([Device.wren: Self.automatic, Device.june: Device.mark(.present)])
        await guide.sync.baselineTask?.value
        // It undoes within the minute.
        clock.advance(by: 20)
        guide.store.state.arrivalClosed = false
        guide.imports([Device.wren: Device.mark(.unmarked)])
        clock.advance(by: 40)
        await guide.sync.runDue()
        #expect(saves.isEmpty)

        // A minute later it closes arrival again.
        clock.advance(by: 60)
        guide.store.state.arrivalClosed = true
        guide.imports([Device.wren: Self.automatic])
        clock.advance(by: ParentLockerSync.backstopWait)
        await guide.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(site.mark(40001) == "703")
        #expect(guide.store.recordedSends.count == 1)
    }

    // MARK: - B4 The first change synced in after a launch

    @Test("The first change synced in after a launch goes, measured against ParentLocker as it arrived")
    func firstImportAfterLaunchSends() async {
        // The morning's send has everyone in as Present; this Mac has just launched.
        let mac = Device(site: site, clock: clock, sent: true)
        settled(mac)
        #expect(mac.sync.lastSeen.isEmpty)
        // A phone that's offline marked Odile absent.
        mac.imports([Device.odile: Device.mark(.absent, reason: "sick")])
        await mac.sync.baselineTask?.value
        #expect(saves.isEmpty, "the class lists are only read")
        #expect(mac.sync.lastSeen[Device.odile]?.holdsMark == true)

        clock.advance(by: ParentLockerSync.importedWait)
        await mac.sync.runDue()
        #expect(site.saves.last?.entries.map(\.studentID) == ["41002"])
        #expect(site.mark(41002) == "703")
        #expect(site.kids[3].comment == "Sick")
    }

    // MARK: - B5 Signing in inside Undo's window

    @Test("Signing in before Close Arrival's Undo has passed sends no earlier than its end")
    func signInWaitsForUndo() async throws {
        let secrets = FakeParentLockerSecrets(password: nil, cookie: nil)
        let phone = Device(site: site, clock: clock, role: .assistant, secrets: secrets, marks: Self.closed)
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 2)
        try await phone.sync.signIn(email: "aide@school.test", password: site.password)
        await phone.sync.runDue()
        #expect(saves.isEmpty, "Undo can still stop it")
        #expect(phone.sync.nextWake == Device.morning.addingTimeInterval(6))

        clock.advance(by: 4)
        await phone.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(phone.store.recordedSends.count == 1)
    }

    @Test("The sync says when Close Arrival's Undo ends, and forgets it on Undo")
    func undoEndsAt() {
        let device = Device(site: site, clock: clock)
        #expect(device.sync.undoEndsAt == nil)
        device.sync.closeArrivalSend(on: Device.morning, after: 7)
        #expect(device.sync.undoEndsAt == Device.morning.addingTimeInterval(7))
        device.sync.cancelCloseArrivalSend()
        #expect(device.sync.undoEndsAt == nil)
    }

    // MARK: - B6 The guide's backstop and newer marks

    @Test("The guide's backstop never overwrites a mark another device saved since, nor records the day again")
    func backstopLeavesNewerMarks() async {
        let phone = Device(site: site, clock: clock, role: .assistant, marks: Self.closed)
        let mac = Device(site: site, clock: clock, marks: Self.closed)
        // The phone closes arrival; the Mac sees only Bea's automatic absence.
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        mac.imports([Device.bea: Self.automatic])
        await mac.sync.baselineTask?.value
        clock.advance(by: 6)
        await phone.sync.runDue()
        #expect(phone.store.recordedSends.count == 1)

        // Bea walks in; the phone sends her Late. Neither has reached the Mac.
        await change(phone, [Device.bea: Device.mark(.tardy)])
        #expect(site.mark(41004) == "702")
        let sent = site.saves.count

        clock.advance(by: ParentLockerSync.backstopWait)
        await mac.sync.runDue()
        #expect(site.saves.count == sent)
        #expect(site.mark(41004) == "702")
        #expect(mac.store.recordedSends.isEmpty, "the phone's record is on its way")
    }

    // MARK: - B7 Stopping

    @Test("Stopping the sync lets the background window go, and schedules nothing after")
    func stopEndsBackgroundWork() async {
        let device = Device(site: site, clock: clock, sent: true)
        settled(device)
        device.marks([Device.wren: Device.mark(.tardy)])
        #expect(device.background.isHeld)
        device.sync.stop()
        #expect(!device.background.isHeld)
        #expect(device.sync.wakeTask == nil)

        // A screen still holding it asks for more: nothing is scheduled or held.
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        device.marks([Device.june: Device.mark(.tardy)])
        #expect(device.sync.wakeTask == nil)
        #expect(!device.background.isHeld)
    }
}
