#if os(macOS)
import AppKit
import CoreData
import CloudKit
import SwiftUI

/// AppDelegate that performs the automatic backup before the app quits.
///
/// Uses the supported AppKit mechanism for async work at quit:
/// `applicationShouldTerminate` returns `.terminateLater`, the backup runs as
/// a normal main-actor task, and `reply(toApplicationShouldTerminate:)`
/// resumes termination when it finishes (or when the safety timeout fires).
/// This replaces a semaphore + RunLoop polling loop that blocked the main
/// thread and only let the backup task run during half its duty cycle.
@MainActor
final class AutoBackupAppDelegate: NSObject, NSApplicationDelegate {
    /// How long quit may be delayed for the backup before we let the app
    /// terminate anyway. Change-gated backups of an idle dataset return in
    /// milliseconds; this bound only matters for large exports.
    private static let quitBackupTimeout: Duration = .seconds(25)

    private var coreDataStack: CoreDataStack?
    private var autoBackupManager: AutoBackupManager?
    private var didReplyToTermination = false

    func setCoreDataStack(_ stack: CoreDataStack, dependencies: AppDependencies) {
        self.coreDataStack = stack
        self.autoBackupManager = dependencies.autoBackupManager
    }

    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        NotificationCenter.default.post(
            name: .didAcceptCloudKitShare,
            object: metadata
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let coreDataStack,
              let autoBackupManager,
              autoBackupManager.enabled else { return .terminateNow }

        let viewContext = coreDataStack.viewContext
        didReplyToTermination = false

        Task { @MainActor in
            await autoBackupManager.performBackupOnQuit(viewContext: viewContext)
            self.replyToTerminationOnce(sender)
        }

        // Safety net: never hold the quit hostage to a hung backup.
        Task { @MainActor in
            try? await Task.sleep(for: Self.quitBackupTimeout)
            self.replyToTerminationOnce(sender)
        }

        return .terminateLater
    }

    /// AppKit must receive exactly one reply per `.terminateLater`.
    private func replyToTerminationOnce(_ application: NSApplication) {
        guard !didReplyToTermination else { return }
        didReplyToTermination = true
        application.reply(toApplicationShouldTerminate: true)
    }
}
#endif
