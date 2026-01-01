import Foundation
import SwiftData
import SwiftUI

/// Manages automatic backups that run when the app quits.
/// All prerequisites have been met (compression, batch processing, checksum validation).
@MainActor
class AutoBackupManager {
    @AppStorage("AutoBackup.enabled") private var isEnabled = true
    @AppStorage("AutoBackup.retentionCount") private var retentionCount = 10
    
    private let backupService = BackupService()
    
    /// Performs an automatic backup when the app quits.
    /// This runs on the main thread (acceptable since app is closing).
    func performBackupOnQuit(modelContext: ModelContext) async {
        guard isEnabled else { return }
        
        let backupDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        // Create timestamped filename (compressed backup format)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let filename = "AutoBackup-\(timestamp).\(BackupFile.fileExtension)"
        let url = backupDir.appendingPathComponent(filename)
        
        // Perform export (optimized with compression and batch processing)
        do {
            _ = try await backupService.exportBackup(modelContext: modelContext, to: url) { _, _ in
                // Silent progress - user is quitting, no UI updates needed
            }
            
            // Cleanup old backups (Retention Policy)
            cleanupOldBackups(in: backupDir, keeping: retentionCount)
        } catch {
            // Log error but don't block app quit
            #if DEBUG
            print("AutoBackupManager: Backup failed: \(error.localizedDescription)")
            #endif
        }
    }
    
    private func cleanupOldBackups(in dir: URL, keeping count: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        // Filter to auto-backup files only
        let autoBackups = files.filter { $0.lastPathComponent.hasPrefix("AutoBackup-") }
        
        // Sort by creation date (oldest first)
        let sorted = autoBackups.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
            return date1 < date2
        }
        
        // Delete oldest if we exceed retention count
        if sorted.count > count {
            let toDelete = sorted.prefix(sorted.count - count)
            for url in toDelete {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    // MARK: - Settings Access
    
    var enabled: Bool {
        get { isEnabled }
        set { isEnabled = newValue }
    }
    
    var retention: Int {
        get { retentionCount }
        set { retentionCount = max(1, min(newValue, 100)) } // Clamp between 1 and 100
    }
}

