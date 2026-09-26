// TodayRetentionCleanup.swift
// Deletes Today's per-day rows once they are more than 30 days old.

import CoreData
import Foundation
import OSLog

/// Deletes Today's saved agenda-order rows, and its empty day pads, dated
/// before the start of the day 30 days ago — at most 1,000 of each per run.
/// Pads with text are kept, so a guide can return to past notes indefinitely.
///
/// Until 2026-09-26 `TodayViewModel` did this on the main thread each time it
/// was created, and `TodayView.init` creates one on every redraw of its parent.
/// Now the first view model made each day starts it for its store, on a
/// background context: the same rows go, with the same cutoff, predicates and
/// caps, once a day instead of many times, and never on the main thread.
nonisolated enum TodayRetentionCleanup {

    /// How many rows one run deleted.
    struct Outcome: Sendable, Equatable {
        var agendaOrders = 0
        var dayPads = 0
    }

    /// The most rows of each entity one run deletes.
    static let rowLimit = 1000

    private static let logger = Logger.app_

    /// Starts a run for `context`'s store on a background context, unless one
    /// already started there today. Returns the run's task, or nil when none
    /// was due.
    @MainActor
    @discardableResult
    static func startIfDue(
        for context: NSManagedObjectContext,
        now: Date = Date(),
        gate: TodayRetentionCleanupGate = .shared
    ) -> Task<Outcome, Never>? {
        guard let coordinator = context.persistentStoreCoordinator,
              gate.claim(coordinator, day: AppCalendar.startOfDay(now)) else { return nil }
        let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        background.persistentStoreCoordinator = coordinator
        // Saved as the view context's own saves were: under its author, which
        // the history processor skips as a local write, and with its merge policy.
        background.transactionAuthor = context.transactionAuthor
        background.mergePolicy = context.mergePolicy
        // `.utility`, like the launch pass. The old `.background` task ran as a
        // main-actor job, so it ran at once; off the main thread, `.background`
        // work can wait tens of seconds for a core while anything else is busy.
        return Task(priority: .utility) {
            await run(on: background, now: now)
        }
    }

    /// Runs the cleanup on `context`'s own queue. `@concurrent`, so the block
    /// is handed to the context at the calling task's priority rather than
    /// from the main thread.
    @concurrent
    static func run(on context: NSManagedObjectContext, now: Date) async -> Outcome {
        await context.perform { deleteExpiredRows(in: context, now: now) }
    }

    /// Deletes the expired rows and saves once if any went. On `context`'s queue.
    static func deleteExpiredRows(in context: NSManagedObjectContext, now: Date) -> Outcome {
        let cutoff = AppCalendar.startOfDay(AppCalendar.addingDays(-30, to: now))

        let orderRequest = CDFetchRequest(CDTodayAgendaOrder.self)
        orderRequest.predicate = NSPredicate(format: "day < %@", cutoff as NSDate)
        orderRequest.fetchLimit = rowLimit

        let padRequest = CDFetchRequest(CDDayPad.self)
        padRequest.predicate = NSPredicate(
            format: "day < %@ AND (body == nil OR body == %@)",
            cutoff as NSDate, ""
        )
        padRequest.fetchLimit = rowLimit

        let orders = fetch(orderRequest, in: context, describing: "agenda orders")
        let pads = fetch(padRequest, in: context, describing: "day pads")
        for order in orders {
            context.delete(order)
        }
        for pad in pads {
            context.delete(pad)
        }
        if !orders.isEmpty || !pads.isEmpty {
            context.safeSave()
        }
        return Outcome(agendaOrders: orders.count, dayPads: pads.count)
    }

    private static func fetch<T: NSManagedObject>(
        _ request: NSFetchRequest<T>,
        in context: NSManagedObjectContext,
        describing rows: String
    ) -> [T] {
        do {
            return try context.fetch(request)
        } catch {
            logger.warning("Failed to cleanup old \(rows, privacy: .public): \(error)")
            return []
        }
    }
}

/// Remembers, per store coordinator, the day the Today cleanup last started,
/// so it starts at most once a day per store however many view models are made.
@MainActor
final class TodayRetentionCleanupGate {
    static let shared = TodayRetentionCleanupGate()

    private struct Claim {
        weak var coordinator: NSPersistentStoreCoordinator?
        let day: Date
    }

    /// Keyed by coordinator identity; the weak reference tells the coordinator
    /// that claimed from a new one that happens to reuse its address.
    private var claims: [ObjectIdentifier: Claim] = [:]

    /// True, and remembered, the first time `coordinator` asks on `day`.
    func claim(_ coordinator: NSPersistentStoreCoordinator, day: Date) -> Bool {
        let key = ObjectIdentifier(coordinator)
        if let existing = claims[key], existing.coordinator === coordinator, existing.day == day {
            return false
        }
        claims = claims.filter { $0.value.coordinator != nil }
        claims[key] = Claim(coordinator: coordinator, day: day)
        return true
    }
}
