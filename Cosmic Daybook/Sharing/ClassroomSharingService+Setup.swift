import Foundation
@preconcurrency import CoreData
import CloudKit
import OSLog

// MARK: - Setting up the one classroom share
//
// The classroom share is created once, on purpose, by the lead guide pressing
// Settings → Classroom → Set Up Classroom Sharing. Nothing creates one on its
// own any more: launch-time auto-create and the orphan guard's auto-create
// each minted share zones whenever the local store merely looked unshared
// (after a reset, on a new device), which is how Development came to hold 13.

extension ClassroomSharingService {

    private static let setupLogger = Logger.classroomSharing

    /// Zone-name prefix `NSPersistentCloudKitContainer` gives the zones that
    /// back a `CKShare` (`com.apple.coredata.cloudkit.share.<UUID>`).
    static let shareZoneNamePrefix = "com.apple.coredata.cloudkit.share."

    /// Share zones that exist on the server in the guide's private database.
    /// The local store only knows what it has imported, so this is the only
    /// reliable answer to "is there a share already?". Throws when the server
    /// can't be reached — callers treat that as unknown and refuse.
    static func fetchServerShareZoneNames() async throws -> Set<String> {
        let zones = try await CloudKitConfigurationService.container.privateCloudDatabase.allRecordZones()
        return Set(zones.map(\.zoneID.zoneName).filter { $0.hasPrefix(shareZoneNamePrefix) })
    }

    // MARK: - Set up

    /// Creates the classroom share and puts every student, attendance record,
    /// school-calendar day and day lock into it, then pins its zone.
    ///
    /// Run once, on the Mac, after the notebook is fully downloaded. Refuses
    /// unless this device is the lead guide's, the first download has
    /// finished, and the server holds no share zone at all. Run again once the
    /// share exists (the server holding that one zone and no other), it adds
    /// whatever of those types is in no share yet — the way to finish a setup
    /// that stopped partway. It never moves a record out of another share.
    func setUpClassroomSharing(coreDataStack: CoreDataStack) async throws -> ClassroomShareSetupReport {
        let (store, pinned) = try await setupPreflight(coreDataStack: coreDataStack)
        let viewContext = coreDataStack.viewContext

        let byEntity = await Self.classroomRecordIDs(in: store, container: container)
        let all = ClassroomShareSetupReport.orderedEntityNames.flatMap { byEntity[$0] ?? [] }
        var waiting = try await ClassroomShareAttach.unshared(all, container: container)

        let share: CKShare
        if let pinned {
            share = pinned
        } else {
            // A student first, so the share's first record is one the
            // assistant needs.
            guard let seed = waiting.first else { throw ClassroomShareError.noSeedRecordAvailable }
            share = try await createPinnedShare(seed: seed, in: viewContext)
            waiting.removeFirst()
        }

        Self.setupLogger.notice("Classroom setup: attaching \(waiting.count, privacy: .public) record(s)")
        let outcome = await ClassroomShareAttach.attach(waiting, to: share, container: container)
        if outcome.mirroringDelegateDied {
            CloudKitSyncStatusService.shared.mirroringDelegateFailed = true
        }
        // Everything this device created before the share existed is covered.
        SharedStoreOrphanGuard.shared.clearPending()

        let contents = await Self.shareContents(coreDataStack: coreDataStack)
        let report = ClassroomShareSetupReport(
            created: pinned == nil,
            attached: outcome.attached + (pinned == nil ? 1 : 0),
            failed: outcome.failed.count,
            stoppedBecause: outcome.stoppedBecause,
            contents: contents
        )
        Self.setupLogger.notice("Classroom setup finished: \(report.logLine, privacy: .public)")
        return report
    }

