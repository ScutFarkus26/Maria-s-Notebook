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

    /// Share zones that exist on the server in the guide's private database.
    /// The local store only knows what it has imported, so this is the only
    /// reliable answer to "is there a share already?". Throws when the server
    /// can't be reached — callers treat that as unknown and refuse.
    static func fetchServerShareZoneNames() async throws -> Set<String> {
        let zones = try await CloudKitConfigurationService.container.privateCloudDatabase.allRecordZones()
        return Set(zones.map(\.zoneID.zoneName).filter { $0.hasPrefix(ClassroomShareScope.shareZonePrefix) })
    }

    // MARK: - Set up

    /// Creates the classroom share and puts this school year's students and
    /// attendance (`ClassroomShareScope`), and every school-calendar day, day
    /// lock, front-desk email record, Restock record and name in the classroom's
    /// list (`ClassroomNames`) into it, then pins its zone.
    ///
    /// Run once, on the Mac, after the notebook is fully downloaded. Refuses
    /// unless this device is the lead guide's, the first download has
    /// finished, and the server holds no share zone at all. Run again once the
    /// share exists (the server holding that one zone and no other), it adds
    /// whatever of those types is in no share yet — the way to finish a setup
    /// that stopped partway ("Add them to the share"). It never moves a record
    /// out of another share, and on a device that didn't make the pin it waits
    /// until the notebook has imported since the pin arrived (`resumePin`).
    ///
    /// Holds `ClassroomShareAttachLock` throughout, so the orphan guard's pass
    /// waits rather than sharing the same records beside it. Refuses, rather
    /// than wait, while a guard pass that outlived its time limit holds the
    /// lock: its call to CloudKit may never return.
    func setUpClassroomSharing(coreDataStack: CoreDataStack) async throws -> ClassroomShareSetupReport {
        let report = try await ClassroomShareAttachLock.shared.runUnlessStuck {
            try await self.setUpHoldingTheLock(coreDataStack: coreDataStack)
        }
        guard let report else { throw ClassroomShareError.earlierAttachStillRunning }
        return report
    }

    private func setUpHoldingTheLock(coreDataStack: CoreDataStack) async throws -> ClassroomShareSetupReport {
        let (store, pinned) = try await setupPreflight(coreDataStack: coreDataStack)
        let viewContext = coreDataStack.viewContext
        if let pinned { try resumePin(pinned, notebookStoreID: store.identifier, in: viewContext) }
        // What this device was holding for the share, as it found it.
        // Everything of these types is shared below, so these go, except any
        // the attach failed on; anything added meanwhile stays.
        let waitingAtStart = SharedStoreOrphanGuard.shared.pendingEntries

        // This school year's records only (`ClassroomShareScope`): earlier years stay private.
        let byEntity = await Self.classroomRecordIDs(in: store, container: container, scope: ClassroomShareScope())
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
        var outcome = await ClassroomShareAttach.attach(waiting, to: share, container: container)
        // Records created while that ran — before the pin was saved the guard
        // had no share to put them in — get a second pass.
        if outcome.stoppedBecause == nil {
            let latest = await Self.classroomRecordIDs(in: store, container: container, scope: ClassroomShareScope())
            let again = ClassroomShareSetupReport.orderedEntityNames.flatMap { latest[$0] ?? [] }
            let stragglers = try await ClassroomShareAttach.unshared(again, container: container)
                .filter { !Set(outcome.failed).contains($0) }
            if !stragglers.isEmpty {
                let second = await ClassroomShareAttach.attach(stragglers, to: share, container: container)
                outcome.attached += second.attached
                outcome.failed += second.failed
                outcome.stoppedBecause = second.stoppedBecause
                outcome.mirroringDelegateDied = second.mirroringDelegateDied
            }
        }
        if outcome.mirroringDelegateDied {
            // The store the attach ran against: the private store's delegate died.
            CloudKitSyncStatusService.shared.markMirroringStopped(byAttachToStoreWithIdentifier: store.identifier)
        }
        let failed = Set(outcome.failed.map { $0.uriRepresentation().absoluteString })
        // Before this school year's start reaches the device, setup goes by the
        // September 1 fallback and can skip this year's first days as last
        // year's; the guard keeps those waiting (#31), so the list stays as it
        // is. The guard's next pass finds what setup attached already shared
        // and drops it then.
        if !ClassroomShareScope().isProvisional {
            SharedStoreOrphanGuard.shared.forget(waitingAtStart, except: failed)
        }

        let contents = await Self.shareContents(coreDataStack: coreDataStack)
        let report = ClassroomShareSetupReport(
            created: pinned == nil,
            attached: outcome.attached + (pinned == nil ? 1 : 0),
            failed: outcome.failed.count,
            stoppedBecause: outcome.stoppedBecause,
            needsRelaunch: outcome.mirroringDelegateDied,
            contents: contents
        )
        Self.setupLogger.notice("Classroom setup finished: \(report.logLine, privacy: .public)")
        return report
    }

    /// Why setup can't run on this device right now, before asking iCloud
    /// anything, or nil. First: a setup found no ready iCloud account
    /// (`shareFilingHold`), which only iCloud becoming ready, or with none
    /// signed in, reopening the notebook, fixes.
    static func setupBlocker(
        coreDataStack: CoreDataStack, sync: CloudKitSyncStatusService = .shared
    ) -> ClassroomShareError? {
        if let hold = sync.shareFilingHold { return ClassroomShareError(hold) }
        guard coreDataStack.isCloudKitActive else { return .cloudKitInactive }
        guard coreDataStack.privatePersistentStore != nil else { return .sharedStoreUnavailable }
        // The attach lock is this process's only: a second copy of the app
        // could share the same records beside the first.
        guard !CoreDataStack.isSecondaryProcess else { return .anotherCopyOpen }
        guard CDClassroomMembership.currentRole(in: coreDataStack.viewContext) == .leadGuide else {
            return .assistantCannotCreateShare
        }
        guard !FirstDownloadGate.isPending() else { return .firstDownloadPending }
        guard !sync.mirroringDelegateFailed else { return .mirroringStopped }
        return nil
    }

    /// Refuses unless setup is safe right now; returns the private store and
    /// the pinned share when one already exists (a resumed setup).
    private func setupPreflight(coreDataStack: CoreDataStack) async throws -> (NSPersistentStore, CKShare?) {
        if let blocker = Self.setupBlocker(coreDataStack: coreDataStack) { throw blocker }
        guard let store = coreDataStack.privatePersistentStore else { throw ClassroomShareError.sharedStoreUnavailable }
        let viewContext = coreDataStack.viewContext

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
        let zone = share.recordID.zoneID.zoneName
        Self.setupLogger.notice("Created the classroom share in zone \(zone, privacy: .public)")
        // Before the pin is saved: the save sets off a guard pass, which must
        // know this pin is this device's own (`forgetWhatSetupElsewhereTook`).
        SharedStoreOrphanGuard.shared.notePinMadeHere(zone: zone)
        ClassroomRepository(context: viewContext).pinClassroom(
            zoneName: zone,
            role: .leadGuide,
            ownerIdentity: share.owner.userIdentity.userRecordID?.recordName ?? "self"
        )
        try savePin(in: viewContext)
        updateShareState(share)
        return share
    }

    /// A setup resumed here, with the share already pinned. A pin whose save
    /// failed last time is saved before anything else. Then, when the pin was
    /// made on another device or before this device noted pins (a build
    /// before 2026-10-06), setup waits for an import into the notebook that
    /// began after this device saw the pin, as the orphan guard does
    /// (`pinWaitBlocker`): until then records already in the share can read as
    /// outside it (`fetchShares` reads only what has downloaded), and
    /// `share(_:to:)` on them is the call behind the 2026-09-28 incident. The
    /// pin is never noted as made here: that ended the guard's wait too (bug
    /// hunt 2026-10-09, #1). Only `createPinnedShare` notes one.
    private func resumePin(
        _ pinned: CKShare, notebookStoreID: String, in viewContext: NSManagedObjectContext
    ) throws {
        if CDClassroomMembership.current(in: viewContext)?.hasChanges == true {
            try savePin(in: viewContext)
        }
        if let wait = Self.pinWaitBlocker(
            pinnedZone: pinned.recordID.zoneID.zoneName, context: viewContext, notebookStoreID: notebookStoreID
        ) {
            Self.setupLogger.notice("Classroom setup: waiting for an import after the pin before adding records")
            throw wait
        }
    }

    /// `.classStillDownloading` while this device must wait for an import into
    /// the notebook since it first saw the pin in `pinnedZone`
    /// (`mustWaitForImportAfterPin`, which notes a pin it hasn't seen), else
    /// nil. Every path that files this device's existing records into the
    /// share asks: a resumed Set Up Classroom Sharing and the attendance
    /// catch-up (the orphan guard waits the same way).
    static func pinWaitBlocker(
        pinnedZone: String,
        context: NSManagedObjectContext,
        notebookStoreID: String,
        guardian: SharedStoreOrphanGuard = .shared
    ) -> ClassroomShareError? {
        let pin = CDClassroomMembership.current(in: context)
        let mustWait = guardian.mustWaitForImportAfterPin(
            pinnedZone: pinnedZone, pinnedAt: pin?.modifiedAt ?? pin?.joinedAt, notebookStoreID: notebookStoreID
        )
        return mustWait ? .classStillDownloading : nil
    }

    /// Saves the pin. Without it the share would be one no pin names: nothing
    /// could be filed into it, and the next launch would refuse to set up
    /// again. A failed save leaves the pin pending in the view context, so
    /// running setup again while the app stays open saves it then.
    private func savePin(in viewContext: NSManagedObjectContext) throws {
        guard ClassroomRepository(context: viewContext).save(reason: "Pin classroom share") else {
            Self.setupLogger.error("Couldn't save the classroom share's pin; setup stopped")
            throw ClassroomShareError.pinNotSaved
        }
    }

    // MARK: - Invitations

    /// The share to invite into, checked first: it must be the pinned share
    /// and hold students, or an assistant would join an empty classroom (the
    /// 2026-09-28 failure). Returns what it holds, for the sheet to show.
    func shareForInvitations(coreDataStack: CoreDataStack) async throws -> (CKShare, ClassroomShareContents) {
        guard let share = try fetchExistingShare() else { throw ClassroomShareError.notSetUp }
        let contents = try Self.invitable(await Self.shareContents(coreDataStack: coreDataStack))
        return (share, contents)
    }

    /// What the share holds, if an assistant can be invited into it: it holds
    /// students. When CloudKit couldn't say (nil), that's "couldn't check",
    /// never "no students".
    static func invitable(_ contents: ClassroomShareContents?) throws -> ClassroomShareContents {
        guard let contents else { throw ClassroomShareError.shareContentsUnknown }
        guard (contents.inShare["Student"] ?? 0) > 0 else { throw ClassroomShareError.shareHasNoStudents }
        return contents
    }
}

