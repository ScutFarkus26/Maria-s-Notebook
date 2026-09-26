//
//  CosmicDaybookApp+Startup.swift
//  Cosmic Daybook
//
//  What happens once a main window is on screen: surfacing a store-load
//  failure, starting the app-wide services (once per process, see
//  AppServicesLauncher), and the iOS backgrounding backup.
//

import SwiftUI
import TipKit

extension CosmicDaybookApp {
    // MARK: - Startup

    func performStartupBootstrap() async {
        let startup = LaunchSignposts.begin("StartupBootstrap")
        defer { LaunchSignposts.end("StartupBootstrap", startup) }

        // Sync initError to error coordinator if not already set
        if databaseErrorCoordinator.error == nil, let error = AppBootstrapping.initError {
            databaseErrorCoordinator.setError(error)
        }

        #if !os(macOS)
        // TipKit's root quick-action tip is temporarily disabled on macOS
        // because it can trigger a SwiftUI update loop when switching views.
        // A second window's call throws "already configured", which try? drops.
        try? Tips.configure([
            .displayFrequency(.weekly)
        ])
        #endif

        await startAppServicesIfNeeded()
    }

    /// Starts the store bootstrap and the app-wide services unless this
    /// process already has: the first main window's task does it, later
    /// windows find it done, and on the Mac an MCP-only launch (no window)
    /// does it from the app delegate. Nothing starts while the store failed
    /// to load.
    func startAppServicesIfNeeded() async {
        #if os(macOS)
        await servicesLauncher.startIfNeeded(quitBackupDelegate: appDelegate)
        #else
        await servicesLauncher.startIfNeeded()
        #endif
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
        Task {
            await BackupBackgroundTaskManager.schedule()
            await dependencies.autoBackupManager.performBackgroundBackup(
                viewContext: coreDataStack.viewContext
            )
            assertion.end()
        }
        #endif
    }
}
