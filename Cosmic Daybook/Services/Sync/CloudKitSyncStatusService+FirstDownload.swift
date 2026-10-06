import CloudKit
import Foundation
import CoreData
import OSLog

// MARK: - First download

extension CloudKitSyncStatusService {

    /// The watch started when the stack loaded. One per process, and outside
    /// `messageObservationTasks`, so `configure`'s teardown doesn't end it.
    private static var firstDownloadWatch: Task<Void, Never>?

    /// While the gate is armed, listens for the private store's first import
    /// from the moment the stack loads (`AppBootstrapping.loadSharedStack`).
    ///
    /// It used to start at `configure`, which the window's bootstrap reaches
    /// some seconds into launch, and never in a launch with no window (a Siri
    /// intent, the MCP server): an import that finished before then was
    /// missed, and the gate stayed armed until some later import. With iCloud
    /// sync on but no iCloud account signed in, nothing will download, so the
    /// gate opens at once. Ends once the gate opens.
    static func watchForFirstDownload(
        on stack: CoreDataStack,
        accountStatus: @escaping @MainActor () async throws -> CKAccountStatus = {
            try await CloudKitConfigurationService.container.accountStatus()
        }
    ) {
        guard FirstDownloadGate.isPending(), firstDownloadWatch == nil else { return }
        // Subscribed before the task starts, so nothing posted meanwhile is missed.
        let events = NotificationCenter.default.messages(
            of: NSPersistentCloudKitContainer.self, for: .eventChanged, bufferSize: 256
        )
        firstDownloadWatch = Task { [weak stack] in
            defer { firstDownloadWatch = nil }
            if let stack, stack.isCloudKitActive, let status = try? await accountStatus(),
               FirstDownloadGate.nothingWillDownload(accountStatus: status, cloudKitActive: true) {
                logger.notice("No iCloud account is signed in, so nothing will download: holds lifted for this session")
                // Lifted for the session, not opened: the gate stays armed, so
                // a later launch with an account signed in waits for the download.
                FirstDownloadGate.liftForSession()
                runWhatTheGateHeld(context: stack.viewContext)
                return
            }
            for await message in events {
                let event = message.event
                guard event.type == .import, event.endDate != nil, event.succeeded else { continue }
                guard let stack else { return }
                finishFirstDownloadIfNeeded(
                    importedStoreIdentifier: event.storeIdentifier,
                    privateStoreIdentifier: stack.privatePersistentStore?.identifier,
                    context: stack.viewContext
                )
                if !FirstDownloadGate.isPending() { return }
            }
        }
    }

    /// `configure`'s call: starts the watch if the stack's load didn't (it
    /// does for the app's own stack, so this is a backstop).
    func watchForFirstDownloadIfPending() {
        guard let coreDataStack else { return }
        Self.watchForFirstDownload(on: coreDataStack)
    }

    /// The event handler's call, for the configured stack's private store.
    func finishFirstDownloadIfNeeded(importedStoreIdentifier: String?) {
        guard let stack = coreDataStack else { return }
        Self.finishFirstDownloadIfNeeded(
            importedStoreIdentifier: importedStoreIdentifier,
            privateStoreIdentifier: stack.privatePersistentStore?.identifier,
            context: stack.viewContext
        )
    }

    /// Opens `FirstDownloadGate` once an import into the private store has
    /// finished successfully, then runs what the gate held back. The shared
    /// store's import says nothing about the private store's, so it never
    /// opens the gate. Returns whether this opened it.
    @discardableResult
    static func finishFirstDownloadIfNeeded(
        importedStoreIdentifier: String?,
        privateStoreIdentifier: String?,
        context: NSManagedObjectContext,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard let privateStoreIdentifier, importedStoreIdentifier == privateStoreIdentifier else { return false }
        return finishFirstDownload(context: context, defaults: defaults)
    }

    /// Opens the gate and runs what it held back, exactly once: the built-in
    /// template seed (a no-op when the notebook's own came down) and the
    /// classroom records this device created while it waited for the pin.
    @discardableResult
    private static func finishFirstDownload(
        context: NSManagedObjectContext,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard FirstDownloadGate.open(defaults: defaults) else { return false }
        logger.notice("First download from iCloud finished: template seeding and classroom attach resume")
        runWhatTheGateHeld(context: context)
        return true
    }

    /// The built-in template seed and the classroom records waiting for the pin.
    private static func runWhatTheGateHeld(context: NSManagedObjectContext) {
        BuiltInTemplateSeeder.seedIfNeeded(context: context)
        if context.hasChanges {
            context.safeSave()
        }
        SharedStoreOrphanGuard.shared.flushPendingIfPossible()
    }
}