/// What one run of Set Up Classroom Sharing did.
nonisolated struct ClassroomShareSetupReport: Sendable {
    /// Every classroom-share type (`CoreDataStack.sharedEntityNames`), in the
    /// order setup takes them and the summary names them. Students first: the
    /// first record becomes the share's seed. Built from the share's own list,
    /// so a type added to the share is set up and counted too, after these.
    static let orderedEntityNames: [String] = {
        let order = [
            "Student", "AttendanceRecord", "NonSchoolDay", "SchoolDayOverride", "AttendanceDayLock",
            "AttendanceEmailSend", "AttendanceEmailSettings", "Supply", "SupplyTransaction", "OrderItem",
            "ClassroomPerson"
        ]
        let shared = CoreDataStack.sharedEntityNames
        return order.filter(shared.contains) + shared.subtracting(order).sorted()
    }()

    let created: Bool
    let attached: Int
    let failed: Int
    /// Why the run stopped early, as a plain phrase ("iCloud stopped
    /// syncing"); nil when it ran to the end.
    let stoppedBecause: String?
    /// Nothing more can be added this session; the app has to be reopened.
    var needsRelaunch = false
    let contents: ClassroomShareContents?

    /// The line Settings shows after a run: "Classroom shared. 214 items
    /// added. 3 couldn't be added because iCloud stopped syncing. Quit and
    /// reopen the app, then try again."
    var summary: String {
        var message = created ? "Classroom shared. " : ""
        message += attached == 1 ? "1 item added." : "\(attached.formatted()) items added."
        if let contents { message += " The share holds \(contents.summary)." }
        if failed > 0 {
            message += failed == 1 ? " 1 couldn't be added" : " \(failed.formatted()) couldn't be added"
            message += stoppedBecause.map { " because \($0)." } ?? "."
            message += needsRelaunch ? " Quit and reopen the app, then try again." : " Try again later."
        }
        return message
    }

    var logLine: String {
        "created=\(created) attached=\(attached) failed=\(failed) stopped=\(stoppedBecause ?? "no") " +
            "outside=\(contents?.outside ?? -1)"
    }

    /// Each share type's name for one record and for several.
    private static let recordNames: [String: (one: String, many: String)] = [
        "Student": ("1 student", "students"),
        "AttendanceRecord": ("1 attendance mark", "attendance marks"),
        "NonSchoolDay": ("1 day off", "days off"),
        "SchoolDayOverride": ("1 extra school day", "extra school days"),
        "AttendanceDayLock": ("1 locked day", "locked days"),
        "AttendanceEmailSend": ("1 front-desk email", "front-desk emails"),
        "AttendanceEmailSettings": ("the front-desk email settings", "email settings"),
        "Supply": ("1 staple", "staples"),
        "SupplyTransaction": ("1 restock history entry", "restock history entries"),
        "OrderItem": ("1 restock item", "restock items"),
        "ClassroomPerson": ("1 person's name", "people's names")
    ]

    static func describe(_ count: Int, _ entity: String) -> String {
        guard let names = recordNames[entity] else {
            // A type added to the share later: never its model name on screen.
            return count == 1 ? "1 other item" : "\(count.formatted()) other items"
        }
        return count == 1 ? names.one : "\(count.formatted()) \(names.many)"
    }
}
