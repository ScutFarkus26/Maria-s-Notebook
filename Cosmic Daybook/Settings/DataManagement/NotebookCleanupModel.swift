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
        /// Ready to confirm, or blocked with the reason.
        case ready(NotebookJunkCleanup.Counts, blocker: String?)
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
        stage = .ready(counts, blocker: blocker())
    }

    /// Every reason not to start right now, in the guide's words, or nil.
    private func blocker() -> String? {
        #if !os(macOS)
        return "Clean up on your Mac."
        #else
        if isRestoring() { return "A restore is running." }
        if FirstDownloadGate.isPending() { return "This Mac is still downloading the notebook from iCloud." }
        if UserDefaults.standard.object(forKey: ClassroomShareRelease.inProgressKey) != nil {
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
        guard case .ready(let preview, nil) = stage, !preview.isEmpty else { return }
        // Checked again: time passed while the guide read the preview.
        if let reason = blocker() {
            stage = .ready(preview, blocker: reason)
            return
        }

        stage = .backingUp
        do {
            let url = try await verifiedBackup()
            Self.logger.notice("Cleanup: verified backup \(url.lastPathComponent, privacy: .public)")
        } catch {
            stage = .failed(error.localizedDescription)
            return
        }

        stage = .cleaning
        // Counted again inside the run: the preview may be minutes old.
        let done = await pass(apply: true)
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
    private func pass(apply: Bool) async -> NotebookJunkCleanup.Counts? {
        let context = dependencies.coreDataStack.newBackgroundContext()
        return await context.perform {
            let counts = NotebookJunkCleanup.run(in: context, apply: apply)
            guard apply, context.hasChanges else { return counts }
            if context.safeSave() { return counts }
            context.rollback()
            return nil
        }
    }

    // MARK: - Backup

    /// Makes a manual backup and checks it holds at least as many records of every kind the
    /// cleanup touches as the notebook has. Throws with the reason otherwise.
    private func verifiedBackup() async throws -> URL {
        let stack = dependencies.coreDataStack
        let result = await dependencies.autoBackupManager.performManualBackup(viewContext: stack.viewContext)
        guard case .success(_, let url) = result else {
            throw ClassroomShareRelease.BackupCheckError(
                "The backup before cleaning up didn't finish. Nothing was changed."
            )
        }
        let counts = try await Self.backupCounts(at: url)
        for entity in NotebookJunkCleanup.touchedEntities {
            let request = NSFetchRequest<NSDictionary>(entityName: entity)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["id"]
            request.returnsDistinctResults = true
            guard let rows = try? stack.viewContext.fetch(request) else {
                throw ClassroomShareRelease.BackupCheckError(
                    "Couldn't count the notebook's \(entity) records. Nothing was changed."
                )
            }
            guard (counts[entity] ?? 0) >= rows.count else {
                throw ClassroomShareRelease.BackupCheckError(
                    "The backup holds \(counts[entity] ?? 0) \(entity) records, the notebook \(rows.count). "
                        + "Nothing was changed."
                )
            }
        }
        return url
    }

    @concurrent
    private static func backupCounts(at url: URL) async throws -> [String: Int] {
        try BackupReader.verifyStructure(at: url).manifest.entityCounts
    }
}
