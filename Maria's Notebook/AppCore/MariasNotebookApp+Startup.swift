//
//  MariasNotebookApp+Startup.swift
//  Maria's Notebook
//
//  What happens once the main window is on screen: bootstrapping the store,
//  wiring sync and background services, and the iOS backgrounding backup.
//

import SwiftUI
import TipKit
#if os(macOS)
import AppKit
#endif

extension MariasNotebookApp {
    // MARK: - Startup

    func performStartupBootstrap() async {
        // Sync initError to error coordinator if not already set
        if databaseErrorCoordinator.error == nil, let error = AppBootstrapping.initError {
            databaseErrorCoordinator.setError(error)
        }

        #if !os(macOS)
        // TipKit's root quick-action tip is temporarily disabled on macOS
        // because it can trigger a SwiftUI update loop when switching views.
        try? Tips.configure([
            .displayFrequency(.weekly)
        ])
        #endif

        // Only bootstrap if the store loaded successfully
        if AppBootstrapping.initError == nil {
            #if os(macOS)
            appDelegate.setCoreDataStack(coreDataStack, dependencies: dependencies)
            #endif
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

            // Index students + lessons into Spotlight (searchable + Siri-referenceable); idempotent, off critical path.
            Task { await SpotlightIndexer.reindexAll() }

            #if os(macOS)
            // Start the MCP server for Claude Desktop if the teacher enabled it.
            MCPServerService.shared.applySettings()
            #endif
        }
    }

    // MARK: - Scene Phase

    /// iOS/iPadOS auto-backup trigger: the app rarely "quits" on iOS, so the
    /// move to the background is the data-protection moment. The backup is
    /// change-gated (persistent history), so idle backgrounding costs nothing.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        #if os(iOS)
        guard phase == .background,
              bootstrapper.state == .ready,
              AppBootstrapping.initError == nil else { return }

        let assertion = BackgroundTaskAssertion()
        assertion.begin(named: "AutoBackup")
        Task { @MainActor in
            await BackupBackgroundTaskManager.schedule()
            await dependencies.autoBackupManager.performBackgroundBackup(
                viewContext: coreDataStack.viewContext
            )
            assertion.end()
        }
        #endif
    }
}
