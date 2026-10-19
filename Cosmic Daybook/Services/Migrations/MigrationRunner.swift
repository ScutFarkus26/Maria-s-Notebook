import CoreData
import Foundation
import OSLog

enum MigrationRunner {
    nonisolated private static let logger = Logger.migration

    /// What one launch pass did, for the log.
    nonisolated struct PassOutcome: Sendable {
        /// Duplicates removed, per model type (what `sweep` returned).
        var duplicatesRemoved: [String: Int] = [:]
        /// How long the integrity repairs took, on launches that ran them.
        var integrityRepairSeconds: TimeInterval?
        /// Work rows whose orphaned student references were cleared.
        var workRowsCleaned = 0
        /// The orphan-grace ledger after the pass, when one was passed in.
        var orphanGraceLedger: [String: Date]?
    }

    /// Runs the launch repairs on a background context.
    ///
    /// - Parameters:
    ///   - includeIntegrityRepairs: also run the whole-table `CDLessonAssignment`
    ///     repair (orphaned student IDs). The bootstrapper passes true on about
    ///     one launch in ten.
    ///   - lastImport: when a store last finished an import from iCloud, or nil
    ///     when none is known. The orphan graces (students, check-ins' missing
    ///     work) only act on an id once an import has finished since it went
    ///     missing; with nothing known, missing ids keep waiting.
    ///
    /// While the first download from iCloud is under way (`FirstDownloadGate`)
    /// the repairs that judge a row by what else is in the store — orphaned
    /// students, check-ins whose work is missing — wait: rows still on their
    /// way down would read as gone, and what they cleared would sync back up.
    static func runIfNeeded(
        coreDataStack: CoreDataStack,
        includeIntegrityRepairs: Bool = false,
        lastImport: @escaping @Sendable (ImportStoreKind) -> Date?
    ) async {
        // Heavy, synchronous launch cleanup — deduplicating ~30 entity types and
        // sweeping orphaned note images — runs on a background context so it no
        // longer blocks the main thread during launch. The view context picks up
        // the results via `automaticallyMergesChangesFromParent`. This mirrors the
        // pattern already used by DeduplicationCoordinator for the post-sync pass.
        let bgContext = coreDataStack.newBackgroundContext()
        let container = coreDataStack.container
        let firstDownloadPending = FirstDownloadGate.isPending()
        let noteScopeRepairDue = DataMigrations.noteScopeIndexRepairDue(firstDownloadPending: firstDownloadPending)
        // The post-import dedup waits while this pass runs (and this pass waits
        // for one already running): two passes on two contexts could each fold
        // the same rows from a view the other is changing.
        let outcome = await DeduplicationCoordinator.shared.holdingPasses {
            await runPass(
                on: bgContext,
                includeIntegrityRepairs: includeIntegrityRepairs,
                firstDownloadPending: firstDownloadPending,
                orphanGraceLedger: OrphanStudentGrace.load(from: .standard),
                lastImport: lastImport,
                sweep: { context in
                    launchSweep(
                        context,
                        container: container,
                        firstDownloadPending: firstDownloadPending,
                        noteScopeRepairDue: noteScopeRepairDue,
                        lastImport: lastImport
                    )
                }
            )
        }
        if let seconds = outcome.integrityRepairSeconds {
            logger.info("Post-launch: integrity repairs completed in \(seconds.formattedAsDuration)")
        }
        for (modelType, count) in outcome.duplicatesRemoved.sorted(by: { $0.key < $1.key }) {
            logger.info("Removed \(count, privacy: .public) duplicate \(modelType, privacy: .public) record(s)")
        }
        if outcome.workRowsCleaned > 0 {
            logger.info("Cleared orphaned students on \(outcome.workRowsCleaned, privacy: .public) work row(s)")
        }
        if let ledger = outcome.orphanGraceLedger {
            OrphanStudentGrace.save(ledger, to: .standard)
        }

        // Calendar notes join their days' pads (one day note): on the Mac, on
        // the view context, each launch once it has caught up with iCloud.
        #if os(macOS)
        startCalendarNotePadCopy(
            coreDataStack: coreDataStack,
            firstDownloadPending: firstDownloadPending,
            lastImport: lastImport(.privateStore)
        )
        #endif
    }

