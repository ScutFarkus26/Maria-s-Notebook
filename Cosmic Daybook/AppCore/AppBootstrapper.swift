import Foundation
import CoreData
import SwiftUI
import OSLog

/// Handles the initial setup and database migrations for the app.
/// Moves heavy synchronous work off the main UI rendering flow of the App struct.
@Observable
final class AppBootstrapper {
    private static let logger = Logger.bootstrapper

    enum State {
        case idle
        case initializingContainer
        case migrating
        case ready
    }
    
    private(set) var state: State = .idle
    
    static let shared = AppBootstrapper()
    private init() {}
    
    func setState(_ newState: State) {
        state = newState
    }
    
    func bootstrap(coreDataStack: CoreDataStack) async {
        guard state == .idle else { return }
        state = .migrating

        let context = coreDataStack.viewContext

        let startTime = Date()
        let bootstrapInterval = LaunchSignposts.begin("Bootstrap")
        Self.logger.info("Bootstrap: Starting startup checks...")

        // Activate the iCloud ubiquity container in the background so the
        // "Cosmic Daybook" folder appears in Finder / Files.app at launch, and
        // keep its URL for the managed document folders, which read it from
        // then on instead of asking on the main thread (it is asked for again
        // whenever the iCloud identity changes; see UbiquityContainerCache).
        // Apple requires this call off the main thread; it can block briefly
        // while the container is set up for the first time.
        UbiquityContainerCache.shared.startRefreshing()

        let earlySetup = LaunchSignposts.begin("EarlySetup")
        performEarlySetup(context: context)
        LaunchSignposts.end("EarlySetup", earlySetup)

        // 4. Initialize CDReminder Sync Service (macOS only)
        #if os(macOS)
        let reminderStart = Date()
        ReminderSyncService.shared.managedObjectContext = context
        // Perform initial sync only if the user has configured a sync list in Settings.
        // No default list is seeded — sync stays off until explicitly configured.
        if ReminderSyncService.shared.syncListIdentifier != nil || ReminderSyncService.shared.syncListName != nil {
            Task {
                do {
                    try await ReminderSyncService.shared.syncReminders()
                    Self.logger.info("Bootstrap: Initial reminder sync completed")
                } catch let error as ReminderSyncError where error.isConfigurationIssue {
                    // Stale or missing configuration (e.g. the list was deleted in
                    // Reminders) — surfaced in Settings, not an app failure.
                    Self.logger.notice("Bootstrap: Initial reminder sync skipped: \(error.localizedDescription)")
                } catch {
                    Self.logger.error("Bootstrap: Initial reminder sync failed: \(error)")
                }
            }
        }
        let remElapsed = Self.formatSeconds(Date().timeIntervalSince(reminderStart))
        Self.logger.info("Bootstrap: Reminder setup completed in \(remElapsed)")
        #endif
        
        // 5. Signal UI (allow first render; heavy migrations continue in background)
        let routerStart = Date()
        AppRouter.shared.refreshPlanningInbox()
        let routerElapsed = Self.formatSeconds(Date().timeIntervalSince(routerStart))
        Self.logger.info("Bootstrap: Router refresh completed in \(routerElapsed)")
        
        let totalElapsed = Self.formatSeconds(Date().timeIntervalSince(startTime))
        Self.logger.info("Bootstrap: Initial phase complete in \(totalElapsed)")
        LaunchSignposts.end("Bootstrap", bootstrapInterval)
        state = .ready
        LaunchSignposts.event("UIReady")

        // 5.5. Initialize post-sync deduplication coordinator — in the one copy
        // of the app that had the store files to itself at launch. A second copy
        // (the Mac can run several) leaves duplicate cleanup and the launch
        // repairs to that one, so two copies never fold the same rows.
        if CoreDataStack.isPrimaryProcess {
            DeduplicationCoordinator.shared.persistentContainer = coreDataStack.container
        }

        // 5.6. Start the orphan guard, which puts each classroom record this
        // device creates into the classroom share as it is saved.
        SharedStoreOrphanGuard.shared.start(coreDataStack: coreDataStack)

        // 6. Run heavy migrations and dedup in the background to avoid UI stalls
        // IMPORTANT: Delay background migrations to let the initial SwiftUI render complete.
        // Without this delay, background DB operations compete with @FetchRequest evaluations
        // and TodayViewModel.reload() for the persistent store coordinator, causing the
        // main thread to block in AG::Subgraph::update() (spinning beach ball).
        Task.detached(priority: .utility) { [coreDataStack] in
            try? await Task.sleep(for: .seconds(3))
            await AppBootstrapper.runPostLaunchMigrations(coreDataStack: coreDataStack)

            // Occasionally purge months-old persistent history that the CloudKit
            // mirroring delegate has provably exported (export-date gated; see
            // PersistentHistoryProcessor.purgeOldHistory for the safety rules).
            if let processor = await MainActor.run(body: { coreDataStack.historyProcessor }) {
                await processor.purgeOldHistory()
            }
        }
    }

