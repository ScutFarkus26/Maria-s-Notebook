import Foundation
import CoreData
import UserNotifications
import OSLog

/// Rebuilds of one kind of reminder, one at a time and each to the end.
///
/// The attendance screen starts a rebuild from a task that SwiftUI cancels on
/// a tab switch or a newer change. A rebuild that stopped there, after
/// removing the old reminders and before adding the new ones, left none:
/// no reminder the next morning. So a rebuild runs in a task of its own that
/// a cancelled caller doesn't stop, after any rebuild already going, so an
/// older one can never put back what a newer one removed.
///
/// A rebuild still waiting for its turn when a newer one of the same context
/// is asked for is skipped, and its caller waits for the newer one instead:
/// that one reads the store later and makes the requests exactly what they
/// should be, whatever was pending. Marking 22 children used to queue about
/// 22 rebuilds and run every one.
@MainActor
final class ReminderRuns {
    private var last: Task<Bool, Never>?
    /// Numbers each rebuild asked for.
    private var asked = 0
    /// The newest rebuild asked for each context, by identity, and its task.
    private var newest: [ObjectIdentifier: (number: Int, task: Task<Bool, Never>)] = [:]

    /// Runs `work` after the rebuild before it, and waits for it, or for the
    /// newer rebuild of `context` that took its place. One with no context
    /// (taking them all off) is never skipped and never takes another's place.
    func run(for context: NSManagedObjectContext? = nil, _ work: @escaping @MainActor () async -> Void) async {
        asked &+= 1
        let number = asked
        let key = context.map(ObjectIdentifier.init)
        let previous = last
        let task = Task { () -> Bool in
            _ = await previous?.value
            // A newer one of this context is queued behind: it does the work.
            if let key, newest[key]?.number != number { return false }
            await work()
            return true
        }
        last = task
        guard let key else {
            _ = await task.value
            return
        }
        newest[key] = (number, task)
        var waitedFor = number
        var ran = await task.value
        while !ran, let newer = newest[key], newer.number != waitedFor {
            waitedFor = newer.number
            ran = await newer.task.value
        }
        if newest[key]?.number == waitedFor { newest[key] = nil }
    }

    /// Makes the pending requests that `isOurs` picks out exactly `requests`,
    /// built beforehand: ones no longer wanted are removed, and ones new or
    /// changed are added, which replaces a pending one with the same
    /// identifier. One pending and wanted unchanged is left alone, as the
    /// pickup reminders do (`EarlyPickupReminder.changes`): a rebuild with
    /// nothing new used to add every one again, about 30 between the
    /// Assistant's arrival and front-desk reminders, on every import.
    static func replace(
        where isOurs: (String) -> Bool,
        with requests: [UNNotificationRequest],
        center: any ReminderCenter,
        logger: Logger
    ) async {
        let pending = await center.pendingRequests().filter { isOurs($0.identifier) }
        let wanted = Set(requests.map(\.identifier))
        let stale = pending.map(\.identifier).filter { !wanted.contains($0) }
        if !stale.isEmpty { center.removePendingRequests(withIdentifiers: stale) }
        let pendingByID = Dictionary(
            pending.compactMap { request in Reminder(request).map { (request.identifier, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        for request in requests {
            if let reminder = Reminder(request), pendingByID[request.identifier] == reminder { continue }
            do {
                try await center.add(request)
            } catch {
                let id = request.identifier
                let reason = error.localizedDescription
                logger.error("Scheduling \(id, privacy: .public) failed: \(reason, privacy: .public)")
            }
        }
    }

    /// One request as the comparison reads it, wanted or pending: its words
    /// and when it fires, as the calendar trigger holds it (to the minute).
    /// The builders vary nothing else; the sound is the default on every
    /// one. Nil for any other trigger, which is always added again.
    private struct Reminder: Equatable {
        let title: String
        let body: String
        let fireTime: [Int?]
        let repeats: Bool

        init?(_ request: UNNotificationRequest) {
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return nil }
            let time = trigger.dateComponents
            title = request.content.title
            body = request.content.body
            fireTime = [time.year, time.month, time.day, time.hour, time.minute]
            repeats = trigger.repeats
        }
    }
}