    /// Copies the Calendar's notes into their days' pads (`CalendarNotePadCopy`),
    /// marking each note on its row, and saves the pads and the marks together.
    ///
    /// - Every launch, not once: a note an older build writes later, on any
    ///   device, is copied the next time. The marks make a launch with nothing
    ///   new one fetch that finds nothing, and no write.
    /// - Not while the first download from iCloud is under way
    ///   (`FirstDownloadGate`), nor before this launch has caught up with
    ///   iCloud (`copyCalendarNotesToPadsOnceCaughtUp`): pads already holding
    ///   the copies, or edited on the iPad since, may still be on their way down.
    /// - On the view context, where Today's Pad and the Calendar edit: a pad
    ///   open in an editor sees the added text and merges it with her typing
    ///   (`TodayDataFetcher.savePadText`), where a second context's save
    ///   could cross hers.
    /// - Never with someone else's edit: the save is the view context's whole
    ///   save, so while the context holds a change not saved yet (a field
    ///   being typed in, a sheet's draft) this pass doesn't run, and returns
    ///   nil; the caller tries again at the next finished import, or the next
    ///   launch does. Between that check and the save nothing else runs, so a
    ///   failed save is rolled back, losing only the copy's own changes, and
    ///   is tried again the same way.
    /// - On the Mac only (the caller gates it), as with the Restock backfill:
    ///   one device writes the copies and the iPad and iPhone get them through
    ///   iCloud, so a device that hasn't caught up can't add a note again to a
    ///   pad edited elsewhere since, nor send a stale pad back over that edit.
    ///   It is safe to run on two devices all the same (the pad's text is
    ///   checked first, and two devices' copies of a day are joined).
    ///
    /// Only the primary copy of the app runs it (`runIfNeeded` is the launch
    /// pass), and only on the notebook's own stack: the Sample Class has its
    /// own store and never runs the launch pass, and hosted tests skip it.
    /// Returns what it did, or nil when it didn't run or couldn't save.
    @discardableResult
    static func copyCalendarNotesToPads(
        in context: NSManagedObjectContext,
        firstDownloadPending: Bool
    ) -> CalendarNotePadCopy.Outcome? {
        guard !firstDownloadPending else { return nil }
        guard !context.hasChanges else {
            logger.info("Calendar notes wait to go into the day pads: a change on screen isn't saved yet")
            return nil
        }
        let outcome = CalendarNotePadCopy.run(in: context)
        guard context.safeSave() else {
            context.rollback()
            logger.error("Calendar notes couldn't be saved into the day pads; they're tried again later")
            return nil
        }
        if outcome.copied > 0 {
            logger.notice("Copied \(outcome.copied, privacy: .public) calendar note(s) into their day pads")
        }
        return outcome
    }

    /// `copyCalendarNotesToPads`, once this launch has caught up with iCloud
    /// (`CalendarNotePadCopy.caughtUp`): an import into the notebook that began
    /// after the app started (`launchedAt`) has finished, the way the orphan
    /// graces wait for one (`OrphanStudentGrace`). `lastImport` is the latest
    /// on record (`ImportWatermark`), or the launch itself when iCloud sync is
    /// off; otherwise it waits for one among `finishedImports`, the starts of
    /// imports into the notebook as each finishes. A pass that doesn't run (a
    /// change on screen not saved yet) or can't save is tried again at the
    /// next of them. None coming (offline all day) leaves the copy to a later
    /// launch. Returns what the copy did, or nil when it didn't run.
    @discardableResult
    static func copyCalendarNotesToPadsOnceCaughtUp(
        in context: NSManagedObjectContext,
        launchedAt: Date,
        lastImport: Date?,
        finishedImports: some AsyncSequence<Date, Never>
    ) async -> CalendarNotePadCopy.Outcome? {
        if CalendarNotePadCopy.caughtUp(lastImport: lastImport, launchedAt: launchedAt),
           let outcome = copyCalendarNotesToPads(in: context, firstDownloadPending: false) {
            return outcome
        }
        for await started in finishedImports
        where CalendarNotePadCopy.caughtUp(lastImport: started, launchedAt: launchedAt) {
            if let outcome = copyCalendarNotesToPads(in: context, firstDownloadPending: false) {
                return outcome
            }
        }
        return nil
    }

