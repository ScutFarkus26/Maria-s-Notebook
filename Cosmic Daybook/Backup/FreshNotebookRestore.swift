// FreshNotebookRestore.swift
// The database-error screen's restore: a backup into a new notebook, with the
// notebook that wouldn't open moved aside and kept.

import CoreData
import Foundation
import OSLog

/// Restores a backup when the notebook on this device won't open: the
/// database-error screen's "Restore from a Backup…".
///
/// A restore writes into an open store, and this notebook won't open. So the
/// backup goes into a new notebook made for it, in a folder of its own beside
/// the stores (`Restoring`). Only once that restore has saved is the notebook
/// that wouldn't open moved aside, into a dated folder beside the stores, and
/// the new one moved into its place. The old one is kept, never deleted: it
/// may hold work done since the backup. A restore that fails or is refused
/// leaves it exactly where it was. The next launch opens the restored notebook
/// as usual.
///
/// **Only while iCloud sync is off on this device.** A restored store has none
/// of iCloud's bookkeeping, so with sync on the next launch would download the
/// notebook in iCloud into it beside the restored records: every record twice.
/// With sync on the screen says to re-download from iCloud instead, and to
/// restore from Settings once the download has finished
/// (`DatabaseErrorCoordinator.restoreOffer`), and `run` refuses. The new
/// stores are opened without iCloud, and a restore never turns sync on
/// (`EnableCloudKitSync` isn't a setting backups carry), so no download ever
/// reaches them. That is why the first-download refusal doesn't apply here
/// (`BackupCoordinator.RestoreTarget.freshNotebook`).
///
/// Moving store files is store surgery: it runs with the stores held
/// exclusively (`StoreProcessLock`), so no other copy of the app has them
/// open, and never while this copy has them open itself. Each store moves
/// whole: its file, its journal (`-wal`, `-shm`) and the folder Core Data
/// keeps its large attachments in, together, by renaming in the same folder.
/// Nothing is copied piecemeal (QA1809) and nothing of the guide's is deleted.
struct FreshNotebookRestore {
    private static let logger = Logger.backup

    /// Why a restore here was refused or undone. In every case the notebook
    /// that wouldn't open is where it was.
    nonisolated enum Failure: ExplainedBackupError, Equatable {
        /// iCloud sync is on (see the type's notes).
        case syncIsOn
        /// Another copy of the app has the notebook open.
        case anotherCopyOpen
        /// This copy of the app has the notebook open after all.
        case notebookOpen
        /// A restore here is already under way.
        case alreadyRunning
        /// The restored notebook couldn't be moved into place.
        case couldNotSwap
        /// …and the notebook couldn't all be moved back: it is in this folder.
        case couldNotPutBack(folderName: String)

        var errorDescription: String? {
            switch self {
            case .syncIsOn:
                return FreshNotebookRestore.syncOnGuidance
            case .anotherCopyOpen:
                return "Another copy of Cosmic Daybook has your notebook open. Quit it, then try again."
            case .notebookOpen:
                return "Cosmic Daybook has your notebook open right now, so nothing was restored over it. "
                    + "Quit the app and open it again."
            case .alreadyRunning:
                return "A restore is already under way. Wait for it to finish."
            case .couldNotSwap:
                return "Couldn't put the restored notebook in place, so your notebook on this device "
                    + "was left as it was. Try again."
            case .couldNotPutBack(let folderName):
                return "Couldn't put the restored notebook in place, or move yours all the way back. "
                    + "Your notebook is safe in a folder named \u{201C}\(folderName)\u{201D} beside the app's "
                    + "data, and nothing was deleted. Get help putting it back before opening the app again."
            }
        }
    }

    /// What the screen says, in place of the button, while iCloud sync is on.
    nonisolated static let syncOnGuidance = "To restore a backup, first choose "
        + "\u{201C}Re-download from iCloud\u{2026}\u{201D}. "
        + "When your notebook has finished downloading, restore the backup from Settings "
        + "\u{203A} Sync and backup."

    /// A finished restore.
    struct Result {
        let summary: BackupOperationSummary
        /// Where the notebook that wouldn't open was moved; nil when there
        /// were no store files to move.
        let keptFolder: URL?
    }

    /// The notebook's two stores, in the order the app adds them (a new
    /// record goes to the first store that has its entity: the private one),
    /// named as `CoreDataStack.privateStoreURL()` and `sharedStoreURL()` name them.
    static let stores: [(fileName: String, configuration: String)] = [
        ("private.sqlite", CoreDataStack.privateConfiguration),
        ("shared.sqlite", CoreDataStack.sharedConfiguration)
    ]

    /// The folder the new notebook is made in, beside the stores.
    static let stagingFolderName = "Restoring"

    /// The dated folder the notebook that wouldn't open is moved to.
    static func keptFolderName(at date: Date) -> String {
        "Set aside " + date.ISO8601Format().replacingOccurrences(of: ":", with: ".")
    }

