import Foundation
@preconcurrency import CoreData
import OSLog

/// Processes persistent history transactions from CloudKit remote changes.
/// Serialized via Swift actor to prevent concurrent history processing.
///
/// Responsibilities:
/// 1. Fetch each store's remote history transactions since that store's last
///    processed position (see `PersistentHistoryProcessor+StoreHistory.swift`)
/// 2. Detect remote inserts and trigger DeduplicationCoordinator
/// 3. Persist each store's position to UserDefaults
/// 4. Occasionally purge months-old history that the CloudKit mirroring
///    delegate has provably finished exporting (see `purgeOldHistory`)
///
/// CDNote: The view context has `automaticallyMergesChangesFromParent = true`,
/// which handles merging remote changes automatically. This processor only
/// inspects history to detect inserts for deduplication — it does NOT call
/// `mergeChanges(fromContextDidSave:)` (that would be redundant).
actor PersistentHistoryProcessor {

    // MARK: - Constants

    static let transactionAuthor = "CosmicDaybook"
    nonisolated static let logger = Logger.historyProcessor

    /// Entities whose remote changes must invalidate the school-day caches.
    /// `CoreDataStack` used to post `.schoolDayDataDidChange` on *every*
    /// remote-change notification (its entity filter read object-ID keys that
    /// notification never carries), which re-keyed every drop zone and day
    /// column for the whole of a CloudKit import. History transactions do
    /// know which entities changed, so the post happens here instead.
    nonisolated private static let schoolDayEntityNames: Set<String> = ["NonSchoolDay", "SchoolDayOverride"]

    /// Entities the Upcoming pane, the progress map and the attendance roll
    /// read. A batch that touched any of them posts `.presentationDataDidChange`
    /// with the touched names under `changedEntityNamesKey`, so those screens
    /// no longer keep whole tables registered through `@FetchRequest` just to
    /// notice a remote change (see `View.onPresentationDataChange`).
    nonisolated static let presentationEntityNames: Set<String> = [
        "LessonAssignment", "Lesson", "Student", "WorkModel",
        "AttendanceRecord", "AttendanceDayLock", "AttendanceEmailSend", "AttendanceEmailSettings"
    ]

    /// `userInfo` key of `.presentationDataDidChange`: the `Set<String>` of
    /// `presentationEntityNames` the batch touched.
    nonisolated static let changedEntityNamesKey = "changedEntityNames"

    // MARK: - State

    private let container: NSPersistentCloudKitContainer
    /// Where the cursor is kept and the export and purge dates are read:
    /// `.standard` in the app, a suite of its own in a test, since the test
    /// host's own processor keeps its cursor under the same key.
    private let defaults: UserDefaults

    /// How far each store's history has been read, keyed by
    /// `NSPersistentStore.identifier`. One token cannot stand for both
    /// stores: a transaction's token holds a position in its own store only.
    private var positions: [String: NSPersistentHistoryToken]

    /// A pass is in flight. `.NSPersistentStoreRemoteChange` arrives in bursts during
    /// a CloudKit sync — one per imported batch — and each notification used to queue
    /// its own pass: a fresh background context plus a history fetch against SQLite,
    /// even though the first pass had already consumed the transactions the rest would
    /// look for. These two flags collapse a burst into at most one follow-up pass.
    private var isProcessing = false
    private var needsAnotherPass = false

    // MARK: - Init

    init(container: NSPersistentCloudKitContainer, defaults: UserDefaults = .standard) {
        self.container = container
        self.defaults = defaults
        self.positions = Self.loadPositions(from: defaults)
        // The single token kept before per-store positions covered one store,
        // and nothing records which. Without it the first pass reads each
        // store from its beginning, exactly as on a first launch.
        defaults.removeObject(forKey: UserDefaultsKeys.persistentHistoryLastToken)
    }

    // MARK: - Public: Process Remote Changes

    /// Process new persistent history transactions since each store's position.
    /// Called when `.NSPersistentStoreRemoteChange` fires.
    ///
    /// Callers that arrive while a pass is running are folded into a single follow-up
    /// pass rather than each running their own. Nothing is dropped: the follow-up reads
    /// from the same positions, so it still sees every transaction written in the meantime.
    func processRemoteChanges() async {
        guard !isProcessing else {
            needsAnotherPass = true
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        repeat {
            needsAnotherPass = false
            await performProcessingPass()
        } while needsAnotherPass
    }

    private func performProcessingPass() async {
        let context = container.newBackgroundContext()
        context.transactionAuthor = Self.transactionAuthor
        let currentPositions = positions
        let author = Self.transactionAuthor

        let pass: HistoryPass = await context.perform {
            Self.readHistory(after: currentPositions, author: author, in: context)
        }

        // Only a moved cursor is worth a defaults write. A store whose read
        // failed has already lost its position, so it restarts from its
        // beginning next time; the other stores keep what they read.
        if pass.positions != positions {
            positions = pass.positions
            Self.savePositions(pass.positions, to: defaults)
        }

        switch pass.outcome {
        case .noTransactions:
            break

        case let .processed(remoteCount, totalCount, insertedEntityNames, changedEntityNames):
            Self.react(
                remoteCount: remoteCount, totalCount: totalCount,
                insertedEntityNames: insertedEntityNames, changedEntityNames: changedEntityNames
            )

        case .failed:
            // Fail open: we don't know what changed, so assume every watched
            // entity might have, and ask for the full dedup sweep the import
            // event no longer triggers.
            Self.postEntityNotifications(for: Self.schoolDayEntityNames.union(Self.presentationEntityNames))
            Self.requestFullDeduplication()
        }
    }

    /// What a processed batch triggers: the school-day cache invalidation and
    /// the scoped dedup report.
    nonisolated private static func react(
        remoteCount: Int,
        totalCount: Int,
        insertedEntityNames: Set<String>,
        changedEntityNames: Set<String>
    ) {
        let inserted: String = insertedEntityNames.sorted().joined(separator: ",")
        logger.debug(
            "Processed \(totalCount) transaction(s), \(remoteCount) remote, inserts: \(inserted, privacy: .public)"
        )

        postEntityNotifications(for: changedEntityNames)

        // Report every remote batch, inserts or not: a duplicate is two rows
        // for one record, so only the inserted entities need a pass, and an
        // empty report tells the coordinator there is nothing to sweep.
        guard remoteCount > 0 else { return }
        requestDeduplication(insertedEntities: insertedEntityNames)
    }

    // The companion app has no dedup coordinator: it writes only attendance,
    // through the store that already collapses duplicates per student-day on read.
    nonisolated private static func requestDeduplication(insertedEntities: Set<String>) {
        #if !ASSISTANT_APP
        Task { @MainActor in
            DeduplicationCoordinator.shared.requestDeduplication(insertedEntities: insertedEntities)
        }
        #endif
    }

    nonisolated private static func requestFullDeduplication() {
        #if !ASSISTANT_APP
        Task { @MainActor in
            DeduplicationCoordinator.shared.requestDeduplication()
        }
        #endif
    }

    /// The entity-scoped notifications a batch that touched
    /// `changedEntityNames` owes: `.schoolDayDataDidChange` when a calendar
    /// entity moved, `.presentationDataDidChange` when any of
    /// `presentationEntityNames` did. (Flags rather than names: the
    /// school-day name is main-actor isolated, and this is decided on the actor.)
    nonisolated static func entityNotices(
        for changedEntityNames: Set<String>
    ) -> (schoolDay: Bool, presentation: Bool) {
        (
            schoolDay: !changedEntityNames.isDisjoint(with: schoolDayEntityNames),
            presentation: !changedEntityNames.isDisjoint(with: presentationEntityNames)
        )
    }

    /// Posts what `entityNotices(for:)` says is owed, on the main actor; the
    /// presentation one carries the touched subset of its entities.
    nonisolated static func postEntityNotifications(for changedEntityNames: Set<String>) {
        let notices = entityNotices(for: changedEntityNames)
        guard notices.schoolDay || notices.presentation else { return }
        let touched = changedEntityNames.intersection(presentationEntityNames)
        Task { @MainActor in
            if notices.schoolDay {
                NotificationCenter.default.post(name: .schoolDayDataDidChange, object: nil)
            }
            if notices.presentation {
                NotificationCenter.default.post(
                    name: .presentationDataDidChange, object: nil,
                    userInfo: [changedEntityNamesKey: touched]
                )
            }
        }
    }

    // MARK: - Public: Purge Old History

    /// How old a transaction must be before it is eligible for purging.
    /// Apple: "long enough for the history to become irrelevant, which can be
    /// several months for apps that people use on a regular basis."
    private static let purgeRetention: TimeInterval = 180 * 24 * 3600

    /// Minimum interval between purges. Apple: "Apps generally only need to
    /// purge the history several times a year."
    private static let purgeInterval: TimeInterval = 60 * 24 * 3600

    /// Purge persistent history following Apple's documented pattern for
    /// CloudKit-backed stores ("Sharing Core Data objects between iCloud
    /// users"): delete only transactions that predate BOTH the start of the
    /// last successful `.export` event AND a several-month retention window.
    ///
    /// `NSCloudKitMirroringDelegate` keeps its own history cursor that this
    /// process cannot read. Purging transactions it hasn't exported yet
    /// invalidates that cursor and forces a full reset against the CloudKit
    /// server — and any deletion whose only record was the purged tombstone
    /// resurrects on the next import. The export-date gate guarantees the
    /// delegate consumed everything we delete; the retention window keeps the
    /// history available for other consumers (BackupChangeTracker) and for
    /// devices that re-enable sync after running in the degraded local mode.
    func purgeOldHistory() async {
        // Never purge before CloudKit has demonstrably exported. On stores
        // that have never synced this keeps all history for a future first
        // export; disk cost is acceptable at this app's write volume.
        guard let exportStart = defaults.object(
            forKey: UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate
        ) as? TimeInterval else {
            Self.logger.debug("Skipping history purge — no successful CloudKit export recorded")
            return
        }

        if let lastPurge = defaults.object(
            forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate
        ) as? TimeInterval,
           Date().timeIntervalSince1970 - lastPurge < Self.purgeInterval {
            return
        }

        let retentionCutoff = Date().addingTimeInterval(-Self.purgeRetention)
        let cutoff = min(Date(timeIntervalSince1970: exportStart), retentionCutoff)

        let context = container.newBackgroundContext()
        let purged: Bool = await context.perform {
            let purgeRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
            do {
                try context.execute(purgeRequest)
                return true
            } catch {
                Self.logger.error("Failed to purge history: \(error.localizedDescription)")
                return false
            }
        }

        if purged {
            defaults.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.persistentHistoryLastPurgeDate)
            Self.logger.info("Purged persistent history older than \(cutoff, privacy: .public)")
        }
    }
}
