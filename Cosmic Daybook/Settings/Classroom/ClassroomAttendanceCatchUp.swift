import CloudKit
import CoreData
import Foundation
import OSLog

/// The Mac's one-time "Add This Year's Attendance to the Share".
///
/// Until 2026-10-05 a mark Siri made while no window was open never went into
/// the classroom share (`SharedStoreOrphanGuard.siriDidSave`), so this school
/// year's attendance can hold marks the assistants never saw. This finds this
/// school year's marks (`ClassroomShareScope`) in the guide's private store that
/// are in no share at all and, once he has read the count and said yes, attaches
/// them through `ClassroomShareAttach`, as any new mark is. A mark already in a
/// share is never touched: `share(_:to:)` on a shared record fails, and on
/// 2026-09-27 it stopped the export for the session. The card goes once there is
/// nothing left to add.
enum ClassroomAttendanceCatchUp {

    private static let logger = Logger.classroomSharing

    /// The step runs on the lead guide's Mac.
    static var isAvailableHere: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// How one run went.
    struct Report: Sendable, Equatable {
        var attached = 0
        var failed = 0
        /// Why it stopped early, as a plain phrase; nil when it ran to the end.
        var stoppedBecause: String?
        /// Nothing more can be added this session; the app has to be reopened.
        var needsRelaunch = false

        /// "Added 12 attendance marks to the share. 2 couldn't be added because
        /// iCloud stopped syncing. Try again later."
        var summary: String {
            var message = "Added \(ClassroomShareSetupReport.describe(attached, "AttendanceRecord")) to the share."
            if failed > 0 {
                message += failed == 1 ? " 1 couldn't be added" : " \(failed.formatted()) couldn't be added"
                message += stoppedBecause.map { " because \($0)." } ?? "."
                message += needsRelaunch ? " Quit and reopen the app, then try again." : " Try again later."
            }
            return message
        }
    }

    /// The card's title for `waiting` marks.
    static func title(waiting: Int) -> String {
        waiting == 1
            ? "1 attendance mark from this school year isn't in the share"
            : "\(waiting.formatted()) attendance marks from this school year aren't in the share"
    }

    // MARK: - Which marks

    /// This school year's attendance in the store with `storeID` that belongs in
    /// the share and is in no share yet. Throws when CloudKit can't say.
    @concurrent
    static func waiting(
        storeID: String,
        container: NSPersistentCloudKitContainer,
        scope: ClassroomShareScope
    ) async throws -> [NSManagedObjectID] {
        let ids = await thisYearsAttendance(storeID: storeID, container: container, scope: scope)
        return try await ClassroomShareAttach.unshared(ids, container: container)
    }

    @concurrent
    private static func thisYearsAttendance(
        storeID: String,
        container: NSPersistentCloudKitContainer,
        scope: ClassroomShareScope
    ) async -> [NSManagedObjectID] {
        let context = container.newBackgroundContext()
        return await context.perform {
            guard let store = context.persistentStoreCoordinator?.persistentStores
                .first(where: { $0.identifier == storeID }) else { return [] }
            let belonging = scope.belongingStudentIDs(in: context, store: store)
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "AttendanceRecord")
            request.resultType = .managedObjectIDResultType
            request.affectedStores = [store]
            request.predicate = scope.predicate(for: "AttendanceRecord", belongingStudentIDs: belonging)
            return (try? context.fetch(request)) ?? []
        }
    }

    // MARK: - On the Mac

    /// Why the step can't run now, or nil. First: a setup found no ready
    /// iCloud account (`shareFilingHold`). Last: on a device that didn't make
    /// the pin, until the notebook has imported since the pin arrived
    /// (`pinWaitBlocker`): before then marks already in the share can read as
    /// outside it, and `share(_:to:)` on them is the 2026-09-28 incident's call.
    static func blocker(
        coreDataStack: CoreDataStack,
        sync: CloudKitSyncStatusService = .shared,
        guardian: SharedStoreOrphanGuard = .shared
    ) -> ClassroomShareError? {
        let context = coreDataStack.viewContext
        if let hold = sync.shareFilingHold { return ClassroomShareError(hold) }
        guard coreDataStack.isCloudKitActive else { return .cloudKitInactive }
        guard let store = coreDataStack.privatePersistentStore else { return .sharedStoreUnavailable }
        guard !CoreDataStack.isSecondaryProcess else { return .anotherCopyOpen }
        guard CDClassroomMembership.currentRole(in: context) == .leadGuide else { return .assistantCannotCreateShare }
        guard !FirstDownloadGate.isPending() else { return .firstDownloadPending }
        guard !sync.mirroringDelegateFailed else { return .mirroringStopped }
        guard let zone = CDClassroomMembership.pinnedZoneName(in: context) else { return .notSetUp }
        return ClassroomSharingService.pinWaitBlocker(
            pinnedZone: zone, context: context, notebookStoreID: store.identifier, guardian: guardian
        )
    }

    /// How many marks the card offers to add; nil when the step can't run here
    /// now or CloudKit can't say.
    static func count(coreDataStack: CoreDataStack) async -> Int? {
        guard isAvailableHere, blocker(coreDataStack: coreDataStack) == nil,
              let store = coreDataStack.privatePersistentStore else { return nil }
        let scope = ClassroomShareScope()
        return try? await waiting(storeID: store.identifier, container: coreDataStack.container, scope: scope).count
    }

    /// Attaches them, holding the attach lock so no other pass shares the
    /// same marks meanwhile. Throws `ClassroomShareError` when it can't start,
    /// including when an earlier pass is stuck holding the lock (waiting behind
    /// it left the card spinning until relaunch).
    static func run(coreDataStack: CoreDataStack) async throws -> Report {
        let report = try await ClassroomShareAttachLock.shared.runUnlessStuck { () async throws -> Report in
            if let blocker = blocker(coreDataStack: coreDataStack) { throw blocker }
            guard let store = coreDataStack.privatePersistentStore else {
                throw ClassroomShareError.sharedStoreUnavailable
            }
            let container = coreDataStack.container
            let share = try await ClassroomShareAttach.classroomShare(
                inStoreWithIdentifier: store.identifier, container: container, pinContext: coreDataStack.viewContext
            )
            guard let share else { throw ClassroomShareError.shareStillSyncing }
            let ids = try await waiting(storeID: store.identifier, container: container, scope: ClassroomShareScope())
            logger.notice("Adding this year's attendance to the share: \(ids.count, privacy: .public) mark(s)")
            let outcome = await ClassroomShareAttach.attach(ids, to: share, container: container)
            if outcome.mirroringDelegateDied {
                // The store the attach ran against: the private store's delegate died.
                CloudKitSyncStatusService.shared.markMirroringStopped(byAttachToStoreWithIdentifier: store.identifier)
            }
            let report = Report(
                attached: outcome.attached, failed: outcome.failed.count,
                stoppedBecause: outcome.stoppedBecause, needsRelaunch: outcome.mirroringDelegateDied
            )
            logger.notice("This year's attendance: attached \(report.attached), failed \(report.failed)")
            return report
        }
        guard let report else { throw ClassroomShareError.earlierAttachStillRunning }
        return report
    }
}
