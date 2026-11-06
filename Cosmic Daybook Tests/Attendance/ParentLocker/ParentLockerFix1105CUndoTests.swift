import Foundation
import Testing
@testable import CosmicDaybook

/// Close Arrival's Undo against a send under way, and a retry inside a new
/// Undo window, as the review of the 2026-11-05 engine fixes found them
/// (report "ParentLocker in the Assistant bug hunt 2026-11-05", Review of
/// the fixes, E1, E2, E12; W6's engine side). Over the fake site, clock and
/// keychain.
@Suite("ParentLocker fixes 2026-11-05 C: Undo and a send under way")
@MainActor
struct ParentLockerFix1105CUndoTests {

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

    // MARK: - E1 The send under way

    @Test("The sync says Close Arrival & Send is under way from the moment it's taken until its run ends (E1)")
    func underWayWhileItRuns() async {
        let device = Fix1105CDevice(site: site, clock: clock, marks: Marks.closed)
        let seen = Fix1105ABox<[Bool]>([])
        device.wire.atRoster = { seen.value.append(device.sync.closeArrivalSendUnderWay) }
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        #expect(!device.sync.closeArrivalSendUnderWay, "waiting out its Undo, nothing is under way")
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(seen.value == [true])
        #expect(!device.sync.closeArrivalSendUnderWay, "the run has ended")
        #expect(saves == ["save 5101", "save 5102"])
    }

    @Test("A failed run takes the flag down while its retry waits, and a retry under way puts it up again (E1)")
    func underWayAcrossARetry() async {
        let device = Fix1105CDevice(site: site, clock: clock, marks: Marks.closed)
        site.failuresLeft = 1
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(device.sync.status.state == .retrying)
        #expect(!device.sync.closeArrivalSendUnderWay)

        let seen = Fix1105ABox<[Bool]>([])
        device.wire.atRoster = { seen.value.append(device.sync.closeArrivalSendUnderWay) }
        clock.advance(by: ParentLockerSync.retryWaits[0])
        await device.sync.runDue()
        #expect(seen.value == [true])
        #expect(!device.sync.closeArrivalSendUnderWay)
    }

    @Test("Taken while a class list is read for a change synced in, it's under way; Undo stops it all (E1, W6)")
    func takenWhileAListIsRead() async {
        let mac = Fix1105CDevice(site: site, clock: clock, marks: Marks.closed)
        mac.sync.closeArrivalSend(on: Device.morning, after: 6)
        // A change synced in, with nothing seen of Wren today: her class lists are read, slowly.
        mac.wire.holdsRosters = true
        mac.imports([Device.wren: Device.mark(.tardy)])
        await fix1105CYield { mac.wire.waiting > 0 }
        #expect(mac.wire.waiting == 1)

        clock.advance(by: Marks.sendsAfter)
        let running = Task { await mac.sync.runDue() }
        await fix1105CYield { mac.sync.closeArrivalSendUnderWay }
        #expect(mac.sync.closeArrivalSendUnderWay, "taken, waiting for the class lists")

        mac.undoesCloseArrival()
        mac.wire.release()
        await running.value
        await mac.sync.baselineTask?.value
        #expect(saves.isEmpty, "nothing of the reopened class goes")
        #expect(mac.store.recordedSends.isEmpty)
        #expect(!mac.sync.closeArrivalSendUnderWay)
        #expect(!mac.sync.isAfter(mac.store.day(Device.morning, withChildren: false), on: Device.morning))
        #expect(mac.unsent.load()?.wholeClass != true)
    }

    @Test("Undo during a run, after a class has gone: no further class goes, nothing is recorded or retried (E1, E12)")
    func undoDuringTheRun() async {
        let device = Fix1105CDevice(site: site, clock: clock, marks: Marks.closed)
        device.wire.afterSave[5101] = { device.undoesCloseArrival() }
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(saves == ["save 5101"], "the second class doesn't go")
        #expect(site.mark(41004) == nil, "Bea's automatic absence never reached ParentLocker")
        #expect(device.store.recordedSends.isEmpty)
        #expect(!device.sync.closeArrivalSendUnderWay)
        #expect(device.unsent.load()?.wholeClass != true, "nothing is owed")

        for wait in ParentLockerSync.retryWaits {
            clock.advance(by: wait)
            await device.sync.runDue()
        }
        #expect(saves == ["save 5101"], "and nothing is retried")
    }

    @Test("Undo during a run that then fails leaves no retry to send the reopened class (E1, E12)")
    func undoDuringAFailingRun() async {
        let device = Fix1105CDevice(site: site, clock: clock, marks: Marks.closed)
        device.wire.atRoster = {
            device.undoesCloseArrival()
            site.failuresLeft = 2
        }
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: Marks.sendsAfter)
        await device.sync.runDue()
        #expect(saves.isEmpty)

        for wait in ParentLockerSync.retryWaits {
            clock.advance(by: wait)
            await device.sync.runDue()
        }
        #expect(saves.isEmpty, "the reopened class never goes")
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.unsent.load()?.wholeClass != true)
    }

    // MARK: - E2 A retry inside a new Undo window

    @Test("A Send Now's retry waits out a new Close Arrival's Undo, and the two go as one send (E2, E12)")
    func retryWaitsOutTheUndo() async {
        let device = Device(site: site, clock: clock, arrivalClosed: false, marks: Self.allButBea)
        site.failuresLeft = 1
        await device.sync.sendNow(day: Device.morning)
        #expect(device.sync.status.state == .retrying)

        // Close Arrival & Send 25 s later marks Bea absent; its Undo runs to 31 s, the send to 32 s.
        clock.advance(by: 25)
        device.store.state.marks[Device.bea] = Marks.automatic
        device.store.state.arrivalClosed = true
        device.sync.closeArrivalSend(on: clock.now, after: 6)
        #expect(device.sync.nextWake == Device.morning.addingTimeInterval(32))

        clock.advance(by: 5)
        await device.sync.runDue()
        #expect(saves.isEmpty, "the retry doesn't go inside the Undo window")

        clock.advance(by: 2)
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.requests.filter { $0 == "courses" }.count == 2, "one send after the failed one, not two")
        #expect(device.store.recordedSends.count == 1)
    }

    @Test("Undo inside the window, with a Send Now's retry waiting: Bea's automatic absence never goes (E2, E12)")
    func undoWithARetryWaiting() async {
        let device = Device(site: site, clock: clock, arrivalClosed: false, marks: Self.allButBea)
        site.failuresLeft = 1
        await device.sync.sendNow(day: Device.morning)
        clock.advance(by: 25)
        device.store.state.marks[Device.bea] = Marks.automatic
        device.store.state.arrivalClosed = true
        device.sync.closeArrivalSend(on: clock.now, after: 6)

        clock.advance(by: 5)
        await device.sync.runDue()
        #expect(saves.isEmpty)
        device.sync.cancelCloseArrivalSend()
        device.store.state.arrivalClosed = false
        device.store.state.marks[Device.bea] = nil

        clock.advance(by: 1)
        await device.sync.runDue()
        #expect(site.mark(41004) == nil, "the absence Undo took back never reached ParentLocker")
        #expect(site.mark(40001) == "701", "the Send Now still sent the rest")
    }
}
