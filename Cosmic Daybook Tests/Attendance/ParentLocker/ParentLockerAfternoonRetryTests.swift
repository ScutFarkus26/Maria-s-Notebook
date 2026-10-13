import Foundation
import Testing
@testable import CosmicDaybook

/// Retries and sign-ins, as the afternoon bug hunt of 2026-10-13 found them
/// (report "ParentLocker bug hunt 2026-10-13 afternoon", H2's engine side,
/// L8, L9, M9): Close Arrival's Undo after its send failed, one retry slot, a
/// "couldn't send" with nothing owed, and a sign-in ParentLocker wants a
/// person for. Over the fake site, clock and keychain.
@Suite("ParentLocker afternoon fixes: retries and sign-ins")
@MainActor
struct ParentLockerAfternoonRetryTests {

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

    // MARK: - H2's engine side: Undo after a failed Close Arrival & Send

    @Test("Close Arrival's Undo after its send failed stops the retry, and arrival is open here again")
    func undoStopsRetry() async {
        var marks = Self.everyonePresent
        marks[Device.bea] = Self.automatic
        let device = Device(site: site, clock: clock, marks: marks)
        site.failuresLeft = 1
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(device.sync.status.state == .retrying)

        // Siri's Undo: Bea is unmarked again, and no automatic absence is left.
        device.sync.cancelCloseArrivalSend()
        device.store.state.arrivalClosed = false
        device.store.state.marks[Device.bea] = nil
        clock.advance(by: ParentLockerSync.retryWaits[0])
        await device.sync.runDue()
        #expect(saves.isEmpty, "the reopened class doesn't go")
        #expect(device.unsent.load() == nil)
        #expect(!device.sync.isAfter(device.store.day(Device.morning, withChildren: false), on: Device.morning))
    }

    @Test("Close Arrival's Undo after its retries ran out takes back the send owed")
    func undoStopsOwedSend() async {
        var marks = Self.everyonePresent
        marks[Device.bea] = Self.automatic
        let device = Device(site: site, clock: clock, marks: marks)
        site.failuresLeft = 4
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 6)
        await device.sync.runDue()
        for wait in ParentLockerSync.retryWaits {
            clock.advance(by: wait)
            await device.sync.runDue()
        }
        #expect(device.sync.status.state == .gaveUp)

        device.sync.cancelCloseArrivalSend()
        device.store.state.arrivalClosed = false
        device.store.state.marks[Device.bea] = nil
        device.sync.appReturned()
        await device.sync.runDue()
        #expect(saves.isEmpty)
        #expect(device.unsent.load() == nil)
    }

    // MARK: - L8 One retry slot

    @Test("A past day's failed send keeps its own retry, and today's still goes on time")
    func pastDayRetryKeepsToday() async {
        let device = Device(site: site, clock: clock, sent: true, marks: Self.everyonePresent)
        settled(device)
        site.failuresLeft = 1
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(device.sync.status.state == .retrying)

        clock.advance(by: 6)
        site.failuresLeft = 1
        let friday = Device.morning.addingTimeInterval(-3 * 86_400)
        await device.sync.sendNow(day: friday)
        clock.advance(by: ParentLockerSync.retryWaits[0] - 6)
        await device.sync.runDue()
        #expect(site.mark(40001) == "702", "today's retry went on time")
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(site.requests.filter { $0 == "courses 2026-10-9" }.count == 2, "and Friday's too")
    }

    // MARK: - L9 "Couldn't send yet" with nothing owed

    @Test("Couldn't send yet clears on the way back when nothing is owed")
    func notSentYetClearsWithNothingOwed() async {
        final class Flag { var value = false }
        let inFront = Flag()
        let device = Device(
            site: site, clock: clock, secrets: FakeParentLockerSecrets(cookie: "expired"),
            inForeground: { inFront.value }, sent: true, marks: Self.everyonePresent
        )
        settled(device)
        // A change synced in, tried in the background: it's left to its own device.
        device.imports([Device.odile: Device.mark(.absent)])
        await device.sync.baselineTask?.value
        clock.advance(by: ParentLockerSync.importedWait)
        await device.sync.runDue()
        #expect(device.sync.status.state == .notSentYet)

        inFront.value = true
        device.sync.appReturned()
        await device.sync.runDue()
        #expect(!device.sync.status.isTrouble)
        #expect(device.sync.status.message == nil)
    }

    // MARK: - M9 A sign-in ParentLocker wants a person for

    @Test("ParentLocker wanting a person at sign-in asks for a sign-in, and the app stops trying by itself")
    func needsYouStopsTrying() async throws {
        let device = Device(site: site, clock: clock, secrets: FakeParentLockerSecrets(cookie: "expired"),
                            sent: true, marks: Self.everyonePresent)
        settled(device)
        site.signInNeedsYou = true
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(site.signIns == 1)
        #expect(device.sync.status.state == .needsYou)
        #expect(device.sync.signInNeedsYou)
        #expect(device.sync.needsSignIn, "the screens offer Sign In")

        // The next change, a return, Send Now: none tries again.
        device.marks([Device.june: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        device.sync.appReturned()
        await device.sync.runDue()
        #expect(site.signIns == 1)
        #expect(saves.isEmpty)

        // Signing in through the sheet clears it, and what waited goes.
        site.signInNeedsYou = false
        try await device.sync.signIn(email: "guide@school.test", password: site.password)
        #expect(!device.sync.signInNeedsYou)
        #expect(!device.sync.needsSignIn)
        await device.sync.runDue()
        #expect(Set(site.saves.flatMap(\.entries).map(\.studentID)) == ["40001", "40002"])
    }
}
