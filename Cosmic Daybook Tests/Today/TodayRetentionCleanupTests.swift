import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Efficiency pass 2026-09-26 (Energy Fifty #12). TodayViewModel ran the 30-day
// cleanup of agenda orders and empty day pads on the main thread every time it
// was created, and TodayView.init creates one on every redraw of its parent. It
// now starts once a day per store, on a background context. These pin that it
// deletes exactly what the old code deleted (kept below), on the in-memory store
// and on SQLite; that it starts once a day however many view models are made;
// and that it runs off the main thread under the view context's author.

@Suite("Today retention cleanup")
@MainActor
struct TodayRetentionCleanupTests {
    typealias Store = LaunchRepairFixture.Store

    /// Friday 25 September 2026, mid-afternoon: the cutoff is the start of 26 August.
    private let now = AppCalendar.shared.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 15))!

    private var cutoff: Date {
        AppCalendar.startOfDay(AppCalendar.addingDays(-30, to: now))
    }

    private static func id(_ number: Int) -> UUID {
        LaunchRepairFixture.uuid(0x400 + number)
    }

    /// Agenda orders and day pads on both sides of the cutoff: a day before,
    /// a second before, exactly at it, after it, undated and long ago; pads
    /// empty, nil, written in, and holding only a space.
    private func seed(_ context: NSManagedObjectContext) throws {
        let dayBefore = cutoff.addingTimeInterval(-86_400)
        let orders: [(Int, Date?)] = [
            (1, dayBefore), (2, cutoff.addingTimeInterval(-1)), (3, cutoff),
            (4, cutoff.addingTimeInterval(86_400)), (5, nil), (6, .distantPast)
        ]
        for (number, day) in orders {
            let order = CDTodayAgendaOrder(context: context)
            order.id = Self.id(number)
            order.day = day
        }
        let pads: [PadSeed] = [
            PadSeed(number: 11, day: dayBefore, body: ""),
            PadSeed(number: 12, day: dayBefore, body: nil),
            PadSeed(number: 13, day: dayBefore, body: "Notes"),
            PadSeed(number: 14, day: cutoff.addingTimeInterval(2 * 86_400), body: ""),
            PadSeed(number: 15, day: nil, body: ""),
            PadSeed(number: 16, day: cutoff.addingTimeInterval(-1), body: " ")
        ]
        for seed in pads {
            let pad = CDDayPad(context: context, day: seed.day ?? .distantPast)
            pad.id = Self.id(seed.number)
            pad.day = seed.day
            pad.body = seed.body
        }
        try context.save()
    }

    private struct PadSeed {
        let number: Int
        let day: Date?
        let body: String?
    }

    /// Ids of the agenda orders and day pads still saved.
    private func remaining(in context: NSManagedObjectContext) -> Set<UUID> {
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        let orders = reader.safeFetch(CDFetchRequest(CDTodayAgendaOrder.self)).compactMap(\.id)
        let pads = reader.safeFetch(CDFetchRequest(CDDayPad.self)).compactMap(\.id)
        return Set(orders + pads)
    }

    private func count<T: NSManagedObject>(_ type: T.Type, in context: NSManagedObjectContext) throws -> Int {
        let reader = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        reader.persistentStoreCoordinator = context.persistentStoreCoordinator
        return try reader.count(for: CDFetchRequest(type))
    }

    // MARK: - Same rows

    @Test("Deletes exactly the rows the view-context cleanup deleted", arguments: [Store.inMemory, .sqlite])
    func sameRowsDeleted(store: Store) async throws {
        let (old, oldOwner) = try store.make()
        let (new, newOwner) = try store.make()
        defer { withExtendedLifetime((oldOwner, newOwner)) {} }
        try seed(old)
        try seed(new)

        oldCleanupOldOrders(context: old, now: now)
        oldCleanupOldDayPads(context: old, now: now)
        let outcome = await TodayRetentionCleanup.run(
            on: LaunchRepairFixture.backgroundContext(beside: new), now: now
        )

        let kept = remaining(in: new)
        let expired: [UUID] = [1, 2, 6, 11, 12].map(Self.id)
        let current: [UUID] = [3, 4, 13, 14, 16].map(Self.id)
        #expect(kept == remaining(in: old))
        #expect(kept.isDisjoint(with: expired))
        #expect(kept.isSuperset(of: current))
        #expect(outcome == TodayRetentionCleanup.Outcome(agendaOrders: 3, dayPads: 2))
    }

    @Test("Stops at 1,000 rows of each, as before", arguments: [Store.inMemory, .sqlite])
    func sameCapPerRun(store: Store) async throws {
        let (old, oldOwner) = try store.make()
        let (new, newOwner) = try store.make()
        defer { withExtendedLifetime((oldOwner, newOwner)) {} }
        let longAgo = cutoff.addingTimeInterval(-10 * 86_400)
        for context in [old, new] {
            for _ in 0..<1_005 {
                CDTodayAgendaOrder(context: context).day = longAgo
                CDDayPad(context: context, day: longAgo)
            }
            try context.save()
        }

        oldCleanupOldOrders(context: old, now: now)
        oldCleanupOldDayPads(context: old, now: now)
        let outcome = await TodayRetentionCleanup.run(
            on: LaunchRepairFixture.backgroundContext(beside: new), now: now
        )

        #expect(outcome == TodayRetentionCleanup.Outcome(agendaOrders: 1_000, dayPads: 1_000))
        #expect(try count(CDTodayAgendaOrder.self, in: new) == 5)
        #expect(try count(CDDayPad.self, in: new) == 5)
        #expect(try count(CDTodayAgendaOrder.self, in: old) == 5)
        #expect(try count(CDDayPad.self, in: old) == 5)
    }

    // MARK: - Once a day

    @Test("Starts once a day per store")
    func startsOncePerDayPerStore() async throws {
        let gate = TodayRetentionCleanupGate()
        let first = try CoreDataTestHelpers.makeInMemoryStack()
        let second = try CoreDataTestHelpers.makeInMemoryStack()
        let tomorrow = AppCalendar.addingDays(1, to: now)

        let firstRun = TodayRetentionCleanup.startIfDue(for: first.viewContext, now: now, gate: gate)
        let again = TodayRetentionCleanup.startIfDue(
            for: first.viewContext, now: now.addingTimeInterval(3_600), gate: gate
        )
        let otherStore = TodayRetentionCleanup.startIfDue(for: second.viewContext, now: now, gate: gate)
        let nextDay = TodayRetentionCleanup.startIfDue(for: first.viewContext, now: tomorrow, gate: gate)

        #expect(firstRun != nil)
        #expect(again == nil)
        #expect(otherStore != nil)
        #expect(nextDay != nil)
        for task in [firstRun, otherStore, nextDay] {
            _ = await task?.value
        }
    }

    @Test("However many Today view models are made, the day's run starts once and deletes the old rows")
    func viewModelsStartItOnce() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let view = stack.viewContext
        let today = Date()
        let old = CDTodayAgendaOrder(context: view)
        old.day = AppCalendar.addingDays(-40, to: today)
        let recent = CDTodayAgendaOrder(context: view)
        recent.day = AppCalendar.addingDays(-3, to: today)
        try view.save()

        // TodayView makes one per parent redraw.
        let models = (0..<5).map { _ in TodayViewModel(context: view) }
        #expect(models.count == 5)
        // The first one claimed today's run for this store.
        #expect(TodayRetentionCleanup.startIfDue(for: view, now: today) == nil)

        // The run is the first view model's, started in its init; poll for it.
        let deadline = ContinuousClock.now + .seconds(30)
        while try count(CDTodayAgendaOrder.self, in: view) > 1, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(remaining(in: view) == Set([recent.id].compactMap { $0 }))
    }

    // MARK: - Off the main thread

    @Test("Runs and saves on a background queue, under the view context's author")
    func runsOffTheMainThread() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("unified.sqlite")
        let stack = try CoreDataStack(enableCloudKit: false, localStoreURL: storeURL)
        let view = stack.viewContext
        try seed(view)
        let recorder = ContextSaveRecorder(coordinator: view.persistentStoreCoordinator)

        let outcome = await TodayRetentionCleanup.startIfDue(
            for: view, now: now, gate: TodayRetentionCleanupGate()
        )?.value
        let saves = recorder.finish()

        #expect(outcome == TodayRetentionCleanup.Outcome(agendaOrders: 3, dayPads: 2))
        #expect(saves.count == 1)
        #expect(saves.allSatisfy { !$0.onMainThread && $0.context != ObjectIdentifier(view) })
        let cleanedEntities: Set<String> = ["TodayAgendaOrder", "DayPad"]
        #expect(saves.first?.entityNames == cleanedEntities)

        // The history processor tells local writes by author; this one must read as local.
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: nil as NSPersistentHistoryToken?)
        let history = try view.execute(request)
        let transactions = (history as? NSPersistentHistoryResult)?.result as? [NSPersistentHistoryTransaction]
        #expect(transactions?.last?.author == PersistentHistoryProcessor.transactionAuthor)
    }

    // MARK: - The old code

    /// `TodayAgendaBuilder.cleanupOldOrders` as it was until 2026-09-26
    /// (TodayViewModel ran it on its view context), with `Date()` passed in as
    /// `now` so both sides read one clock.
    private func oldCleanupOldOrders(context: NSManagedObjectContext, now: Date) {
        let cutoff = AppCalendar.startOfDay(
            AppCalendar.addingDays(-30, to: now)
        )
        do {
            let request = CDFetchRequest(CDTodayAgendaOrder.self)
            request.predicate = NSPredicate(format: "day < %@", cutoff as NSDate)
            request.fetchLimit = 1000
            let old = try context.fetch(request)
            guard !old.isEmpty else { return }
            for entry in old {
                context.delete(entry)
            }
            context.safeSave()
        } catch {
            Issue.record("Failed to cleanup old agenda orders: \(error)")
        }
    }

    /// `TodayAgendaBuilder.cleanupOldDayPads`, likewise.
    private func oldCleanupOldDayPads(context: NSManagedObjectContext, now: Date) {
        let cutoff = AppCalendar.startOfDay(
            AppCalendar.addingDays(-30, to: now)
        )
        do {
            let request = CDFetchRequest(CDDayPad.self)
            request.predicate = NSPredicate(
                format: "day < %@ AND (body == nil OR body == %@)",
                cutoff as NSDate, ""
            )
            request.fetchLimit = 1000
            let old = try context.fetch(request)
            guard !old.isEmpty else { return }
            for entry in old {
                context.delete(entry)
            }
            context.safeSave()
        } catch {
            Issue.record("Failed to cleanup old day pads: \(error)")
        }
    }
}
