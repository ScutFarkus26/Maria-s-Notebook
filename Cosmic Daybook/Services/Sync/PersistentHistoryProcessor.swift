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
///    delegate has provably finished exporting (`purgeOldHistory`, in
///    `+Purge`, which the Daybook Assistant doesn't compile: it trims its own,
///    `AssistantHistoryTrim`)
///
/// The view context has `automaticallyMergesChangesFromParent = true`, which
/// merges what this process saves, CloudKit's imports included. Saves by
/// another process on the same store (a second copy of the app on the Mac, an
/// intent run elsewhere) reach no context here that way: a pass hands their
/// object IDs back (`ForeignChanges`) for the caller to merge into the view
/// context (`merge(_:into:)`), and announces them like an import's.
actor PersistentHistoryProcessor {

    // MARK: - Constants

    /// The author every context of the app stamps on its saves: the app's name
    /// and this process's own suffix. With one name for every process, a save by
    /// another running copy of the app read as this one's own and was skipped:
    /// never merged into this copy's view context, never announced (2026-10-05
    /// hunt, #64). Only this exact author is "own" now, and the bare old one.
    nonisolated static let transactionAuthor =
        "\(legacyTransactionAuthor).\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString.prefix(8))"

    /// What every process wrote before 2026-10-05. Still counted as own, so the
    /// first launch of this build doesn't react to all of its own history again.
    nonisolated static let legacyTransactionAuthor = "CosmicDaybook"

    /// Whether `author` is this process's own (or the old shared one).
    nonisolated static func isOwnAuthor(_ author: String?, own: String = transactionAuthor) -> Bool {
        author == own || author == legacyTransactionAuthor
    }

    /// Whether a transaction was saved by another running copy of the app: the
    /// app's author with another process's suffix. Not by its `processID`, which
    /// is the process's name ("Cosmic Daybook" for every copy). CloudKit's own
    /// imports are this process's, and its contexts merge them already.
    nonisolated static func isFromAnotherProcess(author: String?, own: String = transactionAuthor) -> Bool {
        guard let author, !isOwnAuthor(author, own: own) else { return false }
        return author.hasPrefix(legacyTransactionAuthor + ".")
    }

    nonisolated static let logger = Logger.historyProcessor

    /// Entities whose remote changes must invalidate the school-day caches.
    /// `CoreDataStack` used to post `.schoolDayDataDidChange` on *every*
    /// remote-change notification (its entity filter read object-ID keys that
    /// notification never carries), which re-keyed every drop zone and day
    /// column for the whole of a CloudKit import. History transactions do
    /// know which entities changed, so the post happens here instead.
    nonisolated private static let schoolDayEntityNames: Set<String> = ["NonSchoolDay", "SchoolDayOverride"]

    /// Entities the Upcoming pane, the progress map, the class checklist, the
    /// attendance roll, the ready queue (`ReadyQueueLoader.inputEntities`) and
    /// Restock read (`LessonPresentation` carries the mastery marks the
    /// checklist colors green), and the names people go by (`ClassroomPerson`),
    /// which those lines are worded with. A batch that touched any of them posts
    /// `.presentationDataDidChange` with the touched names under
    /// `changedEntityNamesKey`, so those screens no longer keep whole tables
    /// registered through `@FetchRequest` just to notice a remote change (see
    /// `View.onPresentationDataChange`).
    nonisolated static let presentationEntityNames: Set<String> = [
        "LessonAssignment", "Lesson", "LessonPresentation", "Student", "WorkModel",
        "AttendanceRecord", "AttendanceDayLock", "AttendanceEmailSend", "AttendanceEmailSettings",
        "YearPlanEntry", "WorkParticipantEntity", "LessonSequenceSettings",
        "Supply", "SupplyTransaction", "OrderItem", "ClassroomPerson"
    ]

    /// `userInfo` key of `.presentationDataDidChange`: the `Set<String>` of
    /// `presentationEntityNames` the batch touched.
    nonisolated static let changedEntityNamesKey = "changedEntityNames"

    // MARK: - State

    let container: NSPersistentCloudKitContainer
    /// Where the cursor is kept and the export and purge dates are read:
    /// `.standard` in the app, a suite of its own in a test, since the test
    /// host's own processor keeps its cursor under the same key.
    let defaults: UserDefaults

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
    }

    // MARK: - Public: Process Remote Changes

    /// Process new persistent history transactions since each store's position.
    /// Called when `.NSPersistentStoreRemoteChange` fires.
    ///
    /// Callers that arrive while a pass is running are folded into a single follow-up
    /// pass rather than each running their own. Nothing is dropped: the follow-up reads
    /// from the same positions, so it still sees every transaction written in the meantime.
    ///
    /// Returns what other processes changed in the passes it ran, for the caller to
    /// merge into its view context (`merge(_:into:)`); a caller folded into a running
    /// pass gets nothing back, since that pass's caller gets it.
    @discardableResult
    func processRemoteChanges() async -> ForeignChanges {
        guard !isProcessing else {
            needsAnotherPass = true
            return ForeignChanges()
        }
        isProcessing = true
        defer { isProcessing = false }
        var foreign = ForeignChanges()
        repeat {
            needsAnotherPass = false
            foreign.formUnion(await performProcessingPass())
        } while needsAnotherPass
        return foreign
    }

    private func performProcessingPass() async -> ForeignChanges {
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
        if !pass.foreignChanges.isEmpty {
            Self.logger.info("Another copy of the app changed \(pass.foreignChanges.count) object(s)")
        }
        return pass.foreignChanges
    }

    /// Merges what other processes changed into `context` (the view context):
    /// their saves reach this process only through the store's history.
    @MainActor
    static func merge(_ foreign: ForeignChanges, into context: NSManagedObjectContext) {
        guard !foreign.isEmpty else { return }
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: foreign.remoteSave, into: [context])
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
}
