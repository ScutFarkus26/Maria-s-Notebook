import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The engine's timing, as the afternoon bug hunt of 2026-10-13 found it
/// (report "ParentLocker bug hunt 2026-10-13 afternoon", H3, H4, H5, M5): the
/// guide's backstop across a new day, a mark made seconds before another
/// device closes arrival, a phone that closed arrival offline coming back,
/// and a change synced in whose class lists can't be read. Over the fake
/// site, clock and keychain.
@Suite("ParentLocker afternoon fixes: timing")
@MainActor
struct ParentLockerAfternoonTimingTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    private static let automatic = Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)

    private static let everyonePresent: [UUID: ParentLockerPlanner.DayMark] = Device.children.reduce(into: [:]) {
        $0[$1.id] = Device.mark(.present)
    }

    /// Everyone Present here and in ParentLocker.
    private func settled(_ device: Device) {
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        device.store.state.marks = Self.everyonePresent
    }

    // MARK: - H3 The guide's backstop on a new day

    @Test("A new day's first change keeps the guide's backstop, and the Mac's line moves on at midnight")
    func backstopSpansADay() async throws {
        let mac = Device(site: site, clock: clock, arrivalClosed: false, marks: Self.everyonePresent)
        let center = NotificationCenter()
        let watcher = ParentLockerWatcher(
            context: try CoreDataTestHelpers.makeContext(), sync: mac.sync, center: center
        )
        // Monday goes, and the line says so.
        await mac.sync.sendNow(day: Device.morning)
        #expect(mac.sync.status.state == .upToDate)

        // Midnight: a new day, nothing taken yet, nothing in ParentLocker for it.
        let tuesday = try #require(AppCalendar.shared.date(byAdding: .day, value: 1, to: Device.morning))
        clock.advance(by: tuesday.timeIntervalSince(clock.now) - 8 * 3_600 + 30)
        mac.store.state.marks = [:]
        for kid in site.kids.indices { site.kids[kid].markID = nil }
        site.requests = []
        center.post(name: .NSCalendarDayChanged, object: nil)
        for _ in 0..<100 where mac.sync.status.state == .upToDate { await Task.yield() }
        #expect(mac.sync.status == ParentLockerStatus(state: .waitingForArrival), "yesterday's line is gone")

        // 8:50: a phone that isn't signed in closes arrival; it syncs in.
        clock.advance(by: 8 * 3_600 + 50 * 60)
        mac.store.state.arrivalClosed = true
        var closed = Self.everyonePresent
        closed[Device.wren] = Self.automatic
        mac.imports(closed, on: clock.now)
        await mac.sync.baselineTask?.value
        clock.advance(by: ParentLockerSync.backstopWait)
        await mac.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(site.mark(40001) == "703")
        #expect(mac.store.recordedSends.count == 2, "Monday's and Tuesday's")
        withExtendedLifetime(watcher) {}
    }

    // MARK: - H4 A mark made just before another device closes arrival

    @Test("Marks the guide makes at 8:44:50 reach ParentLocker though an assistant closes arrival seconds later")
    func markJustBeforeClose() async {
        clock.advance(by: 44 * 60 + 50)
        var before = Self.everyonePresent
        before[Device.wren] = nil
        let mac = Device(site: site, clock: clock, arrivalClosed: false, marks: before)
        let phone = Device(site: site, clock: clock, role: .assistant, arrivalClosed: false, marks: before)
        // 8:44:50 on the Mac: Wren walks in, and Odile was late after all.
        mac.marks([Device.wren: Device.mark(.present), Device.odile: Device.mark(.tardy)])

        // 8:44:55 the assistant closes arrival without having seen either:
        // Wren goes absent there, and the class goes once her Undo has passed.
        clock.advance(by: 5)
        phone.store.state.arrivalClosed = true
        phone.marks([Device.wren: Self.automatic])
        phone.sync.closeArrivalSend(on: clock.now, after: 6)
        clock.advance(by: 6)
        await phone.sync.runDue()
        #expect(site.mark(40001) == "703")
        #expect(site.mark(41002) == "701")

        // The close syncs in to the Mac, where Wren's own mark still wins;
        // then the assistant's send record.
        clock.advance(by: 9)
        mac.store.state.arrivalClosed = true
        mac.sync.noteChanges([Device.wren], imported: true, on: clock.now)
        await mac.sync.baselineTask?.value
        clock.advance(by: 20)
        mac.store.state.sentToParentLocker = true

        // The guide's backstop is refused (the day went); the marks still go.
        clock.advance(by: ParentLockerSync.backstopWait)
        await mac.sync.runDue()
        #expect(site.mark(40001) == "701", "Wren is here")
        #expect(site.mark(41002) == "702", "Odile was late")
        #expect(mac.store.recordedSends.isEmpty)
        #expect(mac.sync.status.problems.isEmpty)
    }

    // MARK: - H5 A phone that closed arrival offline comes back

    /// A phone closes arrival with Bea not in yet, and can't reach ParentLocker;
    /// the guide's Mac marks Bea in when she arrives and its backstop sends
    /// the class. Returns the phone, still holding its own view.
    private func offlineClose() async -> Device {
        var marks = Self.everyonePresent
        marks[Device.bea] = Self.automatic
        let phone = Device(
            site: site, clock: clock, role: .assistant, importsExpected: true, marks: marks
        )
        phone.sync.importFinished()
        let mac = Device(site: site, clock: clock, arrivalClosed: false, marks: Self.everyonePresent)
        site.failuresLeft = 1
        phone.sync.closeArrivalSend(on: clock.now, after: 6)
        clock.advance(by: 6)
        await phone.sync.runDue()
        #expect(phone.sync.status.state == .retrying)

        clock.advance(by: 4)
        mac.store.state.arrivalClosed = true
        mac.imports([Device.bea: Self.automatic])
        mac.store.state.marks[Device.bea] = Device.mark(.present)
        await mac.sync.baselineTask?.value
        clock.advance(by: ParentLockerSync.backstopWait)
        await mac.sync.runDue()
        #expect(site.mark(41004) == "701")
        #expect(mac.store.recordedSends.count == 1)
        return phone
    }

    @Test("Back before the import, a phone that closed arrival offline doesn't send its stale view")
    func offlinePhoneReturnsBeforeImport() async {
        let phone = await offlineClose()
        let sent = site.saves.count

        // Twenty minutes later the phone comes back; CloudKit hasn't caught up.
        clock.advance(by: 20 * 60)
        phone.sync.appReturned()
        await phone.sync.runDue()
        #expect(site.saves.count == sent, "the retry waits for the import")
        #expect(site.mark(41004) == "701")

        // The import: Bea is in, and the day was sent.
        phone.store.state.marks[Device.bea] = Device.mark(.present)
        phone.store.state.sentToParentLocker = true
        phone.sync.importFinished()
        await phone.sync.runDue()
        #expect(site.mark(41004) == "701")
        #expect(phone.store.recordedSends.isEmpty, "no second, late send recorded")
    }

    @Test("With no import in time, the phone's owed send leaves what others saved since alone")
    func offlinePhoneWithoutImport() async {
        let phone = await offlineClose()
        clock.advance(by: 20 * 60)
        phone.sync.appReturned()
        clock.advance(by: ParentLockerSync.importWaitLimit)
        await phone.sync.runDue()
        #expect(site.mark(41004) == "701", "Bea stays in")
        #expect(phone.store.recordedSends.isEmpty)
    }

    // MARK: - M5 A change synced in with no class lists read

    @Test("A change synced in goes though the class lists couldn't be read as it arrived, by the mark before it")
    func importWithFailedRead() async {
        let mac = Device(site: site, clock: clock, sent: true, marks: Self.everyonePresent)
        settled(mac)
        // Someone else saved Wren Absent since; Odile's phone is offline.
        site.setMark(40001, "703")
        site.failuresLeft = 1
        mac.imports([Device.odile: Device.mark(.absent, reason: "sick"), Device.wren: Device.mark(.tardy)])
        await mac.sync.baselineTask?.value
        #expect(mac.sync.lastSeen.isEmpty, "the read failed")
        clock.advance(by: ParentLockerSync.importedWait)
        await mac.sync.runDue()
        #expect(site.mark(41002) == "703", "ParentLocker still held Odile's mark from before the change")
        #expect(site.kids[3].comment == "Sick")
        #expect(site.mark(40001) == "703", "Wren is left to the device that saved her")
    }

    @Test("A change synced in waits for the class lists still being read, then goes")
    func importWithLateRead() async throws {
        let mac = Device(site: site, clock: clock, secrets: FakeParentLockerSecrets(cookie: nil), sent: true,
                         marks: Self.everyonePresent)
        settled(mac)
        site.signInYields = 50
        mac.imports([Device.odile: Device.mark(.absent, reason: "sick")])
        for _ in 0..<1_000 where !mac.sync.readingBaseline { await Task.yield() }
        try #require(mac.sync.readingBaseline)
        clock.advance(by: ParentLockerSync.importedWait)
        await mac.sync.runDue()
        await mac.sync.baselineTask?.value
        await mac.sync.runDue()
        #expect(site.mark(41002) == "703")
        #expect(site.kids[3].comment == "Sick")
    }
}