    /// The store files' folder; the lock lives in it.
    let lock: StoreProcessLock
    let defaults: UserDefaults
    let model: NSManagedObjectModel
    /// Whether this copy of the app has the store at a URL open.
    let isOpenInThisCopy: @MainActor (URL) -> Bool
    /// Moves one file or folder (`moveFileNormally`; tests make one fail).
    let moveFile: @MainActor (URL, URL) throws -> Void
    let now: Date

    var directory: URL { lock.directory }

    init(
        lock: StoreProcessLock,
        defaults: UserDefaults,
        model: NSManagedObjectModel,
        isOpenInThisCopy: @escaping @MainActor (URL) -> Bool = FreshNotebookRestore.appHasStoreOpen,
        moveFile: @escaping @MainActor (URL, URL) throws -> Void = FreshNotebookRestore.moveFileNormally,
        now: Date = Date()
    ) {
        self.lock = lock
        self.defaults = defaults
        self.model = model
        self.isOpenInThisCopy = isOpenInThisCopy
        self.moveFile = moveFile
        self.now = now
    }

    /// This device's notebook, in this build's CloudKit environment.
    static func forThisDevice() throws -> FreshNotebookRestore {
        FreshNotebookRestore(lock: CoreDataStack.storeLock, defaults: .standard, model: try CoreDataStack.sharedModel())
    }

    /// Whether the app's own stack has the store at `url` open. Behind the
    /// database-error screen it holds only an in-memory store, unless the
    /// failure was simulated (Debug).
    static func appHasStoreOpen(_ url: URL) -> Bool {
        guard let stack = AppBootstrapping._sharedCoreDataStack else { return false }
        let path = url.standardizedFileURL.path
        return stack.container.persistentStoreCoordinator.persistentStores.contains {
            $0.url?.standardizedFileURL.path == path
        }
    }

