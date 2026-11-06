import Foundation
import Testing
@testable import CosmicDaybook

/// What a whole-class send leaves owed, and what takes it, as the review of
/// the 2026-11-05 engine fixes found them (report "ParentLocker in the
/// Assistant bug hunt 2026-11-05", Review of the fixes, E3–E6, E8–E11): a
/// class owed once the retries give up, a Send Now's rule, what's kept
/// across a launch, and the line and wakes around them. Over the fake site,
/// clock and keychain.
@Suite("ParentLocker fixes 2026-11-05 C: what's owed")
@MainActor
struct ParentLockerFix1105COwedTests {

    typealias Device = ParentLockerTestDevice
    typealias Marks = Fix1105AMarks

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    /// Everyone present but Bea, who isn't marked yet.
    private static var allButBea: [UUID: ParentLockerPlanner.DayMark] {
        var marks = Marks.everyonePresent
        marks[Device.bea] = nil
        return marks
    }

    /// 9:01, a minute after the default due time.
    private var dueCheck: Date {
        let calendar = AppCalendar.shared
        let minutes = AttendanceEmailLog.defaultDeadlineMinutes
        let due = calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: Device.morning))
        return (due ?? Device.morning).addingTimeInterval(ParentLockerSync.backstopWait)
    }

    /// Close Arrival & Send whose four tries all fail: the class is owed.
    private func givesUp(_ device: Fix1105CDevice) async {
        site.failuresLeft = 1 + ParentLockerSync.retryWaits.count
        device.sync.closeArrivalSend(on: clock.now, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        for wait in ParentLockerSync.retryWaits {
            clock.advance(by: wait)
            await device.sync.runDue()
        }
    }

    // MARK: - E3 A class owed once the retries give up

    @Test("Once the retries give up, a change synced in takes the class owed with it (E3)")
    func importReleasesTheClass() async {
        let mac = Fix1105CDevice(site: site, clock: clock)
        await givesUp(mac)
        #expect(mac.sync.status.state == .gaveUp)
        #expect(saves.isEmpty)

        mac.imports([Device.wren: Device.mark(.tardy)])
        await mac.sync.baselineTask?.value
        clock.advance(by: ParentLockerSync.importedWait)
        await mac.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"], "the whole class, not Wren alone")
        #expect(site.mark(41004) == "703", "Bea's absence went")
        #expect(site.mark(40001) == "702")
        #expect(mac.store.recordedSends.count == 1)
        #expect(mac.unsent.load()?.wholeClass != true)
    }

    @Test("A change of its own that goes by itself while the class is owed doesn't make the line say up to date (E3)")
    func lineWhileOwed() async {
        let mac = Fix1105CDevice(site: site, clock: clock)
        site.failuresLeft = 1 + ParentLockerSync.retryWaits.count
        mac.sync.closeArrivalSend(on: clock.now, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await mac.sync.runDue()
        clock.advance(by: ParentLockerSync.retryWaits[0])
        await mac.sync.runDue()
        clock.advance(by: ParentLockerSync.retryWaits[1])
        await mac.sync.runDue()
        // Odile is marked during the last wait: the class's retry holds her change.
        clock.advance(by: 60)
        mac.marks([Device.odile: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.retryWaits[2] - 60)
        await mac.sync.runDue()
        #expect(site.mark(41002) == "702", "her change went by itself once the class gave up")
        #expect(site.mark(41004) == nil, "the class's send is still owed")
        #expect(mac.sync.status.state == .gaveUp)
        #expect(mac.sync.status.message?.contains("Up to date") != true)
    }

    @Test("On the guide's device, the class owed goes a minute after the due time when nothing else takes it (E3)")
    func dueTimeTakesTheClass() async {
        let mac = Fix1105CDevice(site: site, clock: clock)
        await givesUp(mac)
        #expect(mac.sync.nextWake == dueCheck)
        clock.advance(by: dueCheck.timeIntervalSince(clock.now) - 1)
        await mac.sync.runDue()
        #expect(saves.isEmpty)

        clock.advance(by: 1)
        await mac.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(mac.store.recordedSends.count == 1)
        #expect(mac.sync.nextWake == nil, "once a day")
    }

    // MARK: - E4 A Send Now keeps its rule

    @Test("A Send Now with Bea unmarked, owed once its tries give up, still doesn't record the day when it goes (E4)")
    func sendNowOwedKeepsItsRule() async {
        let device = Fix1105CDevice(site: site, clock: clock, arrivalClosed: false, marks: Self.allButBea)
        site.failuresLeft = 1 + ParentLockerSync.retryWaits.count
        await device.sync.sendNow(day: Device.morning)
        for wait in ParentLockerSync.retryWaits {
            clock.advance(by: wait)
            await device.sync.runDue()
        }
        #expect(device.sync.status.state == .gaveUp)
        #expect(device.unsent.load()?.reason == "sendNow")

        device.marks([Device.june: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.mark(40002) == "702")
        #expect(device.store.recordedSends.isEmpty, "Bea still isn't marked")
    }

    @Test("A Send Now's retry held back on the way back to the app keeps its rule too (E4)")
    func sendNowHeldForCatchUp() async {
        let device = Fix1105CDevice(site: site, clock: clock, arrivalClosed: false, marks: Self.allButBea)
        site.failuresLeft = 1
        await device.sync.sendNow(day: Device.morning)
        #expect(device.sync.status.state == .retrying)

        device.sync.appReturned()
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(device.store.recordedSends.isEmpty, "Bea still isn't marked")
    }

    // MARK: - E5 What this device's saves sent, across a launch

    @Test("A save whose reply was lost, then the app ended: the relaunch knows both classes for its own (E5)")
    func sentRowsKeptAcrossLaunches() async {
        let unsent = ParentLockerMemoryUnsentStore()
        let phone = Fix1105CDevice(site: site, clock: clock, unsent: unsent)
        phone.wire.lostReplies = [5102]
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await phone.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(phone.sync.status.state == .retrying)
        phone.sync.stop()

        // iOS ended the app; it comes back with what was owed.
        let again = Fix1105CDevice(site: site, clock: clock, unsent: unsent)
        await again.sync.runDue()
        #expect(saves.count == 2, "both classes had landed")
        #expect(again.store.recordedSends.count == 1)
        #expect(again.sync.status.state == .upToDate)
        #expect(again.sync.status.problems.isEmpty)
    }

    @Test("What's owed from an earlier build still reads, and the rows and notes kept now come back (E5)")
    func unsentReadsOldAndNew() throws {
        let old = #"{"day":"2026-10-12","children":[],"wholeClass":true,"arrivalClosed":true,"reason":"closeArrival"}"#
        let read = try JSONDecoder().decode(ParentLockerUnsent.self, from: Data(old.utf8))
        #expect(read.wholeClass)
        #expect(read.reason == "closeArrival")
        #expect(read.sent.isEmpty)
        #expect(read.notes.isEmpty)

        let entry = ParentLockerPlanner.Entry(
            childID: Device.bea, studentID: "41004", type: .absent, comment: "Sick",
            attendance: .object(["attendance_code": .object(["id": .string("703")]), "comment": .string("Sick")])
        )
        var kept = ParentLockerUnsent(day: "2026-10-12", children: [], wholeClass: false)
        kept.sent = [Device.bea: [5102: ParentLockerSentRow(entry)]]
        kept.notes = [Device.bea: [5102: ["Sick"]]]
        #expect(!kept.isEmpty)
        let again = try JSONDecoder().decode(ParentLockerUnsent.self, from: JSONEncoder().encode(kept))
        #expect(again == kept)
    }

    // MARK: - E6 A whole-class run under way

    @Test("A Send Now later in the day is kept owed while it runs, though arrival closed here long before (E6)")
    func sendNowRunKept() async {
        let device = Fix1105CDevice(site: site, clock: clock)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(device.store.recordedSends.count == 1)
        #expect(device.unsent.load()?.wholeClass != true)

        let during = Fix1105ABox<ParentLockerUnsent?>(nil)
        device.wire.atRoster = { during.value = device.unsent.load() }
        clock.advance(by: 3_600)
        await device.sync.sendNow(day: Device.morning)
        #expect(during.value?.wholeClass == true)
        #expect(during.value?.reason == "sendNow")
        #expect(device.unsent.load()?.wholeClass != true, "settled once it went")
    }

    // MARK: - E8 A backstop and Close Arrival's retry

    @Test("A backstop scheduled while Close Arrival's retry waits is kept as the Close Arrival, which Undo stops (E8)")
    func backstopKeptAsCloseArrival() async {
        let unsent = ParentLockerMemoryUnsentStore()
        let mac = Fix1105CDevice(site: site, clock: clock, unsent: unsent)
        site.failuresLeft = 1
        mac.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await mac.sync.runDue()
        #expect(mac.sync.status.state == .retrying)

        // A change synced in schedules the guide's backstop; one of her own is then kept with what's owed.
        mac.imports([Device.wren: Device.mark(.tardy)])
        mac.marks([Device.odile: Device.mark(.tardy)])
        #expect(unsent.load()?.reason == "closeArrival")
        mac.sync.stop()

        // A relaunch, then Close Arrival's Undo.
        let again = Fix1105CDevice(site: site, clock: clock, unsent: unsent)
        again.undoesCloseArrival()
        await again.sync.runDue()
        #expect(saves.isEmpty, "the reopened class never goes")
        #expect(again.store.recordedSends.isEmpty)
    }

    // MARK: - E9 Signed out on another device

    @Test("Signed out on another device while Close Arrival's send waits: the phone asks to sign in (E9)")
    func signedOutElsewhereAsks() async throws {
        let phone = Fix1105CDevice(site: site, clock: clock, role: .assistant)
        site.failuresLeft = 1
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await phone.sync.runDue()
        #expect(phone.sync.status.state == .retrying)

        try phone.secrets.deletePassword(site: FakeParentLocker.host)
        phone.sync.appReturned()
        #expect(!phone.sync.isSignedIn)
        #expect(phone.sync.awaitsSignIn)
        #expect(phone.sync.closeArrivalSendUnsent)
    }

    @Test("Her own Sign Out keeps the Close Arrival but doesn't ask her to sign in again (E9)")
    func ownSignOutDoesNotAsk() async throws {
        let phone = Fix1105CDevice(site: site, clock: clock, role: .assistant)
        site.failuresLeft = 1
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await phone.sync.runDue()

        try phone.sync.signOut()
        #expect(!phone.sync.awaitsSignIn)
        #expect(phone.sync.closeArrivalSendUnsent)
    }

    // MARK: - E10 Two live retries

    @Test("A live update's retry taking another's place still sends the first one's change synced in (E10)")
    func liveRetriesMerge() async {
        let device = Fix1105CDevice(site: site, clock: clock, sent: true)
        device.imports([Device.wren: Device.mark(.tardy)])
        await device.sync.baselineTask?.value
        clock.advance(by: ParentLockerSync.importedWait)
        site.failuresLeft = 1
        await device.sync.runDue()
        #expect(device.sync.status.state == .retrying)

        // Odile is marked here, and her update fails too.
        clock.advance(by: 1)
        device.marks([Device.odile: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        site.failuresLeft = 1
        await device.sync.runDue()

        clock.advance(by: ParentLockerSync.retryWaits[0])
        await device.sync.runDue()
        #expect(site.mark(41002) == "702")
        #expect(site.mark(40001) == "702", "Wren's change synced in still went")
    }

    // MARK: - E11 A wake with nothing to run

    @Test("A wake after midnight with nothing left to run lets the background window go (E11)")
    func wakeAfterMidnight() async {
        let phone = Fix1105CDevice(site: site, clock: clock, role: .assistant)
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        #expect(phone.background.isHeld)
        #expect(phone.sync.closeArrivalSendUnsent)

        clock.advance(by: 86_400)
        await phone.sync.runDue()
        #expect(site.requests.isEmpty)
        #expect(!phone.background.isHeld)
        #expect(!phone.sync.closeArrivalSendUnsent)
    }
}
