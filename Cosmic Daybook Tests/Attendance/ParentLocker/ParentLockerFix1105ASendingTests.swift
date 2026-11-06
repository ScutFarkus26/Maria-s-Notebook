import Foundation
import Testing
@testable import CosmicDaybook

/// The engine's sending, as the 2026-11-05 bug hunt found it (report
/// "ParentLocker in the Assistant bug hunt 2026-11-05", #1, #2, #3): the
/// class's retry kept whatever comes meanwhile, what's owed kept across a
/// relaunch, and a lost reply. Over the fake site, clock and keychain.
@Suite("ParentLocker fixes 2026-11-05: sending")
@MainActor
struct ParentLockerFix1105ASendingTests {

    typealias Device = ParentLockerTestDevice
    typealias Marks = Fix1105AMarks

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    /// Close Arrival & Send on `device`, failing `failures` times, run when it's due.
    private func closeArrivalFails(_ sync: ParentLockerSync, failures: Int) async {
        site.failuresLeft = failures
        sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await sync.runDue()
        #expect(sync.status.state == .retrying)
    }

    // MARK: - #1 Live updates wait for the class's retry

    @Test("A late mark while Close Arrival's send waits to retry waits for it: the class goes and is recorded (#1)")
    func lateMarkWaitsForTheClass() async {
        let device = Device(site: site, clock: clock, marks: Marks.closed)
        await closeArrivalFails(device.sync, failures: 2)

        // Bea walks in during the 30 s wait.
        clock.advance(by: 3)
        device.marks([Device.bea: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.requests.filter { $0 == "courses" }.count == 1, "her update waits for the class")
        #expect(!device.background.isHeld, "nothing keeps the phone awake through the wait")

        // The class's own retries: the first fails too, the second goes.
        clock.advance(by: ParentLockerSync.retryWaits[0] - 3 - ParentLockerSync.localQuiet)
        await device.sync.runDue()
        clock.advance(by: ParentLockerSync.retryWaits[1])
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.mark(41004) == "702", "Bea goes Late with the class")
        #expect(device.store.recordedSends.count == 1)
        #expect(device.sync.status.state == .upToDate)
    }