    #if os(macOS)
    /// Starts this launch's copy of the Calendar notes into the day pads
    /// (`copyCalendarNotesToPadsOnceCaughtUp`) without holding up the rest of
    /// the launch. A launch during the first download leaves it to the next.
    private static func startCalendarNotePadCopy(
        coreDataStack: CoreDataStack,
        firstDownloadPending: Bool,
        lastImport: Date?
    ) {
        guard !firstDownloadPending, let notebook = coreDataStack.privatePersistentStore?.identifier else { return }
        let context = coreDataStack.viewContext
        let launchedAt = processStartDate() ?? Date()
        Task {
            // Listening before the watermark is read again, so an import that
            // finishes in between is heard.
            let imports = NotificationCenter.default
                .notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
                .compactMap { finishedImportStart($0, storeIdentifier: notebook) }
            let latest = [lastImport, ImportWatermark.lastImport(into: .notebook, of: coreDataStack)]
                .compactMap { $0 }
                .max()
            await copyCalendarNotesToPadsOnceCaughtUp(
                in: context, launchedAt: launchedAt, lastImport: latest, finishedImports: imports
            )
        }
    }

    /// When the import a CloudKit event notification reports began, if it is
    /// an import into the store with `storeIdentifier` that finished and
    /// worked (`RemoteImportReloader.isFinishedImport`). Read off the
    /// notification before it reaches the main actor: `Notification` isn't
    /// Sendable.
    nonisolated private static func finishedImportStart(_ note: Notification, storeIdentifier: String) -> Date? {
        guard RemoteImportReloader.isFinishedImport(note, storeIdentifier: storeIdentifier),
              let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else { return nil }
        return event.startDate
    }

    /// When this process started, from the kernel: "this launch" for the
    /// copy's wait, since the launch's own first import begins right after.
    nonisolated private static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
    #endif

    /// The launch pass's middle step: deduplication and the other launch
    /// cleanups, then one save. On `context`'s queue.
    nonisolated private static func launchSweep(
        _ context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer,
        firstDownloadPending: Bool,
        noteScopeRepairDue: Bool,
        lastImport: @escaping @Sendable (ImportStoreKind) -> Date?
    ) -> [String: Int] {
        // Remove duplicate records that may have been created by CloudKit sync conflicts.
        let results = DataMigrations.deduplicateAllModels(using: context, container: container)
        // Clean up any orphaned note images.
        DataMigrations.cleanupOrphanedNoteImages(using: context)
        // Check-ins that carry only a workID string, and whole-class notes
        // written on a presentation (see +CheckInAndNoteRepairs).
        DataMigrations.repairWorkCheckInLinks(
            using: context, firstDownloadPending: firstDownloadPending, lastImport: lastImport
        )
        // Notes saved with no scope blob join the whole-class index, once per
        // device (see +NoteScopeIndex); before the presentation-note repair, so
        // one on a presentation is narrowed to its roster in this same pass.
        if noteScopeRepairDue {
            DataMigrations.repairMissingNoteScopeIndex(using: context)
        }
        DataMigrations.repairPresentationNoteScopes(using: context)
        // Attendance notes kept as private Notes join their shared record.
        AttendanceNoteMove.run(using: context)
        // Rows still carrying the retired completion outcome (see +WorkStatusMerge).
        DataMigrations.mergeWorkCompletionOutcomes(using: context)
        // The check-in repair's first run counts only once what it did is saved.
        if !context.hasChanges || context.safeSave() {
            DataMigrations.markCheckInLinkRepairRun(firstDownloadPending: firstDownloadPending)
            if noteScopeRepairDue { DataMigrations.markNoteScopeIndexRepairDone() }
        }
        // Multi-child notes get the student links their scope names, once per
        // device after the first download; it saves on its own (see +NoteScopeIndex).
        DataCleanupService.repairNoteStudentLinksIfDue(using: context, firstDownloadPending: firstDownloadPending)
        // Uniform check-in work saved without its project type, once per device
        // after the first download; it saves on its own (see +ProjectWorkContext).
        DataCleanupService.repairProjectWorkContextTypeIfDue(using: context, firstDownloadPending: firstDownloadPending)
        return results
    }

