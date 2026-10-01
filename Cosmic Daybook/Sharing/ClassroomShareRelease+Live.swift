import CloudKit
import CoreData
import Foundation
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
        if !coreDataStack.isCloudKitActive { return "iCloud sync is off." }
        if CDClassroomMembership.currentRole(in: context) != .leadGuide {
            return "Only the lead guide's Mac can change what the share holds."
        }
        if isRestoring { return "A restore is running." }
        if FirstDownloadGate.isPending() { return "This Mac is still downloading the notebook from iCloud." }
        if let reason = syncBlocker() { return reason }
        if CDClassroomMembership.pinnedZoneName(in: context) == nil { return "There's no classroom share." }
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
            return "Another copy of Cosmic Daybook is running (it may be hidden, opened for Claude). Quit it first."
        }
        #endif
        return nil
    }

    /// Sync must be healthy, online and caught up: the release waits on iCloud at every step.
    @MainActor
    static func syncBlocker() -> String? {
        let sync = CloudKitSyncStatusService.shared
        if sync.mirroringDelegateFailed { return "iCloud sync has stopped on this Mac. Quit and reopen first." }
        if let failure = sync.storeHealth.mostSevereFailure, failure.severity == .stopped { return failure.message }
        if !sync.isNetworkAvailable { return "This Mac is offline." }
        if sync.pendingLocalChanges > 0 {
            return "\(sync.pendingLocalChanges) change(s) are still waiting to go to iCloud. Try again in a minute."
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

    /// Makes a manual backup and checks it: it must read back whole and hold every student
    /// and attendance record the notebook has (every distinct `id`: a stopped run's two
    /// copies of one record count once). Throws with the reason otherwise.
    @MainActor
    static func verifiedBackup(
        coreDataStack: CoreDataStack, backups: AutoBackupManager
    ) async throws -> URL {
        let result = await backups.performManualBackup(viewContext: coreDataStack.viewContext)
        guard case .success(_, let url) = result else {
            throw BackupCheckError("The backup before removing last year didn't finish.")
        }
        let counts = try await backupCounts(at: url)
        let context = coreDataStack.viewContext
        for entity in ["Student", "AttendanceRecord"] {
            let request = NSFetchRequest<NSDictionary>(entityName: entity)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["id"]
            request.returnsDistinctResults = true
            guard let rows = try? context.fetch(request) else {
                throw BackupCheckError("Couldn't count the notebook's \(entity) records. Nothing was changed.")
            }
            let here = rows.count
            guard (counts[entity] ?? 0) >= here else {
                throw BackupCheckError(
                    "The backup holds \(counts[entity] ?? 0) \(entity) records, the notebook \(here). "
                        + "Nothing was changed."
                )
            }
        }
        return url
    }

    @concurrent
    private static func backupCounts(at url: URL) async throws -> [String: Int] {
        try BackupReader.verifyStructure(at: url).manifest.entityCounts
    }

    struct BackupCheckError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Where a run keeps note that it started, so a stopped one is offered again.
    static var inProgressKey: String { CloudKitEnvironment.scoped("ClassroomShareRelease.inProgress") }
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
            exportStarted: { await exports.waitForStart(after: $0) }
        )
    }
}