    /// Renames `source` to `destination`, on the same volume.
    static func moveFileNormally(_ source: URL, _ destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    /// The new notebook's stores in `folder`, described as a launch with
    /// iCloud sync off describes the app's own (`CoreDataStack.makeStoreDescriptions`):
    /// migration options and history tracking, and no CloudKit options, so
    /// nothing downloads into them.
    static func storeDescriptions(in folder: URL) -> [NSPersistentStoreDescription] {
        stores.map { store in
            let description = CoreDataStack.makeStoreDescription(
                url: folder.appendingPathComponent(store.fileName),
                configuration: store.configuration
            )
            CoreDataStack.enableHistoryTracking(description)
            return description
        }
    }

    /// Everything on disk that belongs to the store at `storeURL`: the file,
    /// its journal, and `.<name>_SUPPORT`, where Core Data keeps attributes
    /// stored outside the database (attachments, album ink).
    static func storeItems(for storeURL: URL) -> [URL] {
        let name = storeURL.deletingPathExtension().lastPathComponent
        let support = storeURL.deletingLastPathComponent().appendingPathComponent(".\(name)_SUPPORT", isDirectory: true)
        return CoreDataStack.storeFiles(for: storeURL) + [support]
    }

    // MARK: - Restoring

    /// Restores the backup at `url` into a new notebook and puts it in place
    /// of the one that wouldn't open (see the type's notes). Throws
    /// `Failure` when refused or undone, and the restore's own errors; either
    /// way the notebook that wouldn't open is where it was.
    func run(
        backup url: URL,
        restoringWith coordinator: BackupCoordinator,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> Result {
        guard !CoreDataStack.syncPreferred(in: defaults) else { throw Failure.syncIsOn }
        let liveStores = Self.stores.map { directory.appendingPathComponent($0.fileName) }
        guard !liveStores.contains(where: isOpenInThisCopy) else { throw Failure.notebookOpen }
        guard !lock.holdsExclusive else { throw Failure.alreadyRunning }
        guard lock.tryExclusive() else { throw Failure.anotherCopyOpen }
        defer { lock.releaseExclusive() }

        let staging = directory.appendingPathComponent(Self.stagingFolderName, isDirectory: true)
        // An attempt that never finished may have left its new notebook:
        // made from a backup file, ours alone, and never opened by the app.
        try Self.clearStaging(staging)
        defer {
            do {
                try Self.clearStaging(staging)
            } catch {
                Self.logger.warning("Couldn't clear the restore's staging folder: \(error.localizedDescription)")
            }
        }

        let summary = try await restore(url, into: staging, with: coordinator, progress: progress)
        let kept = try moveIntoPlace(from: staging)
        // What belonged to the old stores (history positions, the share's
        // waiting list, repair ledgers) goes, as after a Re-download.
        CoreDataStack.clearLocalCacheResetFlags(in: defaults)
        let keptName = kept?.lastPathComponent ?? "nothing to keep"
        Self.logger.notice("Restored a backup into a fresh notebook; the old one is in \(keptName, privacy: .public)")
        return Result(summary: summary, keptFolder: kept)
    }

    /// The backup restored into new stores in `staging`, saved and closed.
    private func restore(
        _ url: URL,
        into staging: URL,
        with coordinator: BackupCoordinator,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let container = NSPersistentContainer(name: CoreDataStack.modelName, managedObjectModel: model)
        container.persistentStoreDescriptions = Self.storeDescriptions(in: staging)
        var loadError: (any Error)?
        container.loadPersistentStores { _, error in
            if let error, loadError == nil { loadError = error }
        }
        do {
            if let loadError { throw loadError }
            // Stamped as every store this build opens is (`restampSchemaVersion`).
            CoreDataStack.restampSchemaVersion(in: container)
            let context = container.viewContext
            let summary = try await coordinator.importBackup(
                viewContext: context, from: url, mode: .merge, target: .freshNotebook, progress: progress
            )
            // The steps after the restore's own save (locks carried over,
            // Restock levels) save as they go; anything left goes now.
            if context.hasChanges { try context.save() }
            guard Self.close(container) else { throw Failure.couldNotSwap }
            return summary
        } catch {
            _ = Self.close(container)
            throw error
        }
    }

    /// Moves the notebook that wouldn't open aside and the restored one from
    /// `staging` into its place, every store whole. Undoes every move if one
    /// fails. Returns the folder the old notebook went to.
    private func moveIntoPlace(from staging: URL) throws -> URL? {
        let fileManager = FileManager.default
        let kept = Self.unusedFolder(named: Self.keptFolderName(at: now), in: directory)
        var moves: [(from: URL, to: URL)] = []
        do {
            for store in Self.stores {
                for item in Self.storeItems(for: directory.appendingPathComponent(store.fileName))
                where fileManager.fileExists(atPath: item.path) {
                    try fileManager.createDirectory(at: kept, withIntermediateDirectories: true)
                    let target = kept.appendingPathComponent(item.lastPathComponent)
                    try moveFile(item, target)
                    moves.append((item, target))
                }
            }
            let keptAny = !moves.isEmpty
            for store in Self.stores {
                for item in Self.storeItems(for: staging.appendingPathComponent(store.fileName))
                where fileManager.fileExists(atPath: item.path) {
                    let target = directory.appendingPathComponent(item.lastPathComponent)
                    try moveFile(item, target)
                    moves.append((item, target))
                }
            }
            return keptAny ? kept : nil
        } catch {
            Self.logger.error("Restore: couldn't move the notebooks into place: \(error.localizedDescription)")
            var allBack = true
            for move in moves.reversed() {
                do {
                    try moveFile(move.to, move.from)
                } catch {
                    allBack = false
                    let name = move.from.lastPathComponent
                    let reason = error.localizedDescription
                    Self.logger.fault("Restore: couldn't move \(name, privacy: .public) back: \(reason)")
                }
            }
            guard allBack else {
                // Leave a note beside the stores, so the next launch refuses to
                // make an empty notebook where this one belongs.
                Self.markUnfinishedSwap(folder: kept, in: directory)
                throw Failure.couldNotPutBack(folderName: kept.lastPathComponent)
            }
            if (try? fileManager.contentsOfDirectory(atPath: kept.path))?.isEmpty == true {
                try? fileManager.removeItem(at: kept)
            }
            throw Failure.couldNotSwap
        }
    }

    // MARK: - An unfinished swap

    /// Leaves `CoreDataStack.unfinishedRestoreMarkerName` beside the stores,
    /// naming the folder the notebook is in (`CoreDataStack.unfinishedRestoreFolder`).
    private static func markUnfinishedSwap(folder: URL, in directory: URL) {
        let marker = directory.appendingPathComponent(CoreDataStack.unfinishedRestoreMarkerName)
        do {
            try folder.lastPathComponent.write(to: marker, atomically: true, encoding: .utf8)
        } catch {
            logger.fault("Restore: couldn't leave the unfinished-swap note: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Closes every store `container` opened; false if one stays open.
    private static func close(_ container: NSPersistentContainer) -> Bool {
        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            do {
                try coordinator.remove(store)
            } catch {
                logger.error("Restore: couldn't close the new notebook: \(error.localizedDescription)")
            }
        }
        return coordinator.persistentStores.isEmpty
    }

    /// Destroys the stores a restore made in `staging` (through Core Data,
    /// `CoreDataStack.resetStores`) and removes the folder.
    private static func clearStaging(_ staging: URL) throws {
        guard FileManager.default.fileExists(atPath: staging.path) else { return }
        try CoreDataStack.resetStores(stores.map { staging.appendingPathComponent($0.fileName) })
        try FileManager.default.removeItem(at: staging)
    }

    /// `name` in `directory`, or `name 2`, `name 3`… when it's taken.
    private static func unusedFolder(named name: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent(name, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }
}
