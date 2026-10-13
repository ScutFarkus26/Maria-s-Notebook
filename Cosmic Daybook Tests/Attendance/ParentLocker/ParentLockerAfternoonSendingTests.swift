import Foundation
import CoreData
import Testing
import UserNotifications
@testable import CosmicDaybook

/// What the engine sends and says, as the afternoon bug hunt of 2026-10-13
/// found it (report "ParentLocker bug hunt 2026-10-13 afternoon", M2, M3,
/// M4, M6, M8, L6): the line once everyone's marked, a problem kept for its
/// day, a send with children unmarked, the office's notes, a day ParentLocker
/// isn't expecting, and a send asked for before signing in. Over the fake
/// site, clock and keychain.
@Suite("ParentLocker afternoon fixes: sending")
@MainActor
struct ParentLockerAfternoonSendingTests {

    typealias Device = ParentLockerTestDevice

    let site = FakeParentLocker()
    let clock = FakeParentLockerClock(Device.morning)

    private var saves: [String] { site.requests.filter { $0.hasPrefix("save") } }

    private static let automatic = Device.mark(.absent, reason: AttendanceDeduplication.automaticAbsenceRaw)

    private static let everyonePresent: [UUID: ParentLockerPlanner.DayMark] = Device.children.reduce(into: [:]) {
        $0[$1.id] = Device.mark(.present)
    }

    private static var allButBea: [UUID: ParentLockerPlanner.DayMark] {
        var marks = everyonePresent
        marks[Device.bea] = nil
        return marks
    }

    // MARK: - M2 Everyone's marked, and no Close Arrival to tap

    @Test("With everyone marked before arrival closes, the line says to send it, not to close arrival")
    func everyoneMarkedLine() {
        let device = Device(site: site, clock: clock, arrivalClosed: false, marks: Self.allButBea)
        #expect(device.sync.status.state == .waitingForArrival)
        device.marks([Device.bea: Device.mark(.tardy)])
        #expect(device.sync.status.state == .readyToSend)
        #expect(device.sync.status.message == "Everyone's marked. Send it to ParentLocker.")

        let fresh = Device(site: FakeParentLocker(), clock: clock, arrivalClosed: false, marks: Self.everyonePresent)
        #expect(fresh.sync.status.state == .readyToSend)
    }

    @Test("The late reminder doesn't say to close arrival, which may not be there to tap")
    func lateReminderWording() {
        let settings = AttendanceEmailLog.Settings(
            isEnabled: false, toAddresses: "", nameOrder: .firstLast, groupByLevel: false, sendMethod: .parentLocker
        )
        let kinds = FrontDeskEmailReminder.kinds(for: settings, leadMinutes: 10)
        let dueAt = FrontDeskEmailReminder.timeString(settings.deadlineMinutes)
        #expect(kinds.last?.body == "It was due at \(dueAt). Open attendance and send it to ParentLocker.")
        #expect(kinds.allSatisfy { !$0.body.localizedCaseInsensitiveContains("close arrival") })
    }

    // MARK: - M3 A problem on an idle run

    @Test("A run that finds none of the class keeps that problem first for the day, and not the next")
    func noneFoundProblemForTheDay() async {
        site.kids = [
            FakeParentLocker.Kid(studentID: 49_001, first: "Zed", last: "Other", course: FakeParentLocker.middle)
        ]
        let device = Device(site: site, clock: clock, marks: Self.everyonePresent)
        let status = await device.sync.sendNow(day: Device.morning)
        let noneFound = "None of the class's children were found in ParentLocker. "
            + "Check that you signed in with your school account."
        #expect(status.problems.first == noneFound)
        #expect(device.sync.status.problems.first == noneFound)
        #expect(device.sync.status.isTrouble)
        device.sync.appReturned()
        #expect(device.sync.status.problems.first == noneFound, "still today's")

        clock.advance(by: 86_400)
        device.sync.refreshStatus()
        #expect(device.sync.status.problems.isEmpty, "yesterday's problem isn't today's")
    }

    // MARK: - M4 A send with children unmarked

    @Test("A send with a child unmarked sends the rest, names who's left, and doesn't record the day")
    func unmarkedChildNotRecorded() async throws {
        let device = Device(site: site, clock: clock, marks: Self.allButBea)
        #expect(device.sync.unmarkedNames(on: Device.morning) == ["Bea M"])
        let report = try await device.sync.send(day: Device.morning, preview: false).get()
        #expect(report.savedCount == 4)
        #expect(report.unmarked == ["Bea M"])
        #expect(report.text.contains("Bea M"))
        #expect(device.store.recordedSends.isEmpty, "the day isn't done while Bea is unmarked")
        await device.sync.sendNow(day: Device.morning)
        #expect(device.store.recordedSends.isEmpty)

        device.store.state.marks[Device.bea] = Device.mark(.present)
        #expect(device.sync.unmarkedNames(on: Device.morning).isEmpty)
        await device.sync.sendNow(day: Device.morning)
        #expect(device.store.recordedSends.count == 1)
    }

    @Test("A child the guide left out of ParentLocker doesn't count as unmarked")
    func notMatchedIsNotUnmarked() async {
        let device = Device(site: site, clock: clock, marks: Self.allButBea)
        device.store.state.children[4] = ParentLockerPlanner.Child(
            id: Device.bea, firstName: "Bea", lastName: "Marchetti", parentLockerID: ParentLockerPlanner.notMatchedID
        )
        #expect(device.sync.unmarkedNames(on: Device.morning).isEmpty)
        await device.sync.sendNow(day: Device.morning)
        #expect(device.store.recordedSends.count == 1)
    }

