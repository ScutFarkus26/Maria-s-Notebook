import CloudKit
import CoreData
import Foundation
import os
#if os(macOS)
import AppKit
#endif

// The release as the app runs it: the checks before it may start, the preview the guide
// reads, and the environment that reaches CloudKit.

extension ClassroomShareRelease {

    /// A child leaving the share, with how many marks go with her.
    struct DepartingChild: Sendable, Equatable, Identifiable {
        let id: String
        let name: String
        let departed: Date?
        let attendanceRecords: Int
    }

    /// What pressing the button would do, for the guide to read before confirming.
    struct Preview: Sendable, Equatable {
        /// The school year's first day: everything from it on stays shared.
        let cutoff: Date
        /// Children leaving the share, with how many marks go with each.
        let children: [DepartingChild]
        /// Earlier-year attendance of children who stay.
        let olderAttendance: Int
        /// Records a stopped run left on both sides; this run finishes them.
        let unfinished: Int
        let batches: [Batch]

        var isEmpty: Bool { batches.isEmpty }
        var recordCount: Int { batches.reduce(0) { $0 + $1.moves.count } }
    }

    /// The release runs on the Mac. A Debug build takes `-AllowShareReleaseOnIOS` so the
    /// rehearsal can run it in a simulator signed into a test account.
    static var isAvailableHere: Bool {
        #if os(macOS)
        return true
        #elseif DEBUG
        return ProcessInfo.processInfo.arguments.contains("-AllowShareReleaseOnIOS")
        #else
        return false
        #endif
    }

    /// Why the release can't start right now, in the guide's words, or nil.
    @MainActor
    static func blocker(coreDataStack: CoreDataStack, isRestoring: Bool) -> String? {
        guard isAvailableHere else { return "Remove last year from the share on your Mac." }
        let context = coreDataStack.viewContext
        if !coreDataStack.isCloudKitActive {
            return "iCloud sync is off. Turn it on in Settings › Sync and backup first."
        }
        if CDClassroomMembership.currentRole(in: context) != .leadGuide {
            return "Only the lead guide's Mac can change what's shared."
        }
        if isRestoring { return "A restore is running. Try again when it finishes." }
        if FirstDownloadGate.isPending() {
            return "This Mac is still downloading your notebook from iCloud. Try again once it has finished."
        }
        if let reason = syncBlocker() { return reason }
        if CDClassroomMembership.pinnedZoneName(in: context) == nil {
            return "Your classroom isn't shared yet, so there's nothing to remove."
        }
        return anotherCopyBlocker()
    }

    /// Another instance of the app on this Mac (a hidden one opened for Claude, say) holds the
    /// same store; a run that changes many records waits until it's quit.
    static func anotherCopyBlocker() -> String? {
        #if os(macOS)
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        )
        if running.count > 1 {
            return "Cosmic Daybook is also open in the background (Claude may have opened it). "
                + "Quit that copy first."
        }
        #endif
        return nil
    }

    /// Sync must be healthy, online and caught up: the release waits on iCloud at every step.
    @MainActor
    static func syncBlocker() -> String? {
        let sync = CloudKitSyncStatusService.shared
        if sync.mirroringDelegateFailed {
            return "iCloud sync has stopped on this Mac. Quit and reopen the app, then try again."
        }
        if let failure = sync.storeHealth.mostSevereFailure, failure.severity == .stopped {
            // The failure's own text is the sync screen's to explain; it goes to the log.
            logger.notice("Release blocked by a stopped store: \(failure.message, privacy: .public)")
            return "iCloud sync is stopped. Check Settings › Sync and backup, then try again."
        }
        if !sync.isNetworkAvailable { return "This Mac is offline. Connect to the internet, then try again." }
        if sync.pendingLocalChanges > 0 {
            let changes = sync.pendingLocalChanges == 1
                ? "1 change is" : "\(sync.pendingLocalChanges.formatted()) changes are"
            return "\(changes) still waiting to go to iCloud. Try again in a minute."
        }
        return nil
    }

    /// Reads the store and plans the release. Nil when the share can't be read.
    @MainActor
    static func preview(coreDataStack: CoreDataStack) async throws -> Preview? {
        guard let store = coreDataStack.privatePersistentStore,
              let pinned = CDClassroomMembership.pinnedZoneName(in: coreDataStack.viewContext) else { return nil }
        let scope = ClassroomShareScope()
        let container = coreDataStack.container
        let rows = try await rows(
            container: container, storeID: store.identifier, pinnedZone: pinned, scope: scope,
            environment: .live(container: container)
        )
        let batches = plan(rows)
        let unfinished = batches.flatMap(\.moves).filter { $0.existingTwin != nil }.count
        let children = await describeChildren(batches, container: container)
        let older = batches.filter { $0.studentKey == nil }.reduce(0) { $0 + $1.moves.count }
        return Preview(
            cutoff: scope.cutoff, children: children, olderAttendance: older,
            unfinished: unfinished, batches: batches
        )
    }

    @concurrent
    private static func describeChildren(
        _ batches: [Batch], container: NSPersistentCloudKitContainer
    ) async -> [DepartingChild] {
        let context = container.newBackgroundContext()
        return await context.perform {
            batches.compactMap { batch -> DepartingChild? in
                guard let key = batch.studentKey,
                      let studentMove = batch.moves.first(where: { $0.entity == "Student" }),
                      let student = try? context.existingObject(with: studentMove.source) as? CDStudent
                else { return nil }
                return DepartingChild(
                    id: key, name: student.fullName, departed: student.dateWithdrawn,
                    attendanceRecords: batch.moves.filter { $0.entity == "AttendanceRecord" }.count
                )
            }
            .sorted { $0.name < $1.name }
        }
    }

    /// Makes a manual backup; throws when it didn't finish. `checkBackup` checks it against
    /// the plan made after it.
    @MainActor
    static func backUp(coreDataStack: CoreDataStack, backups: AutoBackupManager) async throws -> URL {
        let result = await backups.performManualBackup(viewContext: coreDataStack.viewContext)
        guard case .success(_, let url) = result else {
            throw BackupCheckError("The backup before removing last year didn't finish. Nothing was changed.")
        }
        return url
    }

    /// Checks the backup at `url` holds, by `id`, every record `batches` touch: each shared
    /// original, and any private copy a stopped run left. Throws with the reason otherwise.
    static func checkBackup(
        _ url: URL, holds batches: [Batch], container: NSPersistentCloudKitContainer
    ) async throws {
        let records = batches.flatMap(\.moves).flatMap { move in
            move.sharedRows + [move.existingTwin].compactMap { $0 }
        }
        try await BackupRecordCheck.check(url, holds: records, context: container.newBackgroundContext())
    }

    struct BackupCheckError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Where a run keeps note that it started, so a stopped one is offered again.
    static var inProgressKey: String { CloudKitEnvironment.scoped("ClassroomShareRelease.inProgress") }

    /// A run started and hasn't finished.
    static var stoppedPartway: Bool { UserDefaults.standard.object(forKey: inProgressKey) != nil }
}

