import CoreData
import Foundation
import OSLog
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// Back up now, from Settings › Backups: written straight into the backup
// folder, or saved where the guide says when the folder can't take it.

extension SettingsViewModel {

    /// A name in `folder` no file has, counting iCloud files not downloaded
    /// to this device yet.
    private func uniquedURL(in folder: URL, base: String, ext: String) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var i = 2
        while UbiquitousFile.isAvailable(candidate) {
            candidate = folder.appendingPathComponent("\(base) (\(i))").appendingPathExtension(ext)
            i += 1
        }
        return candidate
    }

    /// How long copying a finished backup to where the guide saved it may
    /// wait for the file to be free (another app or iCloud holding it).
    private static let saveCopyTimeout: Duration = .seconds(60)

    /// What the banner says once a backup is saved as `fileName`: the name,
    /// the export's notes (photos left out, files never in backups), and a
    /// warning while the notebook is still downloading from iCloud (#13, #14).
    static func savedText(
        fileName: String, notes: [String], firstDownloadPending: Bool = FirstDownloadGate.isPending()
    ) -> String {
        var sentences = ["Saved backup as \(fileName)."] + notes
        if firstDownloadPending { sentences.append(AutoBackupManager.firstDownloadWarning) }
        return sentences.joined(separator: " ")
    }

    /// A failure writing straight into the backup folder that writing
    /// somewhere else could get past (the folder full, gone or read-only),
    /// rather than one with the notebook or the key, which would fail again.
    private static func isDestinationProblem(_ error: Error) -> Bool {
        !(error is BackupWriter.WriterError) && !(error is BackupEncryptionKeyStore.KeyStoreError)
            && !(error is CancellationError)
    }

    // MARK: - Export
    /// Back up now. With a backup folder (the usual case), the backup is
    /// written straight into it the way automatic backups are: a hidden temp
    /// file beside the final name, read back and checked, then moved into
    /// place under a coordinated write. Until 2026-11 it was written to the
    /// temporary folder and copied over with a plain `copyItem` on the main
    /// thread, so a full disk or a quit mid-copy left a cut-short file under
    /// the real name, and the window froze while a photo-heavy backup copied
    /// (bug hunt 2026-11-02 #9). Only when the folder can't take it does the
    /// backup go to the temporary folder, for the Mac's Save panel or the iOS
    /// file exporter.
    func performExport(viewContext: NSManagedObjectContext) async {
        // However it ends: a backup that failed part-way left the card's
        // progress bar up, and Back up now and Import off, until a relaunch.
        defer { backupProgress = 0; backupMessage = "" }
        backupProgress = 0; backupMessage = "Preparing…"; resultSummary = nil
        let name = defaultBackupFilename()
        let progress: BackupService.ProgressCallback = { [weak self] progress, message in
            self?.backupProgress = progress
            self?.backupMessage = message
        }
        if let folder = BackupDestination.resolveDefaultFolder() {
            let needsAccess = folder.startAccessingSecurityScopedResource()
            defer { if needsAccess { folder.stopAccessingSecurityScopedResource() } }
            let destination = uniquedURL(in: folder, base: name, ext: BackupFile.fileExtension)
            do {
                let summary = try await coordinator.exportBackup(
                    viewContext: viewContext, to: destination, progress: progress
                )
                backupSaved(as: destination.lastPathComponent, notes: summary.notes)
                return
            } catch where Self.isDestinationProblem(error) {
                let raw = String(describing: error)
                Logger.settings.warning(
                    "Backup folder couldn't take the backup; asking where to save it: \(raw, privacy: .public)"
                )
            } catch {
                showBackupFailure(error, operation: "save the backup")
                return
            }
        }
        await exportForSaving(viewContext: viewContext, name: name, progress: progress)
    }

    /// The banner, the last-backup date and the toast for a saved backup.
    private func backupSaved(as fileName: String, notes: [String]) {
        setLastBackupNow()
        let pending = FirstDownloadGate.isPending()
        resultSummary = BackupResultNote(
            text: Self.savedText(fileName: fileName, notes: notes, firstDownloadPending: pending),
            tone: pending ? .neutral : .success
        )
        dependencies.toastService.showSuccess("Backup saved successfully")
        loadDefaultFolderName()
    }

    /// The backup folder couldn't take the backup: it is written to the
    /// temporary folder, then saved where the guide says (the Mac's Save
    /// panel) or handed to the iOS file exporter.
    private func exportForSaving(
        viewContext: NSManagedObjectContext, name: String, progress: @escaping BackupService.ProgressCallback
    ) async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(BackupFile.fileExtension)
        safeRemoveItem(at: tmp, context: "performExport-cleanup")
        let summary: BackupOperationSummary
        do {
            summary = try await coordinator.exportBackup(viewContext: viewContext, to: tmp, progress: progress)
        } catch {
            showBackupFailure(error, operation: "save the backup")
            return
        }
#if os(macOS)
        defer { safeRemoveItem(at: tmp, context: "performExport-macOSCleanup") }
        let panel = NSSavePanel()
        panel.title = "Save Backup"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(filenameExtension: BackupFile.fileExtension) ?? .data]
        panel.nameFieldStringValue = tmp.lastPathComponent

        guard panel.runModal() == .OK, let chosen = panel.url else {
            resultSummary = BackupResultNote(text: "Backup canceled.", tone: .neutral)
            return
        }
        let finalURL = chosen.pathExtension.isEmpty ? chosen.appendingPathExtension(BackupFile.fileExtension) : chosen
        do {
            // Off the main thread, copied beside the destination, checked,
            // then swapped in: never a cut-short file under the chosen name.
            try await UbiquitousFile.coordinatedCopy(from: tmp, replacing: finalURL, timeout: Self.saveCopyTimeout)
            backupSaved(as: finalURL.lastPathComponent, notes: summary.notes)
        } catch {
            showBackupFailure(error, operation: "save the backup")
        }
#else
        // iOS/iPadOS: the file exporter presents a save sheet and copies the
        // file (`DataManagementPanel`); the notes go with the result.
        pendingExportNotes = summary.notes
        exportFileURL = tmp
#endif
    }

    /// The iOS file exporter finished with `exportFileURL`: saved where the
    /// guide chose, canceled, or failed. The temporary file goes either way.
    func fileExporterFinished(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            setLastBackupNow()
            let pending = FirstDownloadGate.isPending()
            resultSummary = BackupResultNote(
                text: Self.savedText(
                    fileName: url.lastPathComponent, notes: pendingExportNotes, firstDownloadPending: pending
                ),
                tone: pending ? .neutral : .success
            )
        case .failure(let error as CocoaError) where error.code == .userCancelled:
            resultSummary = BackupResultNote(text: "Backup canceled.", tone: .neutral)
        case .failure(let error):
            showBackupFailure(error, operation: "save the backup")
        }
        if let exportFileURL { safeRemoveItem(at: exportFileURL, context: "performExport-exporterCleanup") }
        exportFileURL = nil
        pendingExportNotes = []
    }
}