    /// Refuses unless setup is safe right now; returns the private store and
    /// the pinned share when one already exists (a resumed setup).
    private func setupPreflight(coreDataStack: CoreDataStack) async throws -> (NSPersistentStore, CKShare?) {
        guard coreDataStack.isCloudKitActive else { throw ClassroomShareError.cloudKitInactive }
        guard let store = coreDataStack.privatePersistentStore else { throw ClassroomShareError.sharedStoreUnavailable }
        let viewContext = coreDataStack.viewContext
        guard CDClassroomMembership.currentRole(in: viewContext) == .leadGuide else {
            throw ClassroomShareError.assistantCannotCreateShare
        }
        guard !FirstDownloadGate.isPending() else { throw ClassroomShareError.firstDownloadPending }
        guard !CloudKitSyncStatusService.shared.mirroringDelegateFailed else {
            throw ClassroomShareError.mirroringStopped
        }

        let serverZones = try await Self.fetchServerShareZoneNames()
        let localShares = try container.fetchShares(in: store)
        let pinned = CDClassroomMembership.classroomShare(among: localShares, in: viewContext)
        if let pinned {
            guard serverZones == [pinned.recordID.zoneID.zoneName] else {
                throw ClassroomShareError.otherShareZonesExist(serverZones.count)
            }
        } else if let zone = CDClassroomMembership.pinnedZoneName(in: viewContext), serverZones.contains(zone) {
            throw ClassroomShareError.shareStillSyncing
        } else if !serverZones.isEmpty || !localShares.isEmpty {
            throw ClassroomShareError.otherShareZonesExist(max(serverZones.count, localShares.count))
        }
        return (store, pinned)
    }

    /// Creates the share seeded with `seed`, pins its zone and publishes it.
    private func createPinnedShare(
        seed: NSManagedObjectID, in viewContext: NSManagedObjectContext
    ) async throws -> CKShare {
        let share: CKShare
        do {
            share = try await ClassroomShareAttach.createShareOffMain(seedID: seed, container: container)
        } catch {
            let ns = error as NSError
            let detail = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
            Self.setupLogger.error("Classroom share creation failed: \(detail, privacy: .public)")
            throw error
        }
        let repo = ClassroomRepository(context: viewContext)
        repo.pinClassroom(
            zoneName: share.recordID.zoneID.zoneName,
            role: .leadGuide,
            ownerIdentity: share.owner.userIdentity.userRecordID?.recordName ?? "self"
        )
        _ = repo.save(reason: "Pin classroom share")
        let zone = share.recordID.zoneID.zoneName
        Self.setupLogger.notice("Created the classroom share in zone \(zone, privacy: .public)")
        updateShareState(share)
        return share
    }

    // MARK: - Invitations

    /// The share to invite into, checked first: it must be the pinned share
    /// and hold students, or an assistant would join an empty classroom (the
    /// 2026-09-28 failure). Returns what it holds, for the sheet to show.
    func shareForInvitations(coreDataStack: CoreDataStack) async throws -> (CKShare, ClassroomShareContents) {
        guard let share = try fetchExistingShare() else { throw ClassroomShareError.notSetUp }
        let contents = await Self.shareContents(coreDataStack: coreDataStack)
        guard (contents?.inShare["Student"] ?? 0) > 0 else { throw ClassroomShareError.shareHasNoStudents }
        return (share, contents ?? ClassroomShareContents())
    }

    // MARK: - What the share holds

    /// Per type, how many of the lead guide's classroom records are in the
    /// pinned share and how many exist. Read-only: the difference is shown in
    /// Settings, never fixed on its own. Nil when there is nothing to read or
    /// CloudKit can't say.
    static func shareContents(coreDataStack: CoreDataStack) async -> ClassroomShareContents? {
        guard coreDataStack.isCloudKitActive, let store = coreDataStack.privatePersistentStore else { return nil }
        let pinnedZone = CDClassroomMembership.pinnedZoneName(in: coreDataStack.viewContext)
        let byEntity = await classroomRecordIDs(in: store, container: coreDataStack.container)
        return await countInShare(byEntity, zone: pinnedZone, container: coreDataStack.container)
    }

    @concurrent
    private static func countInShare(
        _ byEntity: [String: [NSManagedObjectID]],
        zone: String?,
        container: NSPersistentCloudKitContainer
    ) async -> ClassroomShareContents? {
        var contents = ClassroomShareContents()
        for (entity, ids) in byEntity {
            contents.total[entity] = ids.count
            guard let zone, !ids.isEmpty else {
                contents.inShare[entity] = 0
                continue
            }
            guard let shares = try? container.fetchShares(matching: ids) else { return nil }
            contents.inShare[entity] = shares.values.filter { $0.recordID.zoneID.zoneName == zone }.count
        }
        return contents
    }

