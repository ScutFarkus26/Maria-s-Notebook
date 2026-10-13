import Foundation
import Testing
@testable import CosmicDaybook

/// When the class goes to ParentLocker and what goes (plan "ParentLocker
/// attendance", Phase 2b): nothing before "after", the whole class at Close
/// Arrival once Undo has gone, then each change live (4 s for this device's,
/// 60 s for one synced in), the guide's backstop, and the catch-up after the
/// first import. Over a fake site, a clock moved by hand and a fake keychain.
@Suite("ParentLocker sync")
@MainActor
struct ParentLockerSyncTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    /// Every child marked as ParentLocker already holds them: Present, except June Absent.
    private func settled(_ device: Device) {
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        site.setMark(40002, "703")
        device.store.state.marks = [
            Device.wren: Device.mark(.present), Device.june: Device.mark(.absent, reason: "sick"),
            Device.marisol: Device.mark(.present), Device.odile: Device.mark(.present),
            Device.bea: Device.mark(.present)
        ]
        site.kids[1].comment = "Sick"
    }

    // MARK: - Nothing before "after"

    @Test("Before arrival closes, no change is sent or even scheduled")
    func nothingBeforeAfter() async {
        let device = Device(site: site, clock: clock, arrivalClosed: false)
        device.marks([Device.wren: Device.mark(.present)])
        device.imports([Device.june: Device.mark(.tardy)])
        #expect(device.sync.nextWake == nil)
        clock.advance(by: 120)
        await device.sync.runDue()
        #expect(site.requests.isEmpty)
        #expect(device.sync.status.state == .waitingForArrival)
    }

    @Test("Arrival closed on an unsigned phone starts live updates, and the guide's backstop sends once")
    func unsignedPhoneAndBackstop() async {
        let phone = Device(site: site, clock: clock, role: .assistant, secrets: FakeParentLockerSecrets(password: nil))
        #expect(!phone.sync.isSignedIn)
        let closed: [UUID: ParentLockerPlanner.DayMark] = [
            Device.wren: Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw),
            Device.june: Device.mark(.present)
        ]
        phone.marks(closed)
        #expect(phone.sync.nextWake == nil)

        let guide = Device(site: site, clock: clock)
        guide.imports(closed)
        clock.advance(by: 59)
        await guide.sync.runDue()
        #expect(site.requests.isEmpty)
        clock.advance(by: 1)
        await guide.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(guide.store.recordedSends.count == 1)
        #expect(site.mark(40001) == "703")
        #expect(site.kids[0].comment.isEmpty)

        // A later change synced in goes live, by itself, and the backstop doesn't go again.
        site.requests = []
        guide.imports([Device.marisol: Device.mark(.tardy)])
        clock.advance(by: 60)
        await guide.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(site.saves.last?.entries.map(\.studentID) == ["40003"])
        #expect(guide.store.recordedSends.count == 1)
    }

    // MARK: - Close Arrival & Send

    @Test("Undo inside Close Arrival's window sends nothing")
    func undoSendsNothing() async {
        let device = Device(site: site, clock: clock)
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        device.marks([Device.wren: Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)])
        clock.advance(by: 4)
        await device.sync.runDue()
        #expect(site.requests.isEmpty, "the change waits for the Close Arrival send")

        device.sync.cancelCloseArrivalSend()
        device.store.state.arrivalClosed = false
        device.marks([Device.wren: Device.mark(.unmarked)])
        clock.advance(by: 60)
        await device.sync.runDue()
        #expect(site.requests.isEmpty)
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.unsent.load() == nil)
    }

    @Test("Close Arrival sends the whole class once, one save per class, and records it once")
    func closeArrivalSendsOncePerClass() async {
        let device = Device(site: site, clock: clock, marks: [
            Device.wren: Device.mark(.present), Device.june: Device.mark(.tardy),
            Device.marisol: Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw),
            Device.odile: Device.mark(.present), Device.bea: Device.mark(.absent, reason: "sick")
        ])
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        device.marks([Device.marisol: Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)])
        #expect(device.background.isHeld, "a phone locked now still sends")
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.saves.map(\.entries.count) == [3, 2])
        #expect(site.mark(41004) == "703")
        #expect(site.kids.first { $0.studentID == 41004 }?.comment == "Sick")
        #expect(device.store.recordedSends.count == 1)
        #expect(device.sync.status.state == .upToDate)

        clock.advance(by: 60)
        await device.sync.runDue()
        #expect(saves.count == 2)
        #expect(!device.background.isHeld)
    }

    // MARK: - Live updates

    @Test("This device's changes wait 4 s of quiet, go together, and only those children")
    func localChangesCoalesce() async {
        let device = Device(site: site, clock: clock, sent: true)
        settled(device)
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: 2)
        device.marks([Device.marisol: Device.mark(.absent, reason: "appointment")])
        clock.advance(by: 3)
        await device.sync.runDue()
        #expect(site.requests.isEmpty, "3 s after the last change")
        clock.advance(by: 1)
        await device.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(Set(site.saves[0].entries.map(\.studentID)) == ["40001", "40003"])
        #expect(site.kids[2].comment == "Appointment")
        #expect(device.store.recordedSends.isEmpty, "a live update isn't the day's send")
        #expect(device.unsent.load() == nil)
    }

    @Test("A change synced in waits 60 s and isn't sent when ParentLocker already has it")
    func importedChangesWait() async {
        let device = Device(site: site, clock: clock, sent: true)
        settled(device)
        // Another device marked Wren late and has sent it.
        site.setMark(40001, "702")
        device.imports([Device.wren: Device.mark(.tardy)])
        clock.advance(by: 59)
        await device.sync.runDue()
        #expect(site.requests.isEmpty)
        clock.advance(by: 1)
        await device.sync.runDue()
        #expect(site.requests.contains("courses"))
        #expect(saves.isEmpty)

        // A phone that marked Odile absent is offline: this device sends it.
        device.imports([Device.odile: Device.mark(.absent)])
        clock.advance(by: 60)
        await device.sync.runDue()
        #expect(saves == ["save 5102"])
        #expect(site.saves.last?.entries.map(\.studentID) == ["41002"])
    }

    @Test("A device holding a stale mark never pushes it over a newer one")
    func staleDeviceDoesNotOverwrite() async {
        let mac = Device(site: site, clock: clock, sent: true)
        let phone = Device(site: site, clock: clock, role: .assistant, sent: true)
        settled(mac)
        settled(phone)
        mac.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: 4)
        await mac.sync.runDue()
        #expect(site.mark(40001) == "702")

        // The phone hasn't seen it, and changes June.
        phone.marks([Device.june: Device.mark(.present)])
        clock.advance(by: 4)
        await phone.sync.runDue()
        #expect(site.saves.last?.entries.map(\.studentID) == ["40002"])
        #expect(site.mark(40001) == "702")

        // The Mac's change arrives on the phone; ParentLocker already has it.
        phone.imports([Device.wren: Device.mark(.tardy)])
        clock.advance(by: 60)
        await phone.sync.runDue()
        #expect(site.saves.count == 2)
        #expect(site.mark(40001) == "702")
    }

    @Test("The catch-up on launch waits for the first import, then sends what this device owes")
    func catchUpWaitsForImport() async {
        let unsent = ParentLockerMemoryUnsentStore(ParentLockerUnsent(
            day: AppCalendar.dayID(Device.morning), children: [Device.wren], wholeClass: false
        ))
        let device = Device(site: site, clock: clock, unsent: unsent, importsExpected: true, sent: true)
        settled(device)
        device.store.state.marks[Device.wren] = Device.mark(.tardy)
        await device.sync.runDue()
        #expect(device.sync.nextWake == nil)
        #expect(site.requests.isEmpty)

        device.sync.importFinished()
        await device.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(site.mark(40001) == "702")
        #expect(unsent.load() == nil)
    }

    @Test("Another day's owed changes are dropped at launch")
    func yesterdaysOwedChangesDrop() {
        let unsent = ParentLockerMemoryUnsentStore(ParentLockerUnsent(
            day: AppCalendar.dayID(Device.morning.addingTimeInterval(-86_400)),
            children: [Device.wren], wholeClass: true
        ))
        let device = Device(site: site, clock: clock, unsent: unsent, sent: true)
        #expect(device.sync.nextWake == nil)
        #expect(unsent.load() == nil)
    }
}