    // MARK: - M6 The office's notes

    @Test("Close Arrival's absence keeps the office's note, and still clears the app's own")
    func automaticAbsenceKeepsOfficeNote() async {
        var marks = Self.everyonePresent
        marks[Device.bea] = Self.automatic
        marks[Device.odile] = Self.automatic
        let device = Device(site: site, clock: clock, marks: marks)
        site.kids[4].comment = "Mom called: dentist at 10"
        site.kids[3].comment = "Sick"
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        clock.advance(by: 6)
        await device.sync.runDue()
        #expect(site.mark(41004) == "703")
        #expect(site.kids[4].comment == "Mom called: dentist at 10")
        #expect(site.kids[3].comment.isEmpty, "the app's own word from an earlier mark goes")
    }

    // MARK: - M8 A day ParentLocker isn't expecting

    @Test("A day ParentLocker isn't expecting says so plainly, records nothing, and withdraws the reminder")
    func notExpectedDay() async throws {
        site.notExpectedToday = true
        let device = Device(site: site, clock: clock, marks: Self.everyonePresent)
        let status = await device.sync.sendNow(day: Device.morning)
        #expect(status.state == .notExpected)
        #expect(device.sync.status.message == "ParentLocker isn't expecting attendance today.")
        #expect(device.sync.status.problems.isEmpty, "no \"none found\", no \"aren't matched\"")
        #expect(!device.sync.status.isTrouble)
        #expect(device.store.recordedSends.isEmpty)
        #expect(device.store.notExpectedDays.map(AppCalendar.dayID) == [AppCalendar.dayID(Device.morning)])
        let report = try await device.sync.send(day: Device.morning, preview: true).get()
        #expect(report.notExpected)
        #expect(report.problems.isEmpty)
        #expect(report.text.contains("isn't expecting attendance"))
    }

    @Test("The reminder leaves out a day ParentLocker isn't expecting, and keeps the next")
    func reminderSkipsNotExpectedDay() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let settings = AttendanceEmailLog.Settings(
            isEnabled: false, toAddresses: "", nameOrder: .firstLast, groupByLevel: false, sendMethod: .parentLocker
        )
        #expect(AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context))
        #expect(CoreDataTestHelpers.save(context))
        let suite = "ParentLockerAfternoonSendingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: FrontDeskEmailReminder.enabledKey)
        let center = AfternoonReminderCenter()
        let now = Device.morning.addingTimeInterval(-3_600)
        let today = AppCalendar.dayID(now)

        await FrontDeskEmailReminder.reschedule(in: context, now: now, center: center, defaults: defaults)
        #expect(center.pending.keys.contains { $0.contains(today) })

        AttendanceEmailLog.recordNotExpected(on: now, role: .leadGuide, in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(AttendanceEmailLog.isNotExpected(on: now, in: context))
        await FrontDeskEmailReminder.reschedule(in: context, now: now, center: center, defaults: defaults)
        #expect(!center.pending.keys.contains { $0.contains(today) })
        #expect(!center.pending.isEmpty, "the days after still ring")
    }

    // MARK: - L6 Send to ParentLocker before signing in

    @Test("Send Now before signing in waits for the sign-in, then goes without a second tap")
    func sendNowWaitsForSignIn() async throws {
        let device = Device(
            site: site, clock: clock, secrets: FakeParentLockerSecrets(password: nil, cookie: nil),
            marks: Self.everyonePresent
        )
        let status = await device.sync.sendNow(day: Device.morning)
        #expect(status.message == "Sign in to ParentLocker to send.")
        #expect(device.sync.awaitsSignIn)
        #expect(site.requests.isEmpty)

        try await device.sync.signIn(email: "guide@school.test", password: site.password)
        #expect(!device.sync.awaitsSignIn)
        await device.sync.runDue()
        #expect(saves == ["save 5101", "save 5102"])
        #expect(device.store.recordedSends.count == 1)
    }

    @Test("Before signing in, another day's Send Now just says to sign in, and a closed sheet drops today's")
    func pastDayAndDismissal() async throws {
        let device = Device(
            site: site, clock: clock, secrets: FakeParentLockerSecrets(password: nil, cookie: nil),
            marks: Self.everyonePresent
        )
        let friday = Device.morning.addingTimeInterval(-3 * 86_400)
        let past = await device.sync.sendNow(day: friday)
        #expect(past.message == "Sign in to ParentLocker to send.")
        #expect(!device.sync.awaitsSignIn)

        await device.sync.sendNow(day: Device.morning)
        #expect(device.sync.awaitsSignIn)
        device.sync.signInDismissed()
        #expect(!device.sync.awaitsSignIn)

        try await device.sync.signIn(email: "guide@school.test", password: site.password)
        await device.sync.runDue()
        #expect(site.requests == ["courses"], "only the sign-in's own check: nothing was sent")
    }

    @Test("Close Arrival & Send before signing in waits for a sign-in; a closed sheet stops asking but keeps it owed")
    func closeArrivalAwaitsSignIn() {
        let device = Device(
            site: site, clock: clock, secrets: FakeParentLockerSecrets(password: nil, cookie: nil),
            marks: Self.everyonePresent
        )
        device.sync.closeArrivalSend(on: Device.morning, after: 6)
        #expect(device.sync.awaitsSignIn)
        device.sync.signInDismissed()
        #expect(!device.sync.awaitsSignIn)
        #expect(device.unsent.load()?.wholeClass == true, "a later sign-in, or the guide's backstop, still sends it")
    }
}

/// A notification center that allows everything and remembers what's pending.
@MainActor
private final class AfternoonReminderCenter: ReminderCenter {
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
