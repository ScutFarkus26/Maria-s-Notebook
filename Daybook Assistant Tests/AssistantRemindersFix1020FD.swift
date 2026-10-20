import Foundation
import CoreData
import Testing
import UserNotifications
@testable import Daybook_Assistant

// The reminders after the 2026-10-20 bug hunt (plan "Daybook Assistant bug
// hunt 2026-10-20 fixes", agent FD): leaving the class or the sample leaves
// no reminders behind (#20, #25), a pickup set in the sample can ring (#23),
// and the reminders read the guide's days off from the classroom share only.
@Suite("Assistant fixes 2026-10-20: reminders")
@MainActor
struct AssistantRemindersFix1020FD {

    /// "8:42 AM" on `day`.
    private static func time(_ hour: Int, _ minute: Int, on day: Date) -> Date {
        day.addingTimeInterval(Double(hour * 3_600 + minute * 60))
    }

    /// Waits until `condition` holds, for up to 5 s.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - #20: leaving the class

    @Test("Without her membership, the upkeep's rebuild puts no reminder back (#20)")
    func noMembershipNoReminders() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        AssistantTestSupport.student("Maya", "Stone", in: context)
        ReminderTestClass.setEmail(on: true, in: context)
        let center = FakeReminderCenter()

        await EarlyPickupReminderUpkeep.refresh(in: context, isSample: false, center: center)

        #expect(center.ids("arrival-").isEmpty)
        #expect(center.ids("frontdesk-").isEmpty)
    }

    @Test("A rebuild already going when she leaves puts nothing back once she's gone (#20)", .timeLimit(.minutes(1)))
    func rebuildDuringLeave() async throws {
        let stack = try ReminderTestClass.withEmail()
        let context = stack.viewContext
        try pickupTomorrow(in: context)
        let membership = try #require(context.safeFetchFirst(CDClassroomMembership.ownRowsRequest()))
        let center = FirstReadHeldCenter()

        let rebuild = Task { await EarlyPickupReminderUpkeep.refresh(in: context, isSample: false, center: center) }
        #expect(await eventually { center.isHolding }, "the pickups' rebuild is mid-way")

        // Leave: the membership row goes, then every reminder comes off.
        context.delete(membership)
        #expect(context.safeSave())
        let leave = Task {
            await ArrivalReminder.cancelAll(center: center)
            await FrontDeskEmailReminder.cancelAll(center: center)
            await EarlyPickupReminder.cancelAll(center: center)
        }
        #expect(await eventually { center.reads >= 3 })
        center.open()
        await rebuild.value
        await leave.value

        #expect(center.inner.ids("arrival-").isEmpty)
        #expect(center.inner.ids("frontdesk-").isEmpty)
        #expect(center.inner.ids("pickup-").isEmpty)
    }

    // MARK: - #23, #25: the sample's pickup reminders

    @Test("A pickup set in the Sample Class asks for notifications, so it can ring (#23)")
    func samplePickupAsks() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        try pickupTomorrow(in: context)
        let center = FakeReminderCenter()
        center.status = .notDetermined

        await ArrivalReminderFollower.askPermission(in: context, setupDone: false, isSample: true, center: center)

        #expect(center.authorizationRequests == 1)
    }

    @Test("Leaving the sample while its pickups are being brought up to date leaves none behind (#25)",
          .timeLimit(.minutes(1)))
    func leavingTheSampleMidRebuild() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        try pickupTomorrow(in: context)
        let center = FirstReadHeldCenter()

        let run = Task {
            await EarlyPickupReminder.reschedule(in: context, asksPermission: false, isSample: true, center: center)
        }
        #expect(await eventually { center.isHolding })
        let leave = Task { await EarlyPickupReminder.cancelSample(center: center) }
        try await Task.sleep(for: .milliseconds(200))
        center.open()
        await run.value
        await leave.value

        #expect(center.inner.ids("pickup-sample-").isEmpty)
    }

    // MARK: - Days off from the classroom share only

    @Test("The reminders skip the guide's days off, not her own notebook's")
    func daysOffFromTheShareOnly() async throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let privateStore = try store(CoreDataStack.privateConfiguration, in: context)
        let monday = try AssistantTestSupport.day("2031-01-06")
        let tuesday = try AssistantTestSupport.day("2031-01-07")
        let wednesday = try AssistantTestSupport.day("2031-01-08")

        let settings = CDAttendanceEmailSettings(context: context)
        context.assign(settings, to: shared)
        settings.isEnabled = true
        settings.toAddresses = "office@school.org"
        settings.deadlineMinutes = 540
        // Her own notebook, on the same Apple Account, has Tuesday off.
        let own = CDNonSchoolDay(context: context)
        context.assign(own, to: privateStore)
        own.date = tuesday
        // The guide has Wednesday off.
        let guides = CDNonSchoolDay(context: context)
        context.assign(guides, to: shared)
        guides.date = wednesday
        #expect(context.safeSave())

        let center = FakeReminderCenter()
        let now = Self.time(7, 0, on: monday)
        await ArrivalReminder.reschedule(in: context, now: now, center: center)
        await FrontDeskEmailReminder.reschedule(in: context, now: now, center: center)

        #expect(center.ids("arrival-").contains("arrival-" + AppCalendar.dayID(tuesday)))
        #expect(!center.ids("arrival-").contains("arrival-" + AppCalendar.dayID(wednesday)))
        #expect(center.ids("frontdesk-").contains("frontdesk-" + AppCalendar.dayID(tuesday) + "-due"))
        #expect(!center.ids("frontdesk-").contains("frontdesk-" + AppCalendar.dayID(wednesday) + "-due"))
    }

    // MARK: - Helpers

    /// Maya, leaving at 1:30 tomorrow.
    private func pickupTomorrow(in context: NSManagedObjectContext) throws {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.ensureRecord(for: maya, on: tomorrow))
        store.updateLeavesAt(record, to: tomorrow.addingTimeInterval(13.5 * 3_600))
        #expect(context.safeSave())
        #expect(!EarlyPickupReminder.pendingPickups(in: context).isEmpty)
    }

    /// Private and shared SQLite stores in a temporary folder, as on a phone.
    private func splitContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            _ = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration, at: dir.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func store(_ configuration: String, in context: NSManagedObjectContext) throws -> NSPersistentStore {
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        return try #require(stores.first { $0.configurationName == configuration })
    }
}

/// A center whose first read of the pending requests waits for `open()`,
/// so a test can hold one rebuild mid-way; every later read goes through
/// at once, and is counted.
@MainActor
private final class FirstReadHeldCenter: ReminderCenter {
    let inner = FakeReminderCenter()
    private(set) var isHolding = false
    private(set) var reads = 0
    private var hasHeld = false
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
        reads += 1
        if !hasHeld, !isOpen {
            hasHeld = true
            isHolding = true
            await withCheckedContinuation { held = $0 }
        }
        return await inner.pendingRequests()
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        inner.removePendingRequests(withIdentifiers: identifiers)
    }

    func add(_ request: UNNotificationRequest) async throws { try await inner.add(request) }
}
