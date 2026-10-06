//
//  CosmicDaybookApp+Startup.swift
//  Cosmic Daybook
//
//  What happens once a main window is on screen: surfacing a store-load
//  failure, starting the app-wide services (once per process, see
//  AppServicesLauncher), and the iOS backgrounding trim and backup.
//

import SwiftUI
import TipKit

extension CosmicDaybookApp {
    // MARK: - Startup

    func performStartupBootstrap() async {
        // The stores open off the main thread; the window says "Opening your
        // notebook…" until they have (or the error screen, if they can't).
        let notebook = await notebookOpener.open()

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

        await startAppServicesIfNeeded(in: notebook)
    }

    /// Starts the store bootstrap and the app-wide services unless this
    /// process already has: the first main window's task does it, later
    /// windows find it done, and on the Mac an MCP-only launch (no window)
    /// does it from the app delegate. Nothing starts while the store failed
    /// to load.
    func startAppServicesIfNeeded(in notebook: OpenNotebook) async {
        #if os(macOS)
        await notebook.servicesLauncher.startIfNeeded(quitBackupDelegate: appDelegate)
        #else
        await notebook.servicesLauncher.startIfNeeded()
        #endif
    }

    // MARK: - Scene Phase

    /// iOS/iPadOS auto-backup trigger: the app rarely "quits" on iOS, so the
    /// move to the background is the data-protection moment. The backup is
    /// change-gated (persistent history), so idle backgrounding costs nothing.
    /// It is also the idle trim's moment: memory held while suspended decides
    /// which app iOS ends first.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        // A second copy on the Mac takes over the primary's jobs once it is
        // the only copy left (`AppBootstrapper.takeOverIfAlone`).
        if phase == .active, let notebook = notebookOpener.notebook {
            AppBootstrapper.takeOverIfAlone(coreDataStack: notebook.coreDataStack)
        }
        #if os(iOS)
        guard phase == .background else { return }
        // Nothing while the notebook is still opening (a launch's first
        // moments): the trim and the backup both belong to it.
        guard let notebook = notebookOpener.notebook else { return }
        // Before the backup starts, and whatever the store's state: the album
        // library's rebuildable caches don't depend on it.
        notebook.dependencies.trimIdleMemory(reason: .appBackgrounded)
        guard bootstrapper.state == .ready,
              AppBootstrapping.initError == nil else { return }

        let assertion = BackgroundTaskAssertion()
        assertion.begin(named: "AutoBackup")
        // Self-initiated work, so utility priority rather than the main
        // thread's, which it used to inherit.
        Task(priority: .utility) {
            await BackupBackgroundTaskManager.schedule()
            await notebook.dependencies.autoBackupManager.performBackgroundBackup(
                viewContext: notebook.coreDataStack.viewContext
            )
            assertion.end()
        }
        #endif
    }
}
