import CoreData
import Foundation
import OSLog

/// Drives "Clean Up Old Records" (`NotebookJunkCleanup`): the preview, the checks, the
/// verified backup, the run and its report. Mac only, like Remove Last Year: the Mac is the
/// first device a build reaches, and the other devices take the deletes from iCloud.
@Observable @MainActor
final class NotebookCleanupModel {
    enum Stage: Equatable {
        case loading
        /// Ready to confirm (unless `blocker` says why not).
        case ready(NotebookJunkCleanup.Counts)
        case backingUp
        case cleaning
        case finished(NotebookJunkCleanup.Counts)
        case failed(String)
    }

    private(set) var stage: Stage = .loading
    private let dependencies: AppDependencies
    private let isRestoring: () -> Bool
    private static let logger = Logger.databaseMaintenance

    init(dependencies: AppDependencies, isRestoring: @escaping () -> Bool) {
        self.dependencies = dependencies
        self.isRestoring = isRestoring
    }

    var isWorking: Bool {
        switch stage {
        case .backingUp, .cleaning: return true
        default: return false
        }
    }

    // MARK: - Preview

    func load() async {
        stage = .loading
        let counts = await pass(apply: false) ?? NotebookJunkCleanup.Counts()
        stage = .ready(counts)
    }

    /// Every reason not to start right now, in the guide's words, or nil. Read live, so the
    /// sheet's notice clears by itself when the sync it waits on finishes.
    var blocker: String? {
        #if !os(macOS)
        return "Clean up on your Mac."
        #else
        if isRestoring() { return "A restore is running." }
        if FirstDownloadGate.isPending() { return "This Mac is still downloading the notebook from iCloud." }
        // Records arriving from iCloud can land a batch ahead of the ones they belong to
        // (work steps before their work), and look like junk until the rest arrives.
        let sync = CloudKitSyncStatusService.shared
        if sync.isImportingFromCloud || sync.isSyncing {
            return "iCloud is syncing this Mac right now. You can start once it's done."
        }
        if ClassroomShareRelease.stoppedPartway {
            return "Removing last year from the share stopped partway. Finish it first, in Settings › Classroom."
        }
        if dependencies.coreDataStack.isCloudKitActive, let reason = ClassroomShareRelease.syncBlocker() {
            return reason
        }
        return ClassroomShareRelease.anotherCopyBlocker()
        #endif
    }

    // MARK: - Running

    func start() async {
        // Checked again at the press: the sheet may not have redrawn since it changed.
        guard case .ready(let preview) = stage, !preview.isEmpty, blocker == nil else { return }

        stage = .backingUp
        do {
            let url = try await verifiedBackup(of: preview)
            Self.logger.notice("Cleanup: verified backup \(url.lastPathComponent, privacy: .public)")
        } catch {
            stage = .failed(error.localizedDescription)
            return
        }

        stage = .cleaning
        // Counted again inside the run, and held to what the preview named: anything that
        // arrived from iCloud since isn't junk the guide saw, nor in the backup.
        let done = await pass(apply: true, within: preview)
        guard let done else {
            stage = .failed("The cleanup couldn't save. Nothing was changed.")
            return
        }
        Self.logger.notice(
            "Cleanup: removed \(done.removed, privacy: .public), changed \(done.changed, privacy: .public)"
        )
        for line in done.lines {
            Self.logger.notice("Cleanup: \(line, privacy: .public)")
        }
        stage = .finished(done)
    }

    /// One pass on a background context. With `apply`, saves, and returns nil when the save
    /// failed (its changes are rolled back).
    private func pass(
        apply: Bool, within preview: NotebookJunkCleanup.Counts? = nil
    ) async -> NotebookJunkCleanup.Counts? {
        let context = dependencies.coreDataStack.newBackgroundContext()
        return await context.perform {
            let counts = NotebookJunkCleanup.run(in: context, apply: apply, within: preview)
            guard apply, context.hasChanges else { return counts }
            if context.safeSave() { return counts }
            context.rollback()
            return nil
        }
    }

    // MARK: - Backup

    /// Makes a manual backup and checks it holds, by `id`, every record the preview names
    /// to remove or change. Throws with the reason otherwise.
    private func verifiedBackup(of preview: NotebookJunkCleanup.Counts) async throws -> URL {
        let stack = dependencies.coreDataStack
        let result = await dependencies.autoBackupManager.performManualBackup(viewContext: stack.viewContext)
        guard case .success(_, let url) = result else {
            throw ClassroomShareRelease.BackupCheckError(
                "The backup before cleaning up didn't finish. Nothing was changed."
            )
        }
        try await BackupRecordCheck.check(
            url, holds: Array(preview.removing.union(preview.changing)), context: stack.newBackgroundContext()
        )
        return url
    }
}
