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
    /// holds lift for the session (`followAccountForFirstDownload`). Ends once
    /// the gate opens.
    static func watchForFirstDownload(
        on stack: CoreDataStack,
        accountStatus: @escaping @MainActor () async throws -> CKAccountStatus = {
            try await CloudKitConfigurationService.container.accountStatus()
        }
    ) {
        guard FirstDownloadGate.isPending(), firstDownloadWatch == nil else { return }
        // A plain observer, listening as this returns and buffering while the
        // account is asked about: a `messages(of:for:)` sequence listens only
        // once it is first iterated, after that question, and an import that
        // finished meanwhile was missed (2026-11-03 review).
        let (events, continuation) = AsyncStream<NSPersistentCloudKitContainer.Event>.makeStream(
            bufferingPolicy: .bufferingNewest(256)
        )
        let center = NotificationCenter.default
        let observer = center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
        ) { note in
            let key = NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            if let event = note.userInfo?[key] as? NSPersistentCloudKitContainer.Event { continuation.yield(event) }
        }
        // The token only goes back to the center that made it.
        nonisolated(unsafe) let token = observer
        firstDownloadWatch = Task { [weak stack] in
            defer {
                center.removeObserver(token)
                continuation.finish()
                firstDownloadWatch = nil
            }
            if let stack, stack.isCloudKitActive {
                await followAccountForFirstDownload(context: stack.viewContext, accountStatus: accountStatus)
            }
            for await event in events {
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

    /// The watch's account step. With no iCloud account signed in, asked
    /// twice (`waitBeforeRecheck` apart: an account change or a minute),
    /// nothing will download now: the holds lift for this session and what
    /// the gate held runs. A Mac opening at login gets `noAccount` for a
    /// moment while the account signs in, and one answer lifted the holds
    /// for the whole session, so the download that followed went unguarded
    /// (bug hunt 2026-11-02, #26; `noteSetupWithoutAccount` asks twice for
    /// the same reason). The lift is taken back once an account change
    /// reports an account (`waitForAccountChange` between looks), and the
    /// watch goes on to wait for the import. Returns at once when an account
    /// is there; otherwise once one signs in. `setLifted` is the session's
    /// lift (`FirstDownloadGate.liftForSession`, `endSessionLift`), which the
    /// tests keep to themselves, since the real one is the whole process's.
    static func followAccountForFirstDownload(
        context: NSManagedObjectContext,
        accountStatus: @escaping @MainActor () async throws -> CKAccountStatus,
        defaults: UserDefaults = .standard,
        setLifted: @escaping @MainActor (Bool) -> Void = { lifted in
            if lifted { FirstDownloadGate.liftForSession() } else { FirstDownloadGate.endSessionLift() }
        },
        waitBeforeRecheck: @escaping @MainActor () async -> Void = {
            await CloudKitSyncStatusService.accountChangeOrTimeout(.seconds(60))
        },
        waitForAccountChange: @escaping @MainActor () async -> Void = {
            await CloudKitSyncStatusService.accountChangeOrTimeout(.seconds(30 * 60))
        }
    ) async {
        let noAccount: @MainActor () async -> Bool = {
            guard let status = try? await accountStatus() else { return false }
            return FirstDownloadGate.nothingWillDownload(accountStatus: status, cloudKitActive: true)
        }
        guard await noAccount() else { return }
        await waitBeforeRecheck()
        guard FirstDownloadGate.isPending(defaults: defaults), await noAccount() else { return }
        logger.notice("No iCloud account is signed in, so nothing will download: holds lifted for this session")
        // Lifted for the session, not opened: the gate stays armed, so a
        // later launch with an account signed in waits for the download.
        setLifted(true)
        runWhatTheGateHeld(context: context)

        // An account that signs in brings the download: hold for it again.
        var signedIn = false
        while !signedIn, !Task.isCancelled {
            await waitForAccountChange()
            if let status = try? await accountStatus() {
                signedIn = status != .noAccount && status != .couldNotDetermine
            }
        }
        guard signedIn, FirstDownloadGate.isArmed(defaults: defaults) else { return }
        setLifted(false)
        logger.notice("An iCloud account signed in: the holds wait for the first download again")
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
