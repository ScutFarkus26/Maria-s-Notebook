import CloudKit
import CoreData
import Foundation
import os

// Carrying out the plan (`ClassroomShareRelease`): each batch in five steps, every step
// confirmed against the CloudKit server itself. On 2026-09-30 a store reported healthy
// while the share's export was being refused, so an export event is never taken as proof
// that iCloud has a record.

nonisolated extension ClassroomShareRelease {

    static let logger = Logger(subsystem: "CosmicDaybook", category: "ClassroomShareRelease")

    /// The steps of one batch, for progress and for tests: a move's five, and a twin
    /// cleanup's four (`+Twins`).
    enum Step: String, Sendable {
        case copied, copiesConfirmed, copiesChecked, originalsDeleted, originalsGone
        case sharedConfirmed, twinsChecked, twinsDeleted, twinsGone
    }

    /// What the run needs from outside the store. The app's reaches CloudKit
    /// (`live(container:)`); tests stand in for it.
    struct Environment: Sendable {
        /// The share zone each object is in; objects in no share are absent.
        var shareZones: @Sendable ([NSManagedObjectID]) async throws -> [NSManagedObjectID: String]
        /// The CloudKit record each object is mirrored to, for those exported so far.
        var recordIDs: @Sendable ([NSManagedObjectID]) async -> [NSManagedObjectID: CKRecord.ID]
        /// Of these records, the ones the server holds, with their modification dates.
        var serverRecords: @Sendable ([CKRecord.ID]) async throws -> [CKRecord.ID: Date]
        /// A reason to stop right now (a store stopped syncing), or nil.
        var stopReason: @Sendable () async -> String?
        /// Another copy of the app has the notebook open (`anotherCopyBlocker`): checked with
        /// `stopReason`, since a copy can open after the run began.
        var anotherCopyOpen: @Sendable () async -> Bool = { false }
        var sleep: @Sendable (Duration) async throws -> Void
        /// How long one step may wait for the server before the run stops.
        var patience: Duration
        /// Waits until no CloudKit export of the notebook is running. A save made while one
        /// runs can be left out of it with no export scheduled after (seen in the 2026-09-30
        /// rehearsal: the last batch's deletes sat unsent until the app was relaunched).
        var exportIdle: @Sendable () async -> Void = {}
        /// Whether an export of the notebook started after `date`, waiting a little for one.
        var exportStarted: @Sendable (_ after: Date) async -> Bool = { _ in true }
        /// Called after each step of each batch (tests).
        var afterStep: @Sendable (Step, Batch) async -> Void = { _, _ in }
        /// The originals whose delete was saved here but not yet confirmed gone from iCloud
        /// (steps 4–5), kept across launches: once they're deleted here no plan can name them,
        /// so a run stopped there is finished from this list (`finishStopped`). Each batch
        /// adds its own and takes them off once confirmed, never the others': a stopped run's
        /// are confirmed at the end of the next (`run`).
        var awaitingGone: @Sendable () -> [CKRecord.ID] = { [] }
        var setAwaitingGone: @Sendable ([CKRecord.ID]) -> Void = { _ in }
        /// Of these records, the ones whose objects are in this Mac's store: back after a
        /// re-download, say. A stopped run's deletes that are back aren't waited on
        /// (`confirmLeftovers`).
        var heldHere: @Sendable ([CKRecord.ID]) async -> Set<CKRecord.ID> = { _ in [] }
    }

    /// How a run went.
    struct Report: Sendable, Equatable {
        var studentsMoved = 0
        var attendanceMoved = 0
        /// Records another device deleted during the run: their copies went too
        /// (`settleVanished`), so they aren't counted as moved.
        var deletedElsewhere = 0
        /// Records a stopped run left twice that belong in the share after all, back to one
        /// copy: the shared one (`+Twins`).
        var twinsCleaned = 0
        /// A stopped run's deletes iCloud still hadn't confirmed when the wait ran out: taken
        /// off the list anyway, so the run can finish (`confirmLeftovers`).
        var unconfirmed = 0
        var batchesDone = 0
        var batchesPlanned = 0
        /// Why the run stopped, in plain words; nil when it finished.
        var stoppedBecause: String?
        /// The technical reason it stopped, for the Details disclosure.
        var stopDetails: String?
    }

    // MARK: - Running

    /// Carries out `batches` in order, stopping at the first problem. The first batch is
    /// the canary. `progress` hears (batches done, batches planned) after each batch. The
    /// writes go through `stack`'s own kind of context (`runContext`): saved with the app's
    /// author, the history processor and another running copy of the app read them as this
    /// copy's (bug hunt 2026-11-02, #53).
    static func run(
        _ batches: [Batch],
        stack: CoreDataStack,
        storeID: String,
        environment: Environment,
        progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> Report {
        var report = Report(batchesPlanned: batches.count)
        func stopped(by error: Error) -> Report {
            let stop = stopMessage(for: error)
            report.stoppedBecause = stop.message
            report.stopDetails = stop.details
            logger.error("Release stopped: \(stop.details, privacy: .public)")
            return report
        }
        for batch in batches {
            if !batch.twinCleanups.isEmpty {
                do {
                    try await runTwinCleanup(batch, stack: stack, environment: environment)
                } catch {
                    return stopped(by: error)
                }
                report.batchesDone += 1
                report.twinsCleaned += batch.twinCleanups.count
                await progress(report.batchesDone, report.batchesPlanned)
                continue
            }
            let settled: Set<NSManagedObjectID>
            do {
                settled = try await runBatch(batch, stack: stack, storeID: storeID, environment: environment)
            } catch {
                return stopped(by: error)
            }
            report.batchesDone += 1
            let moved = batch.moves.filter { !settled.contains($0.source) }
            report.studentsMoved += moved.filter { $0.entity == "Student" }.count
            report.attendanceMoved += moved.filter { $0.entity == "AttendanceRecord" }.count
            report.deletedElsewhere += batch.moves.count - moved.count
            await progress(report.batchesDone, report.batchesPlanned)
        }
        // A stopped run's deletes still awaiting iCloud: this run's saves exported them.
        do {
            report.unconfirmed = try await confirmLeftovers(environment.awaitingGone(), environment: environment)
        } catch {
            return stopped(by: error)
        }
        logger.notice(
            "Release finished: \(report.studentsMoved) students, \(report.attendanceMoved) attendance records"
        )
        return report
    }

    /// Takes `records` off the awaiting list, leaving any others on it.
    static func removeAwaitingGone(_ records: [CKRecord.ID], environment env: Environment) {
        let done = Set(records)
        env.setAwaitingGone(env.awaitingGone().filter { !done.contains($0) })
    }

    /// Throws when the run must stop now: a store stopped syncing, or another copy of the
    /// app opened the notebook.
    static func checkCanGoOn(_ env: Environment) async throws {
        if let reason = await env.stopReason() { throw RunError.stopped(reason) }
        if await env.anotherCopyOpen() { throw RunError.anotherCopyOpen }
    }

    /// How many times a batch checks again when a record changed between its check and its
    /// delete (`RunError.changedDuringRun`) before the run stops.
    static let changeRetries = 3

    /// One batch, in the five steps. Returns the sources of the moves another device
    /// deleted meanwhile (`settleVanished`): those went, copy and all, rather than moved.
    @discardableResult
    static func runBatch(
        _ batch: Batch,
        stack: CoreDataStack,
        storeID: String,
        environment env: Environment
    ) async throws -> Set<NSManagedObjectID> {
        try await checkCanGoOn(env)
        let context = await runContext(stack)
        // The originals' iCloud records, read while they're all here: one that another device
        // deletes during the batch can't be looked up once the delete reaches this Mac.
        let startRecords = await env.recordIDs(batch.moves.flatMap(\.sharedRows))

        // 1. The private copies (or the ones an earlier run made). Each `saved` is taken once
        // the save has returned: an export that began during a save may have missed it.
        await env.exportIdle()
        let keepers = try await makeCopies(batch, context: context, storeID: storeID)
        var saved = Date()
        try await makeSureItExports(after: saved, nudging: keepers.values.first, context: context, environment: env)
        await env.afterStep(.copied, batch)

        // 2. iCloud has every copy, outside any share.
        var confirmed = try await waitForCopies(Array(keepers.values), environment: env)
        await env.afterStep(.copiesConfirmed, batch)

        // Steps 3 and 4, and again from 3 when an original changed after its copy was
        // checked: the run can take many minutes, and the Mac's main window still edits
        // (bug hunt 2026-11-02, #37). Step 3 brings the change over; nothing is lost.
        var settled = Set<NSManagedObjectID>()
        var retries = 0
        while true {
            // 3. Each copy is still here; anything the original changed since is brought over.
            await env.exportIdle()
            let checking = batch.moves.filter { !settled.contains($0.source) }
            let checked = try await checkCopies(checking, keepers: keepers, context: context)
            saved = Date()
            if !checked.changed.isEmpty {
                try await makeSureItExports(
                    after: saved, nudging: checked.changed.first, context: context, environment: env
                )
                let newer = try await waitForNewerCopies(checked.changed, than: confirmed, environment: env)
                confirmed.merge(newer) { $1 }
            }
            settled.formUnion(try await settleVanished(
                checked.vanished, records: startRecords, keepers: keepers, context: context, environment: env
            ))
            await env.afterStep(.copiesChecked, batch)

            // 4. The shared originals go (but not those deleted elsewhere, settled above),
            // each only while its private copy is still here and holds every change of the
            // original's, checked again in the delete's own pass: a copy another device
            // deleted after step 3 keeps its original, and an original changed since goes
            // back to step 3.
            let remaining = batch.moves.filter { !settled.contains($0.source) }
            let originals = remaining.flatMap(\.sharedRows)
            let originalRecords = Array(await env.recordIDs(originals).values)
            guard originalRecords.count == originals.count else { throw RunError.originalNotMirrored }
            await env.exportIdle()
            do {
                try await deleteListed(originalRecords, environment: env) {
                    try await deleteOriginals(remaining, keepers: keepers, context: context)
                }
            } catch RunError.changedDuringRun where retries < changeRetries {
                retries += 1
                logger.notice("An original changed after its copy was checked; checking again")
                continue
            }
            saved = Date()
            try await makeSureItExports(after: saved, nudging: keepers.values.first, context: context, environment: env)
            await env.afterStep(.originalsDeleted, batch)

            // 5. iCloud no longer has them.
            try await waitForGone(originalRecords, environment: env)
            removeAwaitingGone(originalRecords, environment: env)
            await env.afterStep(.originalsGone, batch)
            return settled
        }
    }

    // MARK: - The steps

    /// Makes sure what was saved after `saved` goes to iCloud: when no export starts, one
    /// harmless change (a private copy's `modifiedAt`, a millisecond on) is saved to schedule
    /// one. Without it, a save that landed while an export ran could wait for the next launch.
    static func makeSureItExports(
        after saved: Date,
        nudging keeper: NSManagedObjectID?,
        context: NSManagedObjectContext,
        environment env: Environment
    ) async throws {
        if await env.exportStarted(saved) { return }
        guard let keeper else { return }
        logger.notice("No export started after the save; nudging one")
        await env.exportIdle()
        try await context.perform {
            guard let object = try? context.existingObject(with: keeper),
                  object.entity.attributesByName["modifiedAt"] != nil else { return }
            let stamp = (object.value(forKey: "modifiedAt") as? Date) ?? Date()
            object.setValue(stamp.addingTimeInterval(0.001), forKey: "modifiedAt")
            if context.hasChanges { try context.save() }
        }
        let nudged = Date() // once the save has returned
        if !(await env.exportStarted(nudged)) {
            logger.error("Still no export after the nudge; the server checks will wait for one")
        }
    }

    /// Source → the private copy that stays.
    private static func makeCopies(
        _ batch: Batch, context: NSManagedObjectContext, storeID: String
    ) async throws -> [NSManagedObjectID: NSManagedObjectID] {
        try await context.perform {
            guard let store = store(storeID, in: context) else { throw RunError.storeUnavailable }
            var keepers: [NSManagedObjectID: NSManagedObjectID] = [:]
            var made: [(NSManagedObjectID, NSManagedObject)] = []
            for move in batch.moves {
                if let twin = move.existingTwin {
                    keepers[move.source] = twin
                    continue
                }
                let original = try context.existingObject(with: move.source)
                let copy = NSManagedObject(entity: original.entity, insertInto: context)
                copyAttributes(from: original, to: copy)
                context.assign(copy, to: store)
                made.append((move.source, copy))
            }
            if context.hasChanges { try context.save() }
            for (source, copy) in made { keepers[source] = copy.objectID }
            return keepers
        }
    }

    /// Waits until the server holds every copy; returns their modification dates.
    private static func waitForCopies(
        _ copies: [NSManagedObjectID], environment env: Environment
    ) async throws -> [NSManagedObjectID: Date] {
        try await waitFor("the private copies", environment: env) { () -> [NSManagedObjectID: Date]? in
            let records = await env.recordIDs(copies)
            guard records.count == copies.count else { return nil }
            if records.values.contains(where: { ClassroomShareScope.isShareZone($0.zoneID.zoneName) }) {
                throw RunError.copyLandedInShare
            }
            let onServer = try await env.serverRecords(Array(records.values))
            guard onServer.count == records.count else { return nil }
            return records.compactMapValues { onServer[$0] }
        }
    }

    /// Waits until the server holds a newer version of each of `changed` than `confirmed`;
    /// returns those versions' dates, against which a later change is confirmed in turn.
    static func waitForNewerCopies(
        _ changed: [NSManagedObjectID], than confirmed: [NSManagedObjectID: Date], environment env: Environment
    ) async throws -> [NSManagedObjectID: Date] {
        try await waitFor("the updated copies", environment: env) { () -> [NSManagedObjectID: Date]? in
            let records = await env.recordIDs(changed)
            let onServer = try await env.serverRecords(Array(records.values))
            var newer: [NSManagedObjectID: Date] = [:]
            for id in changed {
                guard let record = records[id], let date = onServer[record],
                      date > (confirmed[id] ?? .distantPast) else { return nil }
                newer[id] = date
            }
            return newer
        }
    }

    // MARK: - Helpers

    /// Polls `attempt` until it returns a value, stopping on a sync problem or after
    /// `patience`.
    static func waitFor<T>(
        _ what: String,
        environment env: Environment,
        _ attempt: () async throws -> T?
    ) async throws -> T {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: env.patience)
        var pause = Duration.seconds(2)
        while true {
            try await checkCanGoOn(env)
            do {
                if let value = try await attempt() { return value }
            } catch let error where CloudKitServerCheck.isTransient(error) {
                // A dropped connection, throttling or a slow answer: ask again.
                logger.notice("Waiting for \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            guard clock.now < deadline else { throw RunError.timedOut(what) }
            try await env.sleep(pause)
            pause = min(pause * 2, .seconds(15))
        }
    }

    /// Every attribute, so an attribute added to the model later is copied too.
    static func copyAttributes(from source: NSManagedObject, to target: NSManagedObject) {
        for name in source.entity.attributesByName.keys {
            target.setValue(source.value(forKey: name), forKey: name)
        }
    }

    /// Whether `lhs` was stamped by an edit after `rhs`. A nudge moves a copy's `modifiedAt`
    /// a millisecond, so only a later stamp by more than a second counts. Without a stamp on
    /// both, the original's values stand. Attendance marks and student edits stamp one (the
    /// profile, level and roster order, the CSV import, rollover grades); sync imports,
    /// restores and repairs don't, since they aren't the guide's edits.
    static func editedLater(_ lhs: NSManagedObject, than rhs: NSManagedObject) -> Bool {
        guard lhs.entity.attributesByName["modifiedAt"] != nil,
              let left = lhs.value(forKey: "modifiedAt") as? Date,
              let right = rhs.value(forKey: "modifiedAt") as? Date else { return false }
        return left.timeIntervalSince(right) > 1
    }

    static func sameAttributes(
        _ lhs: NSManagedObject, _ rhs: NSManagedObject, except skipped: Set<String> = []
    ) -> Bool {
        lhs.entity.attributesByName.keys.allSatisfy { name in
            guard !skipped.contains(name) else { return true }
            let left = lhs.value(forKey: name) as? NSObject
            let right = rhs.value(forKey: name) as? NSObject
            return left == right || (left?.isEqual(right) ?? false)
        }
    }

    static func store(_ identifier: String, in context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores.first { $0.identifier == identifier }
    }
}
