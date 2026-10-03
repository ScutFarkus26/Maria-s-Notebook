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

    /// The steps of one batch, for progress and for tests.
    enum Step: String, Sendable {
        case copied, copiesConfirmed, copiesChecked, originalsDeleted, originalsGone
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
        /// so a run stopped there is finished from this list (`finishStopped`).
        var awaitingGone: @Sendable () -> [CKRecord.ID] = { [] }
        var setAwaitingGone: @Sendable ([CKRecord.ID]) -> Void = { _ in }
    }

    enum RunError: LocalizedError, Equatable {
        case stopped(String)
        case timedOut(String)
        case copyVanished
        case originalVanished
        case copyLandedInShare
        case originalNotMirrored
        case storeUnavailable

        var errorDescription: String? {
            switch self {
            case .stopped(let reason): return "Stopped: \(reason)"
            case .timedOut(let step):
                return "iCloud didn't confirm \(step) in time. Nothing is lost; run it again later to finish."
            case .copyVanished:
                return "A private copy disappeared before its original was removed — another device may be "
                    + "running an older build. That record was left in the share; nothing is lost."
            case .originalVanished:
                return "A record left this Mac during the run while iCloud still has it. Its private copy "
                    + "was kept; nothing is lost. Run it again later."
            case .copyLandedInShare: return "A copy was filed into a share instead of the notebook. Stopped."
            case .originalNotMirrored: return "A shared record had no iCloud record to check. Stopped."
            case .storeUnavailable: return "The notebook's store isn't open."
            }
        }
    }

    /// How a run went.
    struct Report: Sendable, Equatable {
        var studentsMoved = 0
        var attendanceMoved = 0
        var batchesDone = 0
        var batchesPlanned = 0
        var stoppedBecause: String?
    }

    // MARK: - Reading the store

    /// The planner's rows: every Student and AttendanceRecord in the private store, with
    /// where each lives and whether it belongs. Records in some other share are left out:
    /// nothing here ever touches another share.
    static func rows(
        container: NSPersistentCloudKitContainer,
        storeID: String,
        pinnedZone: String,
        scope: ClassroomShareScope,
        environment: Environment
    ) async throws -> [Row] {
        let context = container.newBackgroundContext()
        let read: (ids: [NSManagedObjectID], facts: [NSManagedObjectID: Facts])? = await context.perform {
            guard let store = store(storeID, in: context) else { return nil }
            let belonging = scope.belongingStudentIDs(in: context, store: store)
            var ids: [NSManagedObjectID] = []
            var facts: [NSManagedObjectID: Facts] = [:]
            for entity in ["Student", "AttendanceRecord"] {
                let request = NSFetchRequest<NSManagedObject>(entityName: entity)
                request.affectedStores = [store]
                for object in (try? context.fetch(request)) ?? [] {
                    ids.append(object.objectID)
                    facts[object.objectID] = Facts(object, belonging: belonging, scope: scope)
                }
            }
            return (ids, facts)
        }
        guard let read else { throw RunError.storeUnavailable }
        let zones = try await environment.shareZones(read.ids)
        return read.ids.compactMap { id in
            guard let facts = read.facts[id] else { return nil }
            let zone = zones[id]
            if let zone, zone != pinnedZone { return nil } // another share: never touched
            return Row(
                objectID: id, entity: facts.entity, recordID: facts.recordID,
                studentKey: facts.studentKey, isShared: zone != nil, belongs: facts.belongs
            )
        }
    }

    /// What the planner needs of one object, read on its context's queue.
    struct Facts: Sendable {
        let entity: String
        let recordID: UUID?
        let studentKey: String
        let belongs: Bool

        init(_ object: NSManagedObject, belonging: Set<String>, scope: ClassroomShareScope) {
            entity = object.entity.name ?? ""
            recordID = object.value(forKey: "id") as? UUID
            if entity == "Student" {
                studentKey = ClassroomShareScope.normalizedID(recordID?.uuidString ?? "")
                belongs = belonging.contains(studentKey)
            } else {
                let studentID = object.value(forKey: "studentID") as? String ?? ""
                studentKey = ClassroomShareScope.normalizedID(studentID)
                belongs = scope.attendanceBelongs(
                    date: object.value(forKey: "date") as? Date, studentID: studentID, belongingStudentIDs: belonging
                )
            }
        }
    }

    // MARK: - Running

    /// Carries out `batches` in order, stopping at the first problem. The first batch is
    /// the canary. `progress` hears (batches done, batches planned) after each batch.
    static func run(
        _ batches: [Batch],
        container: NSPersistentCloudKitContainer,
        storeID: String,
        environment: Environment,
        progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async -> Report {
        var report = Report(batchesPlanned: batches.count)
        for batch in batches {
            do {
                try await runBatch(batch, container: container, storeID: storeID, environment: environment)
            } catch {
                report.stoppedBecause = error.localizedDescription
                logger.error("Release stopped: \(error.localizedDescription, privacy: .public)")
                return report
            }
            report.batchesDone += 1
            report.studentsMoved += batch.moves.filter { $0.entity == "Student" }.count
            report.attendanceMoved += batch.moves.filter { $0.entity == "AttendanceRecord" }.count
            await progress(report.batchesDone, report.batchesPlanned)
        }
        logger.notice(
            "Release finished: \(report.studentsMoved) students, \(report.attendanceMoved) attendance records"
        )
        return report
    }

    /// One batch, in the five steps.
    static func runBatch(
        _ batch: Batch,
        container: NSPersistentCloudKitContainer,
        storeID: String,
        environment env: Environment
    ) async throws {
        if let reason = await env.stopReason() { throw RunError.stopped(reason) }
        let context = container.newBackgroundContext()
        // The originals' iCloud records, read while they're all here: one that another device
        // deletes during the batch can't be looked up once the delete reaches this Mac.
        let startRecords = await env.recordIDs(batch.moves.flatMap(\.sharedRows))

        // 1. The private copies (or the ones an earlier run made).
        await env.exportIdle()
        var saved = Date()
        let keepers = try await makeCopies(batch, context: context, storeID: storeID)
        try await makeSureItExports(after: saved, nudging: keepers.values.first, context: context, environment: env)
        await env.afterStep(.copied, batch)

        // 2. iCloud has every copy, outside any share.
        let confirmed = try await waitForCopies(Array(keepers.values), environment: env)
        await env.afterStep(.copiesConfirmed, batch)

        // 3. Each copy is still here; anything the original changed since is brought over.
        await env.exportIdle()
        saved = Date()
        let checked = try await checkCopies(batch.moves, keepers: keepers, context: context)
        if !checked.changed.isEmpty {
            try await makeSureItExports(
                after: saved, nudging: checked.changed.first, context: context, environment: env
            )
            try await waitForNewerCopies(checked.changed, than: confirmed, environment: env)
        }
        let settled = try await settleVanished(
            checked.vanished, records: startRecords, keepers: keepers, context: context, environment: env
        )
        await env.afterStep(.copiesChecked, batch)

        // 4. The shared originals go (but not those deleted elsewhere, settled above).
        let originals = batch.moves.filter { !settled.contains($0.source) }.flatMap(\.sharedRows)
        let originalRecords = await env.recordIDs(originals)
        guard originalRecords.count == originals.count else { throw RunError.originalNotMirrored }
        await env.exportIdle()
        saved = Date()
        env.setAwaitingGone(Array(originalRecords.values))
        try await deleteOriginals(originals, context: context)
        try await makeSureItExports(after: saved, nudging: keepers.values.first, context: context, environment: env)
        await env.afterStep(.originalsDeleted, batch)

        // 5. iCloud no longer has them.
        try await waitForGone(Array(originalRecords.values), environment: env)
        env.setAwaitingGone([])
        await env.afterStep(.originalsGone, batch)
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
        let nudged = Date()
        try await context.perform {
            guard let object = try? context.existingObject(with: keeper),
                  object.entity.attributesByName["modifiedAt"] != nil else { return }
            let stamp = (object.value(forKey: "modifiedAt") as? Date) ?? Date()
            object.setValue(stamp.addingTimeInterval(0.001), forKey: "modifiedAt")
            if context.hasChanges { try context.save() }
        }
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

    /// Waits until the server holds a newer version of each of `changed` than `confirmed`.
    private static func waitForNewerCopies(
        _ changed: [NSManagedObjectID], than confirmed: [NSManagedObjectID: Date], environment env: Environment
    ) async throws {
        _ = try await waitFor("the updated copies", environment: env) { () -> Bool? in
            let records = await env.recordIDs(changed)
            let onServer = try await env.serverRecords(Array(records.values))
            let newer = changed.allSatisfy { id in
                guard let record = records[id], let date = onServer[record] else { return false }
                return date > (confirmed[id] ?? .distantPast)
            }
            return newer ? true : nil
        }
    }

    private static func deleteOriginals(
        _ originals: [NSManagedObjectID], context: NSManagedObjectContext
    ) async throws {
        try await context.perform {
            for id in originals {
                // Gone already (another run finished it): nothing to delete.
                if let object = try? context.existingObject(with: id) { context.delete(object) }
            }
            if context.hasChanges { try context.save() }
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
            if let reason = await env.stopReason() { throw RunError.stopped(reason) }
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

    static func sameAttributes(_ lhs: NSManagedObject, _ rhs: NSManagedObject) -> Bool {
        lhs.entity.attributesByName.keys.allSatisfy { name in
            let left = lhs.value(forKey: name) as? NSObject
            let right = rhs.value(forKey: name) as? NSObject
            return left == right || (left?.isEqual(right) ?? false)
        }
    }

    static func store(_ identifier: String, in context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores.first { $0.identifier == identifier }
    }
}
