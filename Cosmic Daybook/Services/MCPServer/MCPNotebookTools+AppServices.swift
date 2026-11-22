//
//  MCPNotebookTools+AppServices.swift
//  Cosmic Daybook
//
//  The tool that reaches past Core Data into an app-level service: writing a
//  backup archive. It finds the service through MCPAppServices, which the app
//  registers at startup; under tests the provider hands it a container built
//  on an in-memory stack. (Drafting a family's monthly report lived here too,
//  until Parent Reports was taken out on 2026-11-21.)
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Backup

    static func createBackupTool(dependencies: @escaping MCPDependenciesProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "create_backup",
            title: "Create Backup",
            description: "Write a full backup archive of the notebook now, the same file the app's "
                + "Back Up Now button writes. Call it before a bulk change (many presentations, "
                + "attendance for the class, skipping or clearing a year plan) so there is a "
                + "point to restore to. Returns the archive's path and size.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .write,
            handler: { _ in
                guard let container = dependencies() else {
                    throw MCPToolError("The app is still starting; backups are not available yet.")
                }
                let result = await container.autoBackupManager.performManualBackup(
                    viewContext: container.viewContext
                )
                return try backupReceipt(result)
            }
        )
    }

    /// A failed backup is a tool error, not a receipt that reads like success.
    /// One written while this device's first download from iCloud was under
    /// way (its name starts `Partial-`) says it may be missing some of the
    /// notebook: until 2026-11 it read like any other (bug hunt 2026-11-02 #14).
    static func backupReceipt(_ result: AutoBackupManager.BackupResult) throws -> String {
        switch result {
        case .success(let date, let url):
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
                .map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            let sizeText = size.map { " (\($0))" } ?? ""
            let receipt = "Backup written \(dayString(date)) at \(timeString(date)): "
                + "[backup path=\(url.path)]\(sizeText)"
            guard AutoBackupFolders.isPartial(url.lastPathComponent) else { return receipt }
            return receipt + "\nWarning: " + AutoBackupManager.firstDownloadWarning
        case .failure(_, let error):
            throw MCPToolError("The backup could not be written", underlying: error)
        case .skippedNoChanges:
            // Manual backups are never change-gated, so this is defensive.
            return "Nothing has changed since the last backup, so no new file was written."
        }
    }
}
