//
//  AppServicesLauncher.swift
//  Cosmic Daybook
//
//  Starts the app-wide services once per process. They used to start from
//  every main window's `.task`, so each extra window (File > New Window, or
//  a second iPad scene) reconfigured sync-status monitoring, restarted the
//  backup loop, re-registered for pushes, re-applied the Claude Desktop
//  setting and ran another Spotlight pass. Only the store bootstrap itself
//  was guarded. Now the first caller starts everything and later callers
//  return at once; on the Mac that first caller can be the app delegate,
//  when an MCP-only launch has no window at all.
//

import AppIntents
import OSLog
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Whether a caller should start the app-wide services. Pure, so the
/// once-per-process rule is testable without starting anything.
nonisolated struct AppServicesStartGate: Sendable {
    enum Decision: Equatable, Sendable {
        /// The first caller since launch with the store loaded: start everything.
        case start
        /// An earlier caller already started them (or is still starting them).
        case alreadyStarted
        /// The store failed to load, so nothing starts. Nothing is latched
        /// either: a later caller finds the services unstarted, exactly as a
        /// later window's startup used to.
        case storeUnavailable
    }

    private(set) var hasStarted = false

    mutating func claim(storeLoaded: Bool) -> Decision {
        if hasStarted { return .alreadyStarted }
        guard storeLoaded else { return .storeUnavailable }
        hasStarted = true
        return .start
    }
}

/// Owns the one start of the app-wide services: the store bootstrap, sync
/// status monitoring, push registration, memory-pressure monitoring, the
/// interval backup loop, the Spotlight pass and (macOS) the MCP server.
@MainActor
final class AppServicesLauncher {
    /// The launcher the app registered in `init`. The macOS app delegate
    /// starts the services through it for an MCP-only launch, which has no
    /// window whose `.task` could.
    private(set) static var current: AppServicesLauncher?

    /// How long after start-up the Spotlight pass waits, the same pause the
    /// post-launch migrations take, so it never competes with the first render.
    static let spotlightDelay: Duration = .seconds(3)

    private static let logger = Logger.startup

    private let coreDataStack: CoreDataStack
    private let dependencies: AppDependencies
    private let bootstrapper: AppBootstrapper
    private var gate = AppServicesStartGate()
    private var invitationObserver: (any NSObjectProtocol)?

    init(coreDataStack: CoreDataStack, dependencies: AppDependencies, bootstrapper: AppBootstrapper) {
        self.coreDataStack = coreDataStack
        self.dependencies = dependencies
        self.bootstrapper = bootstrapper
    }

    static func register(_ launcher: AppServicesLauncher) {
        current = launcher
    }

    #if os(macOS)
    /// Starts the services unless an earlier caller did. The quit-backup
    /// delegate gets the stack and backup manager first, as it always has,
    /// so a quit backup works from the moment the store is up.
    func startIfNeeded(quitBackupDelegate: AutoBackupAppDelegate) async {
        guard claim() else { return }
        quitBackupDelegate.setCoreDataStack(coreDataStack, dependencies: dependencies)
        await startServices()
    }
    #else
    /// Starts the services unless an earlier caller did.
    func startIfNeeded() async {
        guard claim() else { return }
        await startServices()
    }
    #endif

    /// Claimed synchronously, before the first suspension, so a second
    /// window whose task runs while the bootstrap is still awaiting finds the
    /// services already claimed instead of configuring them a second time.
    private func claim() -> Bool {
        switch gate.claim(storeLoaded: AppBootstrapping.initError == nil) {
        case .start:
            return true
        case .alreadyStarted:
            return false
        case .storeUnavailable:
            Self.logger.notice("App services not started — the store failed to load")
            return false
        }
    }

    private func startServices() async {
        await bootstrapper.bootstrap(coreDataStack: coreDataStack)

        // Configure CloudKit sync status monitoring
        CloudKitSyncStatusService.shared.configure(with: coreDataStack)

        // Register for remote notifications so CloudKit can push sync events.
        // NSPersistentCloudKitContainer handles incoming notifications
        // internally — we just need to ensure the app is registered.
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif

        // PERFORMANCE: Start memory pressure monitoring
        // This allows the app to proactively clear caches before being terminated
        _ = dependencies.memoryPressureMonitor

        // Start the interval auto-backup loop (no-op unless the user
        // enabled scheduled backups). This also hands the manager its
        // context so toggling the setting later can restart the loop.
        dependencies.autoBackupManager.startScheduledBackups(viewContext: coreDataStack.viewContext)

        scheduleSpotlightPass()
        collectShareInvitations()

        #if os(macOS)
        // Start the MCP server for Claude Desktop if the teacher enabled it.
        // The tools that reach past Core Data (backups, report drafts)
        // find the app's services through this registration.
        MCPAppServices.register(dependencies)
        MCPServerService.shared.applySettings()
        #endif
    }

    /// The sharing service is built on first use, normally by Settings →
    /// Classroom, so an accepted invitation could otherwise wait unanswered in
    /// `ShareInvitationInbox`. Building the service is what collects it — the
    /// one already waiting at launch, and any that arrives later.
    private func collectShareInvitations() {
        if ShareInvitationInbox.hasPending { _ = dependencies.classroomSharingService }
        invitationObserver = NotificationCenter.default.addObserver(
            forName: .didAcceptCloudKitShare,
            object: nil,
            queue: .main
        ) { [dependencies] _ in
            MainActor.assumeIsolated { _ = dependencies.classroomSharingService }
        }
    }

    /// Index students + lessons into Spotlight (searchable + Siri-referenceable);
    /// idempotent and change-gated. Self-initiated, so it waits out the first
    /// render at utility priority instead of starting inside it.
    private func scheduleSpotlightPass() {
        Task(priority: .utility) {
            try? await Task.sleep(for: Self.spotlightDelay)
            // Teach Siri the class's names for phrases like "Mark Maya here".
            // Not change-gated: the system reads the names back from
            // `suggestedEntities()` itself, and a new install must learn them.
            CosmicDaybookAppShortcuts.updateAppShortcutParameters()
            // A hot device or Low Power Mode skips it for this launch; the pass
            // is change-gated, so the next launch indexes everything anyway.
            if EnergyPolicy.shared.shouldDeferMaintenance {
                Self.logger.notice("Spotlight reindex skipped — device hot or in Low Power Mode")
                return
            }
            await SpotlightIndexer.reindexAll()
        }
    }
}
