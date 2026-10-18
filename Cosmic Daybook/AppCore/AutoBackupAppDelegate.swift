#if os(macOS)
import AppKit
import CoreData
import CloudKit
import OSLog
import SwiftUI

/// AppDelegate that performs the automatic backup before the app quits.
///
/// Uses the supported AppKit mechanism for async work at quit:
/// `applicationShouldTerminate` returns `.terminateLater`, the backup runs as
/// a normal main-actor task, and `reply(toApplicationShouldTerminate:)`
/// resumes termination when it finishes (or when the safety timeout fires).
/// The timeout is a run-loop timer (`QuitReplyGate`), not a task: a quit
/// started from inside a main-actor task starves every other main-actor
/// task until the reply, so a task-based timeout never fired and the app
/// froze mid-quit (2026-10-18). This replaces a semaphore + RunLoop polling loop that blocked the main
/// thread and only let the backup task run during half its duty cycle.
///
/// It also runs an MCP-only launch (see `AppLaunchMode`): with no main window
/// to start them, the app services start here, the idle-quit controller ends
/// the process once Claude has gone, and a Dock click opens the main window.
/// None of that happens on a normal launch.
final class AutoBackupAppDelegate: NSObject, NSApplicationDelegate {
    /// How long quit may be delayed for the backup before we let the app
    /// terminate anyway. Change-gated backups of an idle dataset return in
    /// milliseconds; this bound only matters for large exports.
    private static let quitBackupTimeout: Duration = .seconds(25)

    private var coreDataStack: CoreDataStack?
    private var autoBackupManager: AutoBackupManager?
    /// Only for an MCP-only launch.
    private var idleQuitController: MCPIdleQuitController?

    func setCoreDataStack(_ stack: CoreDataStack, dependencies: AppDependencies) {
        self.coreDataStack = stack
        self.autoBackupManager = dependencies.autoBackupManager
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppLaunchMode.current == .mcpOnly, !AppBootstrapping.isRunningUnitTests else { return }
        let controller = MCPIdleQuitController()
        idleQuitController = controller
        controller.start()
        // The main window's task is what normally starts the services, and an
        // MCP-only launch suppresses the main window. The MCP server starts
        // with them, once the notebook's stores are open.
        Task {
            let notebook = await NotebookOpener.shared.open()
            await notebook.servicesLauncher.startIfNeeded(quitBackupDelegate: self)
        }
    }

    /// A Dock click (or opening the app again from Finder) in an MCP-only
    /// launch. That launch suppressed the main window scene, and SwiftUI
    /// consults the same launch behavior here, so with no window open it
    /// would present nothing: open the main window, as a normal launch's
    /// reopen does, and tell AppKit it is handled. With a window open
    /// (minimized counts), AppKit's own handling proceeds. The windows are
    /// counted rather than read from `hasVisibleWindows`, which can count a
    /// floating panel.
    ///
    /// A normal launch never sees this method: `responds(to:)` hides it, so
    /// AppKit and SwiftUI handle reopen exactly as they did before it existed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard MCPIdleQuitController.openWindowCount() == 0 else { return true }
        return !MainWindowOpener.shared.openMainWindow()
    }

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(applicationShouldHandleReopen(_:hasVisibleWindows:)) {
            return AppLaunchMode.current == .mcpOnly
        }
        return super.responds(to: aSelector)
    }

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        ShareInvitationInbox.deliver(metadata)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coreDataStack,
              let autoBackupManager,
              autoBackupManager.enabled else { return .terminateNow }

        let viewContext = coreDataStack.viewContext
        // The gate sends the one reply AppKit needs: when the backup ends, or
        // at the timeout, so a hung backup never holds the quit hostage. Its
        // timer keeps it alive until then.
        let gate = QuitReplyGate(timeout: Self.quitBackupTimeout) { timedOut in
            if timedOut {
                Logger.backup.notice("Quit backup still running after the time limit; quitting anyway")
            }
            sender.reply(toApplicationShouldTerminate: true)
        }

        Task {
            await autoBackupManager.performBackupOnQuit(viewContext: viewContext)
            gate.workFinished()
        }

        return .terminateLater
    }
}
#endif
