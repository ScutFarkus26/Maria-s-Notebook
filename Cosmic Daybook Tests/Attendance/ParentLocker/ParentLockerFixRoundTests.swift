import Foundation
import CoreData
import Testing
import UserNotifications
@testable import CosmicDaybook

/// The review of the afternoon fixes (plan "ParentLocker bug hunt afternoon
/// fixes", Phase 2), the engine's side: the guide's own marks made just
/// before another device closes arrival, the sign-in a person closed, a new
/// password saved elsewhere, a day ParentLocker isn't expecting reaching
/// every device, "Not matched" children, and a new day nobody announced.
/// Over the fake site, clock and keychain.
@Suite("ParentLocker fix round")
@MainActor
struct ParentLockerFixRoundTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private static let automatic = Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)

    private static let everyonePresent: [UUID: ParentLockerPlanner.DayMark] = Device.children.reduce(into: [:]) {
        $0[$1.id] = Device.mark(.present)
    }

    /// Everyone Present but Wren and Bea, who aren't in yet.
    private static var waitingForTwo: [UUID: ParentLockerPlanner.DayMark] {
        var marks = everyonePresent
        marks[Device.wren] = nil
        marks[Device.bea] = nil
        return marks
    }

    /// Everyone Present here and in ParentLocker.
    private func settled(_ device: Device) {
        for kid in site.kids.indices { site.kids[kid].markID = "701" }
        device.store.state.marks = Self.everyonePresent
    }

    // MARK: - H4: the guide's own marks made just before another device closes arrival

    /// 8:44:55: the assistant's phone closes arrival without having seen
    /// Wren come in on the Mac, and its send goes at 8:45:01. The close
    /// syncs in to `mac` at 8:44:57, which reads the class lists then,
    /// before that send lands. Returns once the Mac's minute has passed.
    private func phoneClosesBeforeTheMacCatchesUp(_ mac: Device) async {
        let phone = Device(site: site, clock: clock, role: .assistant, arrivalClosed: false, marks: Self.waitingForTwo)
        clock.advance(by: 5)
        phone.store.state.arrivalClosed = true
        phone.marks([Device.wren: Self.automatic, Device.bea: Self.automatic])
        phone.sync.closeArrivalSend(on: clock.now, after: 6)

        clock.advance(by: 2)
        mac.store.state.arrivalClosed = true
        mac.store.state.marks[Device.bea] = Self.automatic
        mac.sync.noteChanges([Device.bea, Device.wren], imported: true, on: clock.now)
        await mac.sync.baselineTask?.value
        #expect(mac.sync.lastSeen[Device.wren] != nil, "the Mac read the class lists before the phone's send")

        clock.advance(by: 4)
        await phone.sync.runDue()
        #expect(site.mark(40001) == "703", "the phone's send marks Wren absent")

        clock.advance(by: ParentLockerSync.backstopWait)
        await mac.sync.runDue()
    }

    @Test("A mark the guide makes at 8:44:50 reaches ParentLocker, though the Mac read the class lists first")
    func ownEarlyMarkWinsOverAStaleClose() async {
        clock.advance(by: 44 * 60 + 50)
        let mac = Device(site: site, clock: clock, arrivalClosed: false, marks: Self.waitingForTwo)
        mac.marks([Device.wren: Device.mark(.present)])
        await phoneClosesBeforeTheMacCatchesUp(mac)
        #expect(site.mark(40001) == "701", "Wren is here, as the Mac says")
        #expect(site.mark(41004) == "703", "Bea is still absent")
    }

    @Test("The guide's early mark is kept across a relaunch before arrival closes")
    func ownEarlyMarkSurvivesARelaunch() async {
        clock.advance(by: 44 * 60 + 50)
        let unsent = ParentLockerMemoryUnsentStore()
        var marks = Self.waitingForTwo
        do {
            let before = Device(site: site, clock: clock, unsent: unsent, arrivalClosed: false, marks: marks)
            before.marks([Device.wren: Device.mark(.present)])
            before.sync.stop()
        }
        #expect(unsent.load()?.children == [Device.wren], "kept with what's owed")
        marks[Device.wren] = Device.mark(.present)
        let mac = Device(site: site, clock: clock, unsent: unsent, arrivalClosed: false, marks: marks)
        await phoneClosesBeforeTheMacCatchesUp(mac)
        #expect(site.mark(40001) == "701")
    }

    // MARK: - A sign-in she closed

    @Test("With a refused password, a sign-in closed without signing in doesn't open again at every mark")
    func closedSignInStaysClosed() async {
        var marks = Self.everyonePresent
        marks[Device.bea] = Self.automatic
        let device = Device(
            site: site, clock: clock, secrets: FakeParentLockerSecrets(password: "wrong", cookie: nil), marks: marks
        )
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(device.sync.savedPasswordRefused)
        #expect(device.sync.awaitsSignIn, "the send she just asked for waits for her sign-in")

        device.sync.signInDismissed()
        for child in [Device.wren, Device.june] {
            device.marks([child: Device.mark(.tardy)])
            clock.advance(by: ParentLockerSync.localQuiet)
            await device.sync.runDue()
            #expect(!device.sync.awaitsSignIn, "a mark doesn't ask her again")
        }
        #expect(site.signIns == 1, "the refused password isn't tried again")
        #expect(device.unsent.load()?.wholeClass == true, "the class is still owed")

        await device.sync.sendNow(day: Device.morning)
        #expect(device.sync.awaitsSignIn, "a new Send Now asks again")
    }

    // MARK: - M9: a new password saved on another device

    @Test("A newer password saved on another device clears \"needs you\", and the app signs in by itself again")
    func newerPasswordClearsNeedsYou() async throws {
        let device = Device(site: site, clock: clock, secrets: FakeParentLockerSecrets(cookie: "expired"),
                            sent: true, marks: Self.everyonePresent)
        settled(device)
        site.signInNeedsYou = true
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        #expect(device.sync.signInNeedsYou)

        // The guide signs in on his iPad, accepting ParentLocker's new
        // terms there; the password comes to this device by iCloud Keychain.
        site.signInNeedsYou = false
        try device.secrets.savePassword(
            ParentLockerKeychain.Credential(email: "guide@school.test", password: site.password),
            site: FakeParentLocker.host
        )
        device.sync.appReturned()
        #expect(!device.sync.signInNeedsYou)
        #expect(!device.sync.needsSignIn)
        await device.sync.runDue()
        #expect(site.signIns == 2)
        #expect(site.mark(40001) == "702", "what waited went")
    }

    @Test("Without a new password, \"needs you\" stays")
    func samePasswordKeepsNeedsYou() async {
        let device = Device(site: site, clock: clock, secrets: FakeParentLockerSecrets(cookie: "expired"),
                            sent: true, marks: Self.everyonePresent)
        settled(device)
        site.signInNeedsYou = true
        device.marks([Device.wren: Device.mark(.tardy)])
        clock.advance(by: ParentLockerSync.localQuiet)
        await device.sync.runDue()
        device.sync.appReturned()
        #expect(device.sync.signInNeedsYou)
        #expect(site.signIns == 1)
    }

    // MARK: - M8: a day ParentLocker isn't expecting, on every device

    @Test("A day ParentLocker isn't expecting withdraws the other devices' reminders, and nothing reads it as sent")
    func notExpectedReachesEveryDevice() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let settings = AttendanceEmailLog.Settings(
            isEnabled: false, toAddresses: "", nameOrder: .firstLast, groupByLevel: false, sendMethod: .parentLocker
        )
        #expect(AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context))
        #expect(CoreDataTestHelpers.save(context))
        site.notExpectedToday = true

        // The guide's Mac finds ParentLocker isn't expecting today's attendance.
        let mac = Self.sync(on: context, site: site, clock: clock)
        let status = await mac.sendNow(day: Device.morning)
        #expect(status.state == .notExpected)

        // The assistant's phone (the same share, its own preferences) reads it.
        let phone = try FixRoundReminderDevice()
        await FrontDeskEmailReminder.reschedule(
            in: context, now: Device.morning, center: phone.center, defaults: phone.defaults
        )
        let today = AppCalendar.dayID(Device.morning)
        #expect(!phone.center.pending.keys.contains { $0.contains(today) }, "today's reminder is withdrawn")
        #expect(!phone.center.pending.isEmpty, "the days after still ring")

        // Nothing reads it as a send.
        #expect(AttendanceEmailLog.latestSend(on: Device.morning, in: context) == nil)
        #expect(AttendanceEmailLog.sends(on: Device.morning, in: context).isEmpty)
        #expect(AttendanceEmailLog.thirdPersonSummary(on: Device.morning, in: context) == nil)
        let day = ParentLockerCoreDataStore(
            context: context, sendRecorded: { _ in }, fixedRole: .assistant, lateDefaults: Self.lateDefaults()
        )
            .day(Device.morning, withChildren: false)
        #expect(!day.sentToParentLocker)
        #expect(!day.isAfter, "not a reason to go live")
        #expect(day.notExpected)

        // The phone's own line says so too, though its sync never asked.
        let phoneSync = Self.sync(on: context, site: site, clock: clock, role: .assistant)
        phoneSync.refreshStatus()
        #expect(phoneSync.status.message == "ParentLocker isn't expecting attendance today.")

        // A second run doesn't note it twice.
        await mac.sendNow(day: Device.morning)
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceEmailSend.self)).count == 1)
    }

    /// A sync on a real notebook context, as the apps make it, over the fake site.
    /// Settings of their own, so a day another test left closed on the
    /// simulator's shared settings can't read as closed here.
    private static func lateDefaults() -> UserDefaults {
        let name = "ParentLockerFixRoundTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    private static func sync(
        on context: NSManagedObjectContext, site: FakeParentLocker, clock: FakeParentLockerClock,
        role: CDClassroomMembership.ClassroomRole = .leadGuide
    ) -> ParentLockerSync {
        var dependencies = ParentLockerSync.Dependencies(store: ParentLockerCoreDataStore(
            context: context, sendRecorded: { _ in }, fixedRole: role, lateDefaults: lateDefaults()
        ))
        dependencies.secrets = FakeParentLockerSecrets()
        dependencies.makeTransport = { _, cookies, _ in FakeParentLockerTransport(site: site, cookies: cookies) }
        dependencies.clock = clock
        dependencies.policy = .live
        dependencies.unsent = ParentLockerMemoryUnsentStore()
        dependencies.refusals = ParentLockerMemoryRefusalStore()
        dependencies.background = FakeParentLockerBackground()
        dependencies.importsExpected = false
        let sync = ParentLockerSync(dependencies: dependencies)
        sync.refreshSignIn()
        return sync
    }

    // MARK: - "Not matched" children

    @Test("A child left out of ParentLocker doesn't keep the day from reading as everyone marked")
    func notMatchedChildIsNotWaitedFor() async {
        var marks = Self.everyonePresent
        marks[Device.bea] = nil
        let device = Device(site: site, clock: clock, arrivalClosed: false, marks: marks)
        device.store.state.children[4] = ParentLockerPlanner.Child(
            id: Device.bea, firstName: "Bea", lastName: "Marchetti", parentLockerID: ParentLockerPlanner.notMatchedID
        )
        #expect(device.store.day(Device.morning, withChildren: true).everyoneMarked)
        device.sync.refreshStatus()
        #expect(device.sync.status.state == .readyToSend, "the same as the unmarked names say")

        // A minute after the due time the guide's device sends the day.
        clock.advance(by: 3_600 + ParentLockerSync.backstopWait)
        await device.sync.runDue()
        #expect(site.mark(40001) == "701")
        #expect(device.store.recordedSends.count == 1)
    }

    // MARK: - M5: a new day nobody announced

    @Test("On a new day first seen by a run, a change synced in is measured by the mark before it")
    func newDayWithoutMidnightNotice() async {
        let phone = Device(site: site, clock: clock, sent: true, marks: Self.everyonePresent)
        // Tuesday 8:30. The phone slept through midnight: no notice came.
        clock.advance(by: 86_400 + 30 * 60)
        settled(phone)
        phone.sync.appReturned()
        await phone.sync.runDue()

        // Odile went home sick; the class lists can't be read as it arrives.
        site.failuresLeft = 1
        phone.imports([Device.odile: Device.mark(.absent, reason: "sick")], on: clock.now)
        await phone.sync.baselineTask?.value
        #expect(phone.sync.lastSeen.isEmpty, "the read failed")
        clock.advance(by: ParentLockerSync.importedWait)
        await phone.sync.runDue()
        #expect(site.mark(41002) == "703", "ParentLocker still held Odile's mark from before the change")
    }
}

/// Another device's reminders: its own preferences and notification center.
@MainActor
private final class FixRoundReminderDevice {
    let defaults: UserDefaults
    let center = FixRoundReminderCenter()
    private let suite = "ParentLockerFixRoundTests.\(UUID().uuidString)"

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: FrontDeskEmailReminder.enabledKey)
    }

    deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
}

/// A notification center that allows everything and remembers what's pending.
@MainActor
private final class FixRoundReminderCenter: ReminderCenter {
    private(set) var pending: [String: UNNotificationRequest] = [:]

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers { pending[id] = nil }
    }

    func add(_ request: UNNotificationRequest) async throws {
        pending[request.identifier] = request
    }
}