    /// Object IDs of every record of the classroom share's types in `store`,
    /// by entity, read on a background context without faulting any row.
    @concurrent
    static func classroomRecordIDs(
        in store: NSPersistentStore,
        container: NSPersistentCloudKitContainer
    ) async -> [String: [NSManagedObjectID]] {
        let context = container.newBackgroundContext()
        return await context.perform {
            var result: [String: [NSManagedObjectID]] = [:]
            for entity in ClassroomShareSetupReport.orderedEntityNames {
                let request = NSFetchRequest<NSManagedObjectID>(entityName: entity)
                request.affectedStores = [store]
                request.resultType = .managedObjectIDResultType
                result[entity] = (try? context.fetch(request)) ?? []
            }
            return result
        }
    }
}

/// How many records of each classroom-share type are in the share, of how many.
nonisolated struct ClassroomShareContents: Sendable, Equatable {
    var inShare: [String: Int] = [:]
    var total: [String: Int] = [:]

    /// Records of the share's types that aren't in it.
    var outside: Int {
        total.reduce(0) { $0 + max(0, $1.value - (inShare[$1.key] ?? 0)) }
    }

    /// "40 students, 3,908 attendance records, 16 school-calendar days, 2 locked days".
    var summary: String {
        ClassroomShareSetupReport.orderedEntityNames.compactMap { entity in
            let count = inShare[entity] ?? 0
            guard count > 0 || entity == "Student" else { return nil }
            return ClassroomShareSetupReport.describe(count, entity)
        }
        .joined(separator: ", ")
    }
}

/// What one run of Set Up Classroom Sharing did.
nonisolated struct ClassroomShareSetupReport: Sendable {
    /// Students first: the first record becomes the share's seed.
    static let orderedEntityNames = [
        "Student", "AttendanceRecord", "NonSchoolDay", "SchoolDayOverride", "AttendanceDayLock"
    ]

    let created: Bool
    let attached: Int
    let failed: Int
    let stoppedBecause: String?
    let contents: ClassroomShareContents?

    var logLine: String {
        "created=\(created) attached=\(attached) failed=\(failed) stopped=\(stoppedBecause ?? "no") " +
            "outside=\(contents?.outside ?? -1)"
    }

    static func describe(_ count: Int, _ entity: String) -> String {
        let number = count.formatted()
        switch entity {
        case "Student": return count == 1 ? "1 student" : "\(number) students"
        case "AttendanceRecord": return count == 1 ? "1 attendance record" : "\(number) attendance records"
        case "NonSchoolDay": return count == 1 ? "1 day off" : "\(number) days off"
        case "SchoolDayOverride": return count == 1 ? "1 extra school day" : "\(number) extra school days"
        case "AttendanceDayLock": return count == 1 ? "1 locked day" : "\(number) locked days"
        default: return "\(number) \(entity)"
        }
    }
}

/// Why sharing couldn't be set up or opened.
enum ClassroomShareError: LocalizedError {
    case cloudKitInactive
    case sharedStoreUnavailable
    case assistantCannotCreateShare
    case noSeedRecordAvailable
    case shareStillSyncing
    case firstDownloadPending
    case mirroringStopped
    case otherShareZonesExist(Int)
    case notSetUp
    case shareHasNoStudents

    var errorDescription: String? {
        switch self {
        case .cloudKitInactive:
            return "iCloud sync isn't active. Turn on iCloud for Cosmic Daybook in System Settings and try again."
        case .sharedStoreUnavailable:
            return "Shared classroom storage isn't available on this device."
        case .assistantCannotCreateShare:
            return "Only the lead guide can share the classroom."
        case .noSeedRecordAvailable:
            return "Add a student before sharing the classroom."
        case .shareStillSyncing:
            return "This classroom's share is still coming down from iCloud. Wait for sync to finish, then try again."
        case .firstDownloadPending:
            return "The notebook is still downloading from iCloud. Set up sharing once it has finished."
        case .mirroringStopped:
            return "iCloud sync stopped working this session. Quit and reopen Cosmic Daybook, then try again."
        case .otherShareZonesExist(let count):
            return "iCloud already holds \(count) other classroom share(s) for this notebook. " +
                "Sharing is set up once, into an empty notebook, so nothing was changed."
        case .notSetUp:
            return "Classroom sharing isn't set up yet. Choose Set Up Classroom Sharing first."
        case .shareHasNoStudents:
            return "The classroom share holds no students yet, so an assistant would see an empty class. " +
                "Nothing was sent."
        }
    }
}