nonisolated extension ClassroomShareRelease.Environment {
    /// The app's: CloudKit's own answers, and the sync status for reasons to stop.
    static func live(container: NSPersistentCloudKitContainer) -> Self {
        let privateStore = container.persistentStoreCoordinator.persistentStores.first {
            $0.configurationName == CoreDataStack.privateConfiguration
        }
        let exports = ClassroomShareExportActivity(storeIdentifier: privateStore?.identifier)
        return Self(
            // Both read the mirroring metadata, which can wait on an export: off the main actor.
            shareZones: { ids in
                try await Task.detached {
                    var zones: [NSManagedObjectID: String] = [:]
                    for start in stride(from: 0, to: ids.count, by: 500) {
                        let chunk = Array(ids[start..<min(start + 500, ids.count)])
                        let shares = try container.fetchShares(matching: chunk)
                        for (id, share) in shares { zones[id] = share.recordID.zoneID.zoneName }
                    }
                    return zones
                }.value
            },
            recordIDs: { ids in
                await Task.detached {
                    var records: [NSManagedObjectID: CKRecord.ID] = [:]
                    for id in ids {
                        if let record = container.recordID(for: id) { records[id] = record }
                    }
                    return records
                }.value
            },
            serverRecords: { ids in
                let database = await CloudKitConfigurationService.container.privateCloudDatabase
                return try await CloudKitServerCheck.existing(ids, in: database)
            },
            stopReason: {
                await MainActor.run {
                    let sync = CloudKitSyncStatusService.shared
                    if sync.mirroringDelegateFailed { return "iCloud sync stopped on this Mac." }
                    if let failure = sync.storeHealth.mostSevereFailure, failure.severity == .stopped {
                        return failure.message
                    }
                    return nil
                }
            },
            sleep: { try await Task.sleep(for: $0) },
            patience: .seconds(10 * 60),
            exportIdle: { await exports.waitUntilIdle() },
            exportStarted: { await exports.waitForStart(after: $0) },
            awaitingGone: { savedAwaitingGone() },
            setAwaitingGone: { saveAwaitingGone($0) }
        )
    }

    /// The live `awaitingGone` list: record name, zone name and owner of each.
    private static var awaitingGoneKey: String { CloudKitEnvironment.scoped("ClassroomShareRelease.awaitingGone") }

    private static func savedAwaitingGone() -> [CKRecord.ID] {
        let saved = UserDefaults.standard.array(forKey: awaitingGoneKey) as? [[String]] ?? []
        return saved.compactMap { parts in
            guard parts.count == 3 else { return nil }
            return CKRecord.ID(recordName: parts[0], zoneID: CKRecordZone.ID(zoneName: parts[1], ownerName: parts[2]))
        }
    }

    private static func saveAwaitingGone(_ records: [CKRecord.ID]) {
        guard !records.isEmpty else {
            UserDefaults.standard.removeObject(forKey: awaitingGoneKey)
            return
        }
        let parts = records.map { [$0.recordName, $0.zoneID.zoneName, $0.zoneID.ownerName] }
        UserDefaults.standard.set(parts, forKey: awaitingGoneKey)
    }
}