    @Test("Undo while Close Arrival's send waits to retry still stops it, though a mark came meanwhile (#1)")
    func undoAfterALateMark() async {
        let device = Device(site: site, clock: clock, marks: Marks.closed)
        await closeArrivalFails(device.sync, failures: 2)
        clock.advance(by: 3)
        device.marks([Device.bea: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()

        device.sync.cancelCloseArrivalSend()
        device.store.state.arrivalClosed = false
        for wait in ParentLockerSync.retryWaits {
            clock.advance(by: wait)
            await device.sync.runDue()
        }
        #expect(saves.isEmpty, "nothing of the reopened class goes")
        #expect(device.store.recordedSends.isEmpty)
    }

    @Test("A Send Now that fails while Close Arrival's send waits to retry keeps it one, so Undo stops it (#1)")
    func failedSendNowKeepsCloseArrival() async {
        let device = Device(site: site, clock: clock, marks: Marks.closed)
        await closeArrivalFails(device.sync, failures: 2)
        await device.sync.sendNow(day: Device.morning)
        #expect(device.sync.status.state == .retrying)

        device.sync.cancelCloseArrivalSend()
        device.store.state.arrivalClosed = false
        device.store.state.marks[Device.bea] = nil
        for wait in ParentLockerSync.retryWaits {
            clock.advance(by: wait)
            await device.sync.runDue()
        }
        #expect(saves.isEmpty)
    }

    @Test("Two past days' failed sends each keep their own retry (#1)")
    func pastDaysKeepTheirRetries() async {
        let device = Device(site: site, clock: clock, sent: true, marks: Marks.everyonePresent)
        site.failuresLeft = 2
        await device.sync.sendNow(day: Device.morning.addingTimeInterval(-3 * 86_400))
        await device.sync.sendNow(day: Device.morning.addingTimeInterval(-4 * 86_400))
        clock.advance(by: ParentLockerSync.retryWaits[0])
        await device.sync.runDue()
        #expect(site.requests.filter { $0 == "courses 2026-10-9" }.count == 2, "Friday's went again")
        #expect(site.requests.filter { $0 == "courses 2026-10-8" }.count == 2, "and Thursday's")
    }

    // MARK: - #2 What's owed, kept across a relaunch

    @Test("A mark made while the class's send is under way, then a relaunch, still sends the class (#2)")
    func markDuringTheRunKeepsTheClass() async {
        let unsent = ParentLockerMemoryUnsentStore()
        let phone = Fix1105ADevice(site: site, clock: clock, role: .assistant, unsent: unsent, marks: Marks.closed)
        let killedNow = Fix1105ABox<ParentLockerUnsent?>(nil)
        phone.wire.duringRun = {
            phone.marks([Device.bea: Device.mark(.tardy)])
            // What iOS ending the app right now would leave.
            killedNow.value = unsent.load()
        }
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await phone.sync.runDue()
        #expect(killedNow.value?.wholeClass == true)

        // Relaunched from what was kept then, against a ParentLocker that never got the class.
        let fresh = FakeParentLocker()
        var marks = Marks.closed
        marks[Device.bea] = Device.mark(.tardy)
        let relaunched = Device(
            site: fresh, clock: clock, role: .assistant,
            unsent: ParentLockerMemoryUnsentStore(killedNow.value), marks: marks
        )
        await relaunched.sync.runDue()
        #expect(fresh.saves.count == 2, "the whole class goes")
        #expect(fresh.mark(41004) == "702")
    }

    @Test("A mark made while the class's send waits to retry, then a relaunch, still sends the class (#2)")
    func markDuringTheRetryKeepsTheClass() async {
        let unsent = ParentLockerMemoryUnsentStore()
        let before = Device(site: site, clock: clock, role: .assistant, unsent: unsent, marks: Marks.closed)
        await closeArrivalFails(before.sync, failures: 1)
        before.marks([Device.bea: Device.mark(.tardy)])
        #expect(unsent.load()?.wholeClass == true)
        before.sync.stop()

        var marks = Marks.closed
        marks[Device.bea] = Device.mark(.tardy)
        let after = Device(site: site, clock: clock, role: .assistant, unsent: unsent, marks: marks)
        await after.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(after.store.recordedSends.count == 1)
    }

    // MARK: - #3 A lost reply

    @Test("A save whose reply was lost is this device's own on the retry, and the day is recorded (#3)")
    func lostReplyStillRecords() async {
        let phone = Fix1105ADevice(site: site, clock: clock, role: .assistant, marks: Marks.closed)
        phone.wire.lostReplies = [5102]
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await phone.sync.runDue()
        #expect(phone.sync.status.state == .retrying)
        #expect(site.mark(41004) == "703", "the save reached ParentLocker")

        clock.advance(by: ParentLockerSync.retryWaits[0])
        await phone.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"], "nothing went twice")
        #expect(phone.store.recordedSends.count == 1)
        #expect(phone.sync.status.state == .upToDate)
        #expect(phone.sync.status.problems.isEmpty)
    }

    @Test("The guide's backstop still leaves a class another device sent to it, and its record (#3)")
    func backstopStillLeavesOthersSend() async {
        let phone = Fix1105ADevice(site: site, clock: clock, role: .assistant, marks: Marks.closed)
        let mac = Device(site: site, clock: clock, marks: Marks.closed)
        phone.wire.lostReplies = [5102]
        phone.sync.closeArrivalSend(on: Device.morning, after: 6)
        mac.imports([Device.bea: Marks.automatic])
        await mac.sync.baselineTask?.value
        clock.advance(by: Marks.sendsAfter)
        await phone.sync.runDue()
        // Bea walks in; the phone's retry carries her Late. Nothing has synced to the Mac.
        phone.marks([Device.bea: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.retryWaits[0])
        await phone.sync.runDue()
        #expect(site.mark(41004) == "702")
        let sent = site.saves.count

        clock.advance(by: ParentLockerSync.backstopWait)
        await mac.sync.runDue()
        #expect(site.saves.count == sent)
        #expect(site.mark(41004) == "702")
        #expect(mac.store.recordedSends.isEmpty, "the phone's record is on its way")
    }
}
