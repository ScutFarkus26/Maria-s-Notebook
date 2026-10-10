import Foundation
import CoreData
import OSLog
import Testing
import UserNotifications
@testable import Daybook_Assistant

/// A class of one with the guide's email set up, for the reminder suites.
@MainActor
enum ReminderTestClass {
    static func withEmail() throws -> CoreDataStack {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Maya", "Stone", in: context)
        setEmail(on: true, in: context)
        return stack
    }

    static func setEmail(on: Bool, in context: NSManagedObjectContext) {
        let settings = AttendanceEmailLog.Settings(
            isEnabled: on, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
        )
        AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context)
        #expect(context.safeSave())
    }
}

// A rebuild of the arrival and front-desk reminders does only the work that
// changes something: it adds only what's new or changed (2026-10-10, before
// which every rebuild added all of them again) and leaves the same requests
// pending as adding every one did.
@Suite("Reminder rebuilds do only what changes something")
@MainActor
struct ReminderRebuildTests {

    private let logger = Logger.app(category: "test")

    /// An arrival-style request on 2026-10-`day` at `hour`:`minute`.
    private func request(
        _ id: String, title: String = "Time to close arrival", day: Int, hour: Int = 8, minute: Int = 15
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Close arrival to mark anyone not here yet absent."
        content.sound = .default
        let time = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// The rebuild before 2026-10-10: remove what's no longer wanted, then
    /// add every wanted request again.
    private func replaceAddingAll(_ requests: [UNNotificationRequest], center: FakeReminderCenter) async {
        let wanted = Set(requests.map(\.identifier))
        let stale = await center.pendingRequests().map(\.identifier)
            .filter { $0.hasPrefix("arrival-") && !wanted.contains($0) }
        center.removePendingRequests(withIdentifiers: stale)
        for request in requests { try? await center.add(request) }
    }

    /// Each pending request's words and time, by identifier.
    private func snapshot(_ center: FakeReminderCenter) -> [String: String] {
        center.pending.mapValues { request in
            let time = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents
            let when = [time?.year, time?.month, time?.day, time?.hour, time?.minute].map { "\($0 ?? -1)" }
            return request.content.title + "|" + request.content.body + "|" + when.joined(separator: "-")
        }
    }

    // MARK: - Compare first

    @Test("Comparing first leaves the same pending reminders as adding every one again")
    func compareFirstMatchesAddingAll() async {
        let pending = [
            request("arrival-12", day: 12),
            request("arrival-13", day: 13),
            request("arrival-14", day: 14),
            request("arrival-15", title: "Old words", day: 15),
            request("frontdesk-12-due", title: "Front desk email is late", day: 12, hour: 9, minute: 0)
        ]
        // 13 unchanged, 14 moved, 15 reworded, 16 new; 12 no longer wanted,
        // and the front-desk one isn't this kind's to touch.
        let wanted = [
            request("arrival-13", day: 13),
            request("arrival-14", day: 14, minute: 30),
            request("arrival-15", day: 15),
            request("arrival-16", day: 16)
        ]
        let before = FakeReminderCenter()
        before.seed(pending)
        await replaceAddingAll(wanted, center: before)
        let after = FakeReminderCenter()
        after.seed(pending)

        await ReminderRuns.replace(where: { $0.hasPrefix("arrival-") }, with: wanted, center: after, logger: logger)

        #expect(snapshot(after) == snapshot(before))
        #expect(before.adds == 4)
        #expect(after.adds == 3)
    }

    @Test("A rebuild with nothing changed adds nothing")
    func nothingChangedAddsNothing() async {
        let wanted = [request("arrival-13", day: 13), request("arrival-14", day: 14)]
        let center = FakeReminderCenter()
        center.seed(wanted)
        let before = snapshot(center)

        await ReminderRuns.replace(where: { $0.hasPrefix("arrival-") }, with: wanted, center: center, logger: logger)

        #expect(center.adds == 0)
        #expect(snapshot(center) == before)
    }

    @Test("Rebuilding the arrival and front-desk reminders with nothing changed adds none of them again")
    func secondRebuildAddsNothing() async throws {
        let stack = try ReminderTestClass.withEmail()
        let context = stack.viewContext
        let center = FakeReminderCenter()
        await ArrivalReminder.reschedule(in: context, center: center)
        await FrontDeskEmailReminder.reschedule(in: context, center: center)
        let first = center.adds
        let scheduled = snapshot(center)
        #expect(first > 0)
        #expect(first == center.ids("arrival-").count + center.ids("frontdesk-").count)

        await ArrivalReminder.reschedule(in: context, center: center)
        await FrontDeskEmailReminder.reschedule(in: context, center: center)

        #expect(center.adds == first)
        #expect(snapshot(center) == scheduled)
    }

    @Test("Once the guide's email is off, the next rebuild takes every front-desk reminder off")
    func staleRequestsStillGo() async throws {
        let stack = try ReminderTestClass.withEmail()
        let context = stack.viewContext
        let center = FakeReminderCenter()
        await FrontDeskEmailReminder.reschedule(in: context, center: center)
        #expect(!center.ids("frontdesk-").isEmpty)

        ReminderTestClass.setEmail(on: false, in: context)
        await FrontDeskEmailReminder.reschedule(in: context, center: center)

        #expect(center.ids("frontdesk-").isEmpty)
    }

    // MARK: - One rebuild per change

    @Test("The screen asks, then hands the rebuild to the upkeep's settle instead of rebuilding itself")
    func followerGoesThroughTheSettle() async throws {
        let stack = try ReminderTestClass.withEmail()
        let context = stack.viewContext
        let center = FakeReminderCenter()
        var settles = 0

        await ArrivalReminderFollower.follow(
            hasClass: true, in: context, setupDone: true, isSample: false, center: center
        ) { settles += 1 }
        #expect(settles == 1)
        #expect(center.adds == 0)
        #expect(center.pendingReads == 0)

        // No class on screen: nothing, as before.
        await ArrivalReminderFollower.follow(
            hasClass: false, in: context, setupDone: true, isSample: false, center: center
        ) { settles += 1 }
        #expect(settles == 1)
    }

    @Test("Rebuilds of one class queued behind each other run once, and every caller waits for it")
    func queuedRebuildsRunOnce() async throws {
        let stack = try ReminderTestClass.withEmail()
        let context = stack.viewContext
        let reference = FakeReminderCenter()
        await ArrivalReminder.reschedule(in: context, center: reference)
        let wanted = reference.ids("arrival-")
        #expect(!wanted.isEmpty)
        let center = FakeReminderCenter()

        let callers = (0..<5).map { _ in
            Task {
                await ArrivalReminder.reschedule(in: context, center: center)
                return center.ids("arrival-")
            }
        }
        for caller in callers {
            #expect(await caller.value == wanted)
        }
        // One read of what's pending: only the newest rebuild did the work.
        #expect(center.pendingReads == 1)
    }

    @Test("A rebuild already going finishes, and the newer one queued behind it takes off what it put back")
    func olderRebuildNeverWins() async throws {
        let stack = try ReminderTestClass.withEmail()
        let context = stack.viewContext
        let center = HeldReminderCenter()

        let older = Task { await FrontDeskEmailReminder.reschedule(in: context, center: center) }
        #expect(await eventually { center.isHolding })
        // The guide turns the email off while the older rebuild is mid-way.
        ReminderTestClass.setEmail(on: false, in: context)
        let newer = Task { await FrontDeskEmailReminder.reschedule(in: context, center: center) }
        center.open()
        await older.value
        await newer.value

        #expect(center.inner.adds > 0)
        #expect(center.inner.ids("frontdesk-").isEmpty)
    }

    @Test("Rebuilds of different classes never take each other's place")
    func otherContextsAreNotSkipped() async throws {
        let one = try ReminderTestClass.withEmail()
        let two = try ReminderTestClass.withEmail()
        let centerOne = FakeReminderCenter()
        let centerTwo = FakeReminderCenter()

        let first = Task { await ArrivalReminder.reschedule(in: one.viewContext, center: centerOne) }
        let second = Task { await ArrivalReminder.reschedule(in: two.viewContext, center: centerTwo) }
        await first.value
        await second.value

        #expect(!centerOne.ids("arrival-").isEmpty)
        #expect(centerOne.ids("arrival-") == centerTwo.ids("arrival-"))
    }

    /// Waits until `condition` holds, for up to 10 s.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

/// A center whose first read of the pending requests waits for `open()`, so
/// a test can hold a rebuild mid-way, its requests already built.
@MainActor
final class HeldReminderCenter: ReminderCenter {
    let inner = FakeReminderCenter()
    private(set) var isHolding = false
    private var isOpen = false
    private var held: CheckedContinuation<Void, Never>?

    func open() {
        isOpen = true
        held?.resume()
        held = nil
    }

    func authorizationStatus() async -> UNAuthorizationStatus { await inner.authorizationStatus() }

    func requestAuthorization() async -> Bool { await inner.requestAuthorization() }

    func pendingRequests() async -> [UNNotificationRequest] {
        if !isOpen {
            isHolding = true
            await withCheckedContinuation { held = $0 }
        }
        return await inner.pendingRequests()
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        inner.removePendingRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await inner.add(request)
    }
}