    private func performEarlySetup(context: NSManagedObjectContext) {
        // Seed built-in templates (first launch or after restore)
        BuiltInTemplateSeeder.seedIfNeeded(context: context)
    }

    /// A second copy of the app (the Mac can run several) takes over duplicate
    /// cleanup and sharing new classroom records once it has the store files
    /// to itself: the copy that had that job has quit. Primary was otherwise
    /// decided once, at launch, so relaunching the installed app beside a
    /// Debug run left it a second copy all day (2026-10-05 review).
    static func takeOverIfAlone(coreDataStack: CoreDataStack) {
        guard CoreDataStack.isSecondaryProcess, CoreDataStack.promoteToPrimaryIfAlone() else { return }
        logger.notice("The other copy of the app has quit: this one now runs duplicate cleanup and shares new records")
        DeduplicationCoordinator.shared.persistentContainer = coreDataStack.container
        SharedStoreOrphanGuard.shared.flushPendingIfPossible()
    }

    /// When the launch counts the notebook as caught up with iCloud without
    /// an import: now, when iCloud sync is turned off (nothing is on its way
    /// down); otherwise nil, and each store's import watermark decides, even
    /// when CloudKit failed to start this launch.
    nonisolated static func caughtUpWithoutImports(syncPreferred: Bool, now: Date = Date()) -> Date? {
        syncPreferred ? nil : now
    }

    private static func runPostLaunchMigrations(coreDataStack: CoreDataStack) async {
        let start = Date()
        let migrations = LaunchSignposts.begin("PostLaunchMigrations")
        defer { LaunchSignposts.end("PostLaunchMigrations", migrations) }
        logger.info("Post-launch migrations started")

        // 3.8. Deduplication (CloudKit sync can create duplicates during merge
        // conflicts) runs later in this same sequence via MigrationRunner, on a
        // background context. It used to run here on the view context as well —
        // a second full pass over ~35 entity types whose results the view context
        // then held for the rest of the session.

        // The one-time steps that used to run around here (the May classroom
        // shared→private store move, the PDF folder move, two presentation
        // backfills, the March note-scope repair) were removed on 2026-09-26
        // once every device had long since run them.

        // 3.9. Data Integrity Repairs (Run on ~10% of launches to reduce startup impact).
        // They run first in MigrationRunner's background pass — the same place in
        // this sequence as before, but no longer on the view context.
        let includeIntegrityRepairs = Int.random(in: 1...10) == 1

        // The orphan graces act on a missing student or work row only once an
        // import from iCloud that began after it went missing has finished
        // (`ImportWatermark`). Read here, on the main actor, and handed to the
        // background pass as plain dates. With iCloud sync turned off nothing
        // is on its way down, so the notebook counts as caught up now and only
        // the day of grace applies. Not when sync is on but CloudKit didn't
        // start this launch: everything still to come is then on its way, and
        // a missing row must keep waiting (2026-10-05 review).
        let caughtUpNow = caughtUpWithoutImports(syncPreferred: CoreDataStack.syncPreferred(in: .standard))
        let notebookImport = caughtUpNow ?? ImportWatermark.lastImport(into: .notebook, of: coreDataStack)
        let shareImport = caughtUpNow ?? ImportWatermark.lastImport(into: .classroomShare, of: coreDataStack)
        let lastImport: @Sendable (ImportStoreKind) -> Date? = { kind in
            switch kind {
            case .privateStore: return notebookImport
            case .sharedStore: return shareImport
            }
        }
        if CoreDataStack.isPrimaryProcess {
            await MigrationRunner.runIfNeeded(
                coreDataStack: coreDataStack,
                includeIntegrityRepairs: includeIntegrityRepairs,
                lastImport: lastImport
            )
        } else {
            logger.notice("Post-launch: another copy of the app runs the launch repairs")
        }

        // Drop the Claude/OpenAI API keys and model choices the Apple-only AI
        // change left on this device. Once per device, off the main thread;
        // retried if the Keychain refuses, for up to three launches.
        await RetiredAIKeysCleanup.runOffMainThread()

        // The one-time steps below write on the view context and save as one
        // batch; their done flags count only once that batch has saved.
        let viewContext = coreDataStack.viewContext
        runLaunchBatch(
            in: viewContext,
            oneShotFlags: [UserDefaultsKeys.attendanceLocksCarriedOver, UserDefaultsKeys.restockLevelsFromCounts]
        ) {
            // Locked attendance days moved from an iCloud setting to shared lock
            // records (schema 9); carry this device's old ones over, once.
            AttendanceDayLocks.migrateStoredLegacyKeysIfNeeded(in: viewContext)

            // Staples kept as counts before Restock's levels (schema 15) get a level
            // from their count, once, on the Mac only: an iPad that hadn't caught up
            // with the Mac could set a staple restocked there back to Out. On the view
            // context, so the needs it opens join the classroom share when the batch
            // saves.
            #if os(macOS)
            RestockLevelBackfill.runIfNeeded(in: viewContext)
            #endif

            // The front-desk email's settings travel to the assistants in the
            // classroom share (schema 12). Written here only when the share has
            // none yet; after that only the settings screen's edits change them.
            // This device's preferences may not have caught up with an edit made
            // on another of the guide's devices.
            AttendanceEmail.shareSettingsIfMissing(in: viewContext)
        }

        // Classroom records this device created before the classroom share's
        // pin arrived (a new device) go in now, if the share is here. Nothing
        // else is swept in: see SharedStoreOrphanGuard.
        SharedStoreOrphanGuard.shared.flushPendingIfPossible()

        // The front-desk email reminder, if this device has it on: the next
        // school days' requests, without today's once the email has gone.
        await FrontDeskEmailReminder.reschedule(in: coreDataStack.viewContext)

        logger.info("Post-launch migrations finished in \(formatSeconds(Date().timeIntervalSince(start)))")

        // 4. Bring the full-text search index up to date after data is clean.
        // `refresh` reuses the on-disk snapshot and replays persistent history
        // since it was written; only a missing or stale snapshot costs a full pass.
        //
        // Skipped entirely on a hot device or in Low Power Mode: the refresh is
        // change-gated, so the next launch picks up everything this one missed.
        // Searching still works meanwhile — the snapshot on disk is just older.
        guard !EnergyPolicy.shared.shouldDeferMaintenance else {
            logger.notice("Post-launch: search index refresh skipped — device hot or in Low Power Mode")
            return
        }

        // 3.95. iCloud files. Photos kept on this device before note photos
        // moved to iCloud (2026-09-27) join them, once iCloud Drive is on; a
        // no-op once the local folder is empty. Then, on iPhone and iPad, ask
        // iCloud for every file of the app's not yet downloaded, so lesson
        // files, stories and photos open without a network.
        await PhotoStorageService.moveLocalPhotosToICloud()
        #if !os(macOS)
        UbiquitousDownloadSweep.shared.start()
        #endif
        let searchIndex = LaunchSignposts.begin("SearchIndexRebuild")
        await SearchIndexService.shared.refresh(container: coreDataStack.container)
        LaunchSignposts.end("SearchIndexRebuild", searchIndex)
    }

