import Foundation
import Testing
@testable import CosmicDaybook

/// The races and stalls the 2026-10-13 bug check found in the live sync: a
/// device holding an older change than ParentLocker, a Close Arrival with
/// nobody left to mark, a catch-up waiting for an import that never comes,
/// the Mac's app switches, and a Keychain that can't be read or won't delete.
/// Over the fake site, clock and keychain.
@Suite("ParentLocker sync races and stalls")
@MainActor
struct ParentLockerSyncRacesTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    /// Everyone marked Present here and in ParentLocker.
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

    // MARK: - #1 An older change synced in

    @Test("A change synced in late never goes over a newer one its own device already sent")
    func olderImportDoesNotOverwrite() async {
        let mac = Device(site: site, clock: clock, sent: true)
        let phone = Device(site: site, clock: clock, role: .assistant, sent: true)
        settled(mac, phone)
        // The Mac has looked at ParentLocker today: Wren Present.
        await change(mac, [Device.bea: Device.mark(.tardy)])
        #expect(site.mark(40001) == "701")

        // The phone marks Wren late, then absent, and sends both.
        await change(phone, [Device.wren: Device.mark(.tardy)])
        await change(phone, [Device.wren: Device.mark(.absent, reason: "sick")])
        #expect(site.mark(40001) == "703")
        let sent = site.saves.count

        // Only the late mark has reached the Mac so far.
        mac.imports([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.importedWait)
        await mac.sync.runDue()
        #expect(site.saves.count == sent, "the Mac leaves Wren to the phone")
        #expect(site.mark(40001) == "703")
        #expect(site.kids[0].comment == "Sick")
    }

    @Test("A change synced in from a phone that never sent it still goes, over what this device last saw")
    func offlinePhoneStillCovered() async {
        let mac = Device(site: site, clock: clock, sent: true)
        settled(mac)
        await change(mac, [Device.bea: Device.mark(.tardy)])

        // A phone offline (or not signed in) marked Odile absent; ParentLocker still has Present.
        mac.imports([Device.odile: Device.mark(.absent)])
        clock.advance(by: ParentLockerSync.importedWait)
        await mac.sync.runDue()
        #expect(site.saves.last?.entries.map(\.studentID) == ["41002"])
        #expect(site.mark(41002) == "703")
    }

    @Test("Unread as the change arrived, a child this device never saw goes only while ParentLocker holds no mark")
    func neverSeenChild() async {
        let mac = Device(site: site, clock: clock, sent: true)
        // Wren has a mark saved by someone; Odile has none yet.
        site.setMark(40001, "703")
        mac.store.state.marks = [Device.wren: Device.mark(.tardy), Device.odile: Device.mark(.tardy)]
        // The class lists can't be read as the change arrives (B4 reads them then).
        site.failuresLeft = 1
        mac.imports([Device.wren: Device.mark(.tardy), Device.odile: Device.mark(.tardy)])
        await mac.sync.baselineTask?.value
        #expect(mac.sync.lastSeen.isEmpty)
        clock.advance(by: ParentLockerSync.importedWait)
        await mac.sync.runDue()
        #expect(site.saves.flatMap(\.entries).map(\.studentID) == ["41002"])
        #expect(site.mark(40001) == "703", "left to the device that saved it")
        #expect(site.mark(41002) == "702")
    }

    // MARK: - #2 The guide's check after the due time

    /// A phone closed arrival with everyone already marked (no automatic
    /// absence) and wasn't signed in: nothing says arrival closed.
    private static let everyoneMarked: [UUID: ParentLockerPlanner.DayMark] = [
        Device.wren: Device.mark(.present), Device.june: Device.mark(.tardy),
        Device.marisol: Device.mark(.present), Device.odile: Device.mark(.absent, reason: "sick"),
        Device.bea: Device.mark(.present)
    ]

    /// 9:00, the default due time.
    private var dueCheck: Date {
        let calendar = AppCalendar.shared
        let minutes = AttendanceEmailLog.defaultDeadlineMinutes
        return calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: Device.morning))
            ?? Device.morning
    }

    @Test("A class taken with nobody left to close goes from the guide's device a minute after the due time")
    func deadlineBackstop() async {
        let guide = Device(site: site, clock: clock, arrivalClosed: false, marks: Self.everyoneMarked)
        let checkAt = dueCheck.addingTimeInterval(ParentLockerSync.backstopWait)
        #expect(guide.sync.nextWake == checkAt)
        clock.advance(by: checkAt.timeIntervalSince(clock.now) - 1)
        await guide.sync.runDue()
        #expect(site.requests.isEmpty)

        clock.advance(by: 1)
        await guide.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(guide.store.recordedSends.count == 1)
        #expect(site.mark(41002) == "703")

        // The day is sent now, so changes go live, and the check doesn't come back.
        guide.imports([Device.bea: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.importedWait)
        await guide.sync.runDue()
        #expect(site.saves.last?.entries.map(\.studentID) == ["41004"])
        #expect(guide.sync.deadlineDue == nil)
        #expect(guide.store.recordedSends.count == 1)
    }

    @Test("After the due time, the check waits for the last child to be marked; an assistant's phone never checks")
    func deadlineWaitsForEveryone() async {
        var partly = Self.everyoneMarked
        partly[Device.bea] = nil
        let guide = Device(site: site, clock: clock, arrivalClosed: false, marks: partly)
        let phone = Device(
            site: FakeParentLocker(), clock: clock, role: .assistant, arrivalClosed: false, marks: Self.everyoneMarked
        )
        #expect(phone.sync.nextWake == nil)
        clock.advance(by: dueCheck.addingTimeInterval(ParentLockerSync.backstopWait).timeIntervalSince(clock.now))
        await guide.sync.runDue()
        #expect(site.requests.isEmpty, "Bea isn't marked yet")
        #expect(guide.store.recordedSends.isEmpty)

        // Bea's mark syncs in at 9:30; a minute later the class goes.
        clock.advance(by: 29 * 60)
        guide.imports([Device.bea: Device.mark(.present)])
        #expect(guide.sync.nextWake == clock.now.addingTimeInterval(ParentLockerSync.backstopWait))
        clock.advance(by: ParentLockerSync.backstopWait)
        await guide.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(guide.store.recordedSends.count == 1)
    }

    @Test("The due-time check sends nothing once another device recorded the day")
    func deadlineAfterSendElsewhere() async {
        let guide = Device(site: site, clock: clock, arrivalClosed: false, marks: Self.everyoneMarked)
        guide.store.state.sentToParentLocker = true
        clock.advance(by: dueCheck.addingTimeInterval(ParentLockerSync.backstopWait).timeIntervalSince(clock.now))
        await guide.sync.runDue()
        #expect(site.requests.isEmpty)
        #expect(guide.store.recordedSends.isEmpty)
    }

    // MARK: - #5 The catch-up and the Mac's app switches

    @Test("The catch-up goes after 20 s when no import comes")
    func catchUpWithoutImport() async {
        let unsent = ParentLockerMemoryUnsentStore(ParentLockerUnsent(
            day: AppCalendar.dayID(Device.morning), children: [Device.wren], wholeClass: false
        ))
        let device = Device(site: site, clock: clock, unsent: unsent, importsExpected: true, sent: true)
        settled(device)
        device.store.state.marks[Device.wren] = Device.mark(.tardy)
        #expect(device.sync.nextWake == Device.morning.addingTimeInterval(ParentLockerSync.importWaitLimit))
        clock.advance(by: ParentLockerSync.importWaitLimit - 1)
        await device.sync.runDue()
        #expect(site.requests.isEmpty)

        clock.advance(by: 1)
        await device.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(site.mark(40001) == "702")
        #expect(unsent.load() == nil)
    }

    @Test("On the Mac a switch between apps isn't a return; a minute away is")
    func macReturnsNeedAnAbsence() async {
        let unsent = ParentLockerMemoryUnsentStore()
        let mac = Device(
            site: site, clock: clock, unsent: unsent, importsExpected: true, returnNeedsAbsence: true, sent: true
        )
        mac.sync.importFinished()
        settled(mac)
        // A send that couldn't go: owed until the next change, a return or Send Now.
        site.failuresLeft = 4
        await change(mac, [Device.wren: Device.mark(.tardy)])
        for wait in ParentLockerSync.retryWaits {
            clock.advance(by: wait)
            await mac.sync.runDue()
        }
        #expect(mac.sync.status.state == .gaveUp)

        // Away for 30 s: nothing changes, and nothing waits on an import.
        mac.sync.appResigned()
        clock.advance(by: 30)
        mac.sync.appBecameActive()
        #expect(!mac.sync.awaitingImport)
        #expect(mac.sync.localChanges.keys.contains(Device.wren))

        // Away for a minute: the catch-up waits for the import, then goes.
        mac.sync.appResigned()
        clock.advance(by: ParentLockerSync.returnAbsence)
        mac.sync.appBecameActive()
        #expect(mac.sync.awaitingImport)
        mac.sync.importFinished()
        await mac.sync.runDue()
        #expect(saves == ["save 5101"])
        #expect(site.mark(40001) == "702")
    }

    // MARK: - #10, #11 The Keychain

    @Test("A Keychain that can't be read leaves the sign-in as it was")
    func unreadableKeychainIsNotSignedOut() {
        let secrets = FakeParentLockerSecrets()
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        #expect(device.sync.isSignedIn)
        secrets.fail(with: .read(-25_308))
        device.sync.refreshSignIn()
        device.sync.appReturned()
        #expect(device.sync.isSignedIn)
        #expect(secrets.savedCookies.map(\.value) == ["good"], "this device's cookies stay")
        #expect(device.sync.status.state != .signedOut)
    }

    @Test("Sign Out that can't delete the password says so and stays signed in")
    func failedSignOut() throws {
        let secrets = FakeParentLockerSecrets()
        let device = Device(site: site, clock: clock, secrets: secrets, sent: true)
        secrets.fail(with: .write(-25_308))
        #expect(throws: ParentLockerKeychain.KeychainError.write(-25_308)) { try device.sync.signOut() }
        #expect(device.sync.isSignedIn)
        #expect(secrets.savedCookies.map(\.value) == ["good"])
        #expect(ParentLockerSignInSheet.signOutFailed == "Couldn't sign out of ParentLocker on this device. Try again.")

        secrets.fail(with: nil)
        try device.sync.signOut()
        #expect(!device.sync.isSignedIn)
        #expect(try secrets.credential(site: FakeParentLocker.host) == nil)
        #expect(secrets.savedCookies.isEmpty)
    }
}
