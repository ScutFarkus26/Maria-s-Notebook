import Foundation
import CoreData
import Testing
import UserNotifications
@testable import Daybook_Assistant

/// A notification center that allows everything and remembers what was
/// scheduled: the simulator's own has no permission under tests.
@MainActor
final class FakeReminderCenter: ReminderCenter {
    var status: UNAuthorizationStatus = .authorized
    private(set) var pending: [String: UNNotificationRequest] = [:]
    private(set) var authorizationRequests = 0

    func ids(_ prefix: String) -> Set<String> {
        Set(pending.keys.filter { $0.hasPrefix(prefix) })
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return false
    }

    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers { pending[id] = nil }
    }

    func add(_ request: UNNotificationRequest) async throws {
        pending[request.identifier] = request
    }
}

// The arrival, front-desk and pickup reminders follow every change, not only
// the ones the attendance screen sees, and a run cut short never leaves her
// with none.
@Suite("Reminders follow every change")
@MainActor
struct ReminderRescheduleTests {

    private let today = Calendar.current.startOfDay(for: Date())

    /// A class of one with the guide's email set up.
    private func classWithEmail() throws -> (CoreDataStack, CDStudent) {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let settings = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
        )
        AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: context)
        #expect(context.safeSave())
        return (stack, maya)
    }

    @Test("An import or a trip to the background brings the arrival and front-desk reminders up to date too")
    func upkeepReschedulesAll() async throws {
        let (stack, _) = try classWithEmail()
        let center = FakeReminderCenter()

        await EarlyPickupReminderUpkeep.refresh(in: stack.viewContext, isSample: false, center: center)

        #expect(!center.ids("arrival-").isEmpty)
        #expect(!center.ids("frontdesk-").isEmpty)
    }

    @Test("The sample class's upkeep leaves the real class's arrival and front-desk reminders alone")
    func upkeepInTheSampleSchedulesNoArrival() async throws {
        let (stack, _) = try classWithEmail()
        let center = FakeReminderCenter()

        await EarlyPickupReminderUpkeep.refresh(in: stack.viewContext, isSample: true, center: center)

        #expect(center.ids("arrival-").isEmpty)
        #expect(center.ids("frontdesk-").isEmpty)
    }

    @Test("Before the class's children have downloaded, the upkeep schedules no arrival reminder")
    func upkeepWaitsForAClass() async throws {
        let stack = try AssistantTestSupport.makeStack()
        let center = FakeReminderCenter()

        await EarlyPickupReminderUpkeep.refresh(in: stack.viewContext, isSample: false, center: center)

        #expect(center.ids("arrival-").isEmpty)
    }

    @Test("Before setup is done, a pickup doesn't ask for notifications over it")
    func noPermissionPromptDuringSetup() async throws {
        let (stack, maya) = try classWithEmail()
        let context = stack.viewContext
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let store = CDAttendanceStore(context: context, role: .assistant)
        let record = try #require(try store.ensureRecord(for: maya, on: tomorrow))
        store.updateLeavesAt(record, to: tomorrow.addingTimeInterval(13.5 * 3600))
        #expect(context.safeSave())
        #expect(!EarlyPickupReminder.pendingPickups(in: context).isEmpty)
        let center = FakeReminderCenter()
        center.status = .notDetermined

        await ArrivalReminderFollower.refresh(
            hasClass: true, in: context, setupDone: false, isSample: false, center: center
        )
        #expect(center.authorizationRequests == 0)

        // Once setup is done, the screen asks.
        await ArrivalReminderFollower.refresh(
            hasClass: true, in: context, setupDone: true, isSample: false, center: center
        )
        #expect(center.authorizationRequests > 0)
    }

    @Test("A run cut short by a tab switch still puts every arrival reminder back")
    func cancelledArrivalRunFinishes() async throws {
        let (stack, _) = try classWithEmail()
        let context = stack.viewContext
        let center = FakeReminderCenter()
        await ArrivalReminder.reschedule(in: context, center: center)
        let wanted = center.ids("arrival-")
        #expect(!wanted.isEmpty)

        let run = Task { await ArrivalReminder.reschedule(in: context, center: center) }
        run.cancel()
        await run.value

        #expect(center.ids("arrival-") == wanted)
    }

    @Test("A run cut short by a tab switch still puts every front-desk reminder back")
    func cancelledFrontDeskRunFinishes() async throws {
        let (stack, _) = try classWithEmail()
        let context = stack.viewContext
        let center = FakeReminderCenter()
        await FrontDeskEmailReminder.reschedule(in: context, center: center)
        let wanted = center.ids("frontdesk-")
        #expect(!wanted.isEmpty)

        let run = Task { await FrontDeskEmailReminder.reschedule(in: context, center: center) }
        run.cancel()
        await run.value

        #expect(center.ids("frontdesk-") == wanted)
    }
}