    /// Runs the launch's one-time view-context steps and saves what they
    /// changed as one batch (with whatever else the view context holds, as
    /// before). Returns whether the batch saved.
    ///
    /// `oneShotFlags` are the steps' done flags: the steps set them as they
    /// run, and they are held back and set only once the save has gone
    /// through. If the save fails, only what the steps changed is undone: rows
    /// they added are dropped and rows they changed go back to their saved
    /// values, so one bad row doesn't stay behind to fail every later save of
    /// the view context, and the guide's unsaved edits aren't rolled back with
    /// it. Their flags stay as they were, so the steps run again next launch
    /// (2026-10-05). The steps only insert and update.
    @discardableResult
    static func runLaunchBatch(
        in context: NSManagedObjectContext,
        oneShotFlags: [String],
        defaults: UserDefaults = .standard,
        steps: () -> Void
    ) -> Bool {
        context.processPendingChanges()
        let pendingBefore = context.insertedObjects.union(context.updatedObjects).union(context.deletedObjects)
        let flagsBefore = oneShotFlags.map { ($0, defaults.object(forKey: $0)) }
        steps()
        context.processPendingChanges()
        let flagsAfter = oneShotFlags.map { ($0, defaults.object(forKey: $0)) }
        for (key, value) in flagsBefore {
            defaults.set(value, forKey: key)
        }
        let inserted = context.insertedObjects.subtracting(pendingBefore)
        let changed = context.updatedObjects.union(context.deletedObjects).subtracting(pendingBefore)

        guard !context.hasChanges || context.safeSave() else {
            for object in inserted {
                context.delete(object)
            }
            for object in changed {
                context.refresh(object, mergeChanges: false)
            }
            context.processPendingChanges()
            let undone = inserted.count + changed.count
            logger.error("Post-launch migrations: the batch didn't save; undid \(undone) row(s), will retry")
            return false
        }
        for (key, value) in flagsAfter {
            defaults.set(value, forKey: key)
        }
        return true
    }

    private static func formatSeconds(_ interval: TimeInterval) -> String {
        interval.formattedAsDuration
    }
}