    /// Runs the launch repairs on `context`'s queue, in the order they have
    /// always run:
    /// 1. on `includeIntegrityRepairs` launches, orphaned student IDs on
    ///    assignments (until 2026-09-26 this ran just before this pass, on the
    ///    main-actor view context);
    /// 2. `sweep` — deduplication and the other launch cleanups, then a save;
    /// 3. orphaned student IDs on work rows (until 2026-09-26 this ran just
    ///    after the pass on the view context, firing one `participants` fault
    ///    per work row on the main thread).
    ///
    /// The scheduled-day mirror was rewritten in step 1 until 2026-10-05; it
    /// isn't any more (`DataMigrations.repairScheduledForDayMirror`).
    ///
    /// With `firstDownloadPending`, the two orphaned-student steps are skipped:
    /// the students they check against may not have downloaded yet.
    ///
    /// With `orphanGraceLedger`, a missing student id is only cleared once it has been
    /// missing on passes a day apart with an import since into the store that holds
    /// students (`OrphanStudentGrace`, `lastImport`); the updated ledger comes back in the
    /// outcome. Without one (tests), every missing id is cleared at once.
    ///
    /// Each step saves what it changed, as it did on its own context, so each
    /// reads what the one before saved — and the dedup's id-column pre-check,
    /// which falls back to reading whole tables on a context with unsaved
    /// changes, still starts clean. A step whose save failed leaves changes
    /// behind; they are dropped before the next step, which then reads the
    /// store as it did when the steps ran on separate contexts, so one failed
    /// save can't make every later save of the pass fail too.
    ///
    /// `@concurrent`, so the block is handed to the context from the calling
    /// task's executor at that task's priority (`.utility` at launch), not
    /// from the main thread.
    @concurrent
    nonisolated static func runPass(
        on context: NSManagedObjectContext,
        includeIntegrityRepairs: Bool,
        firstDownloadPending: Bool,
        orphanGraceLedger: [String: Date]? = nil,
        lastImport: @escaping @Sendable (ImportStoreKind) -> Date? = { _ in nil },
        now: Date = Date(),
        sweep: @escaping @Sendable (NSManagedObjectContext) -> [String: Int]
    ) async -> PassOutcome {
        await context.perform {
            var outcome = PassOutcome()
            let grace = orphanGraceLedger.map { ledger in
                OrphanStudentGrace(ledger: ledger, now: now, lastImport: lastImport(studentStore(in: context)))
            }
            if includeIntegrityRepairs {
                let start = Date()
                if !firstDownloadPending {
                    DataMigrations.cleanOrphanedStudentIDs(using: context, grace: grace)
                    discardUnsavedChanges(in: context)
                }
                outcome.integrityRepairSeconds = Date().timeIntervalSince(start)
            }
            outcome.duplicatesRemoved = sweep(context)
            discardUnsavedChanges(in: context)
            if !firstDownloadPending {
                outcome.workRowsCleaned = DataMigrations.cleanOrphanedWorkStudentIDs(using: context, grace: grace)
                discardUnsavedChanges(in: context)
            }
            outcome.orphanGraceLedger = grace?.ledger
            return outcome
        }
    }

    /// Where this notebook's students live: the private store on the lead
    /// guide's devices (his own records, shared from there), the shared store
    /// on a notebook that joined someone else's classroom as an assistant.
    nonisolated private static func studentStore(in context: NSManagedObjectContext) -> ImportStoreKind {
        CDClassroomMembership.currentRole(in: context) == .assistant ? .sharedStore : .privateStore
    }

    /// Drops what a step left unsaved, which it only does when its save failed.
    nonisolated private static func discardUnsavedChanges(in context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        logger.error("A launch repair step could not save; discarding its changes before the next step")
        context.rollback()
    }
}
