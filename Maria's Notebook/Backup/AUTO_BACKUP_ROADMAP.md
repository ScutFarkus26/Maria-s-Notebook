# Automatic Backups - Implementation Roadmap

## ⚠️ DO NOT IMPLEMENT AUTOMATIC BACKUPS YET

Automatic backups are an **excellent idea** for protecting mission-critical teacher data (student records, lesson plans, etc.). However, **the current backup system has performance bottlenecks that would make automatic backups unsafe.**

## Why Automatic Backups Are Needed

- **Safety:** Protects against data corruption or accidental deletions
- **History:** Allows "undoing" a bad import or bulk delete operation
- **Convenience:** "Set it and forget it" - teachers often forget to back up manually until it's too late

## Why We Must Wait (Current Code Issues)

| **Problem** | **Current Status** | **Risk** |
| --- | --- | --- |
| **Memory Spike (Issue #3)** | ❌ **NOT FIXED** - All entities loaded into RAM at once | Automatic backups could crash the app during a lesson or freeze the UI |
| **No Compression (Issue #6)** | ❌ **NOT FIXED** - Backups are raw JSON files | Auto-backups will quickly fill up hard drives with large uncompressed files |
| **Main Thread Blocking** | ❌ **NOT FIXED** - `BackupService` is `@MainActor` | An auto-backup would freeze the UI, making the app unresponsive |

### Current Implementation Details

1. **Memory Issue:** `BackupService.exportBackup()` loads ALL entities into memory simultaneously (see lines 30-65 in `BackupService.swift`). With large datasets (1000+ students, 5000+ lessons), this causes significant memory spikes.

2. **Storage Issue:** Backup files are stored as uncompressed JSON. A teacher with extensive records could generate 100MB+ backup files. With automatic daily backups, this would consume GBs of storage quickly.

3. **UI Blocking:** The entire `BackupService` class is marked `@MainActor`, meaning all backup operations run on the main thread and will freeze the UI.

## Prerequisites for Safe Auto-Backups

Before implementing automatic backups, we MUST fix these three items from `BACKUP_IMPROVEMENTS.md`:

### ✅ 1. Fix Issue #3 (Memory): Batch Processing
- Implement batch processing so we don't load the whole database into RAM
- Process entities in chunks (e.g., 1000 at a time)
- Use streaming JSON encoding where possible
- Add memory pressure handling

### ✅ 2. Fix Issue #6 (Size): Add Compression
- Use LZFSE or ZIP compression via the `Compression` framework
- Compress backup files to significantly reduce storage requirements
- Update backup format to indicate compression
- Handle decompression during restore

### ⚠️ 3. Fix Issue #1 (Integrity): Checksum Validation
- **Status:** ✅ Actually FIXED (see `IMPROVEMENTS_APPLIED.md`)
- Checksum validation is now enabled for format version 5+
- However, ensure it's robust before enabling auto-backups

## Recommended Implementation Strategy: "Backup on Quit"

Once the prerequisites are met, the best strategy for a Mac app is **"Backup on Quit."** This is less intrusive than backing up while the user is working and avoids interrupting their workflow.

### Future Implementation Code

```swift
// Future Recommendation: Auto-Backup Manager
// ⚠️ DO NOT IMPLEMENT until prerequisites are met (see above)

import Foundation
import SwiftData
import Compression

@MainActor
class AutoBackupManager: ObservableObject {
    @AppStorage("AutoBackup.enabled") private var isEnabled = true
    @AppStorage("AutoBackup.retentionCount") private var retentionCount = 10
    
    private let backupService = BackupService()
    
    /// Performs an automatic backup when the app quits
    /// This should only be called after fixing Issues #3, #6, and #1
    func performBackupOnQuit(modelContext: ModelContext) async {
        guard isEnabled else { return }
        
        let backupDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto")
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        
        // 1. Create timestamped filename (compressed!)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let filename = "AutoBackup-\(formatter.string(from: Date())).json.lzfse"
        let url = backupDir.appendingPathComponent(filename)
        
        // 2. Perform export (optimized version with compression and batch processing)
        // NOTE: This assumes BackupService has been updated to:
        // - Run off the main actor (or use a background context)
        // - Support compression
        // - Use batch processing for large datasets
        try? await backupService.exportBackup(modelContext: modelContext, to: url) { _, _ in }
        
        // 3. Cleanup old backups (Retention Policy)
        cleanupOldBackups(in: backupDir, keeping: retentionCount)
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
}
```

### Integration Points

1. **App Termination:** Hook into `applicationWillTerminate` or `applicationDidFinishLaunching` to trigger backup on quit
2. **Settings UI:** Add toggle in Settings to enable/disable auto-backups
3. **Retention Settings:** Allow users to configure how many auto-backups to keep (default: 10)
4. **Background Context:** Use a background ModelContext for the backup operation to avoid blocking the main thread

## Alternative Strategies (Consider Later)

- **Scheduled Backups:** Use a background timer for daily/weekly backups (more complex, may need background execution permissions)
- **Backup Before Major Operations:** Automatically backup before bulk imports or replace-mode restores
- **Incremental Backups:** Only backup changed entities (requires Issue #8 from `BACKUP_IMPROVEMENTS.md`)

## Summary

**Current Recommendation:** Focus on fixing the high-priority items in `BACKUP_IMPROVEMENTS.md` first:

1. ✅ Issue #3: Implement batch processing (Memory optimization)
2. ✅ Issue #6: Add compression (Storage optimization)  
3. ✅ Issue #1: Verify checksum validation is robust (Already fixed, but double-check)

Once these optimizations are complete, enabling automatic backups becomes a trivial and safe addition. The backup engine will be efficient (compressed and streamed), making auto-backups non-intrusive and reliable.

## Related Documents

- `BACKUP_IMPROVEMENTS.md` - Full list of backup system improvements
- `IMPROVEMENTS_APPLIED.md` - Tracking of which improvements have been completed
- `BackupService.swift` - Current backup implementation

