# Backup and Restore System - Improvement Recommendations

This document outlines specific, actionable improvements for the backup and restore system.

## 🔴 Critical Issues (Security & Data Integrity)

### 1. Checksum Validation Disabled
**Location:** `BackupService.swift` lines 514-519, 668-673

**Problem:** Checksum validation is completely disabled with a comment about "non-deterministic key order". This is a serious data integrity risk.

**Solution:** 
- Re-enable checksum validation with deterministic JSON encoding
- Use `.sortedKeys` on encoder (already present) but ensure consistent encoding
- Add option to verify backup after creation
- If format version < 5, allow bypass only for old backups

**Code Changes:**
```swift
// Replace disabled checksum validation with proper implementation
progress(0.20, "Validating…")
if envelope.formatVersion >= 5 || !UserDefaults.standard.bool(forKey: "Backup.allowChecksumBypass") {
    let sha = sha256Hex(payloadBytes)
    guard sha == envelope.manifest.sha256 else {
        throw NSError(domain: "BackupService", code: 1102, userInfo: [NSLocalizedDescriptionKey: "Checksum mismatch. File may be corrupted."])
    }
}
```

### 2. No Backup Verification After Creation
**Problem:** Backups are written but never verified by reading them back.

**Solution:** Add optional verification step after export:
```swift
// After writing backup file
progress(0.95, "Verifying backup…")
let verificationData = try Data(contentsOf: url)
let verificationEnvelope = try decoder.decode(BackupEnvelope.self, from: verificationData)
// Quick sanity check: verify structure can be decoded
```

## ⚡ Performance Issues

### 3. All Entities Loaded Into Memory
**Location:** `BackupService.swift` lines 30-54

**Problem:** All entities are fetched synchronously into memory at once, causing memory spikes with large datasets.

**Solution:** 
- Process entities in batches (e.g., 1000 at a time)
- Use streaming JSON encoding where possible
- Add memory pressure handling

**Example:**
```swift
private func fetchInBatches<T: PersistentModel>(
    _ type: T.Type,
    using context: ModelContext,
    batchSize: Int = 1000
) -> AsyncStream<[T]> {
    AsyncStream { continuation in
        Task {
            var offset = 0
            while true {
                var descriptor = FetchDescriptor<T>()
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = batchSize
                let batch = (try? context.fetch(descriptor)) ?? []
                if batch.isEmpty { break }
                continuation.yield(batch)
                offset += batchSize
            }
            continuation.finish()
        }
    }
}
```

### 4. Inefficient Replace Mode Delete-All
**Location:** `BackupService.swift` lines 1180-1210

**Problem:** `deleteAll` iterates through all types and calls `delete(model:)` which may be slow for large datasets.

**Solution:**
- Use batch deletion with predicates
- Consider using raw SQL/delete requests if available
- Progress reporting during deletion
- Alternative: use transaction rollback approach for safer atomic operations

### 5. Repetitive `fetchOne` Method
**Location:** `BackupService.swift` lines 1017-1113

**Problem:** ~100 lines of repetitive type-specific fetch code that's hard to maintain.

**Solution:** Use a generic approach with type erasure:
```swift
private func fetchOne<T: PersistentModel>(_ type: T.Type, id: UUID, using context: ModelContext) throws -> T? {
    // Create predicate using keyPath if available, or use reflection fallback
    let descriptor = FetchDescriptor<T>()
    // Use Codable UUID comparison or generic predicate
    let results = try context.fetch(descriptor)
    return results.first { ($0 as? (any Identifiable))?.id == id } as? T
}
```

Or better, maintain a registry of entity types with their ID keyPaths.

### 6. No Compression
**Problem:** Backup files can be very large (JSON is verbose), especially with many records.

**Solution:** Add optional compression using `Compression` framework:
```swift
import Compression

// After encoding payload
let compressed = try (payloadBytes as NSData).compressed(using: .lzfse)
// Store compression flag in envelope
// Decompress on import
```

## 🛡️ Reliability & Error Handling

### 7. Limited Error Recovery
**Problem:** If import fails partway through, data may be in inconsistent state (especially in replace mode).

**Solution:**
- Implement transactional import with rollback capability
- Create backup before replace-mode import
- Add "dry run" mode that validates without importing
- Better error messages with specific entity type/ID that failed

### 8. No Incremental Backup Support
**Problem:** Every backup is a full backup, even if only small changes occurred.

**Solution:** (Future enhancement)
- Track last backup timestamp
- Store entity modification timestamps
- Export only changed entities since last backup
- Merge with previous backups on restore

### 9. Duplicate ID Validation Limited
**Location:** `BackupService.swift` line 679

**Problem:** Only validates duplicate Student IDs, not other entity types.

**Solution:** Validate duplicates for all entity types:
```swift
func validateNoDuplicates<T: Identifiable>(_ items: [T], entityName: String) throws {
    let ids = items.map { $0.id }
    let uniqueIds = Set(ids)
    if ids.count != uniqueIds.count {
        let duplicates = ids.filter { id in ids.filter { $0 == id }.count > 1 }
        throw NSError(domain: "BackupService", code: 1004, userInfo: [
            NSLocalizedDescriptionKey: "Duplicate \(entityName) IDs found: \(Set(duplicates).prefix(5))"
        ])
    }
}
```

## 📊 User Experience

### 10. No Backup Metadata Browsing
**Problem:** Users can't view backup contents without importing.

**Solution:** 
- Create lightweight backup inspector view
- Show backup metadata (date, size, entity counts) in file browser
- Quick preview of what would be restored

### 11. Limited Progress Feedback
**Problem:** Progress updates are generic ("Collecting data…") and don't show which entity type is being processed.

**Solution:** More granular progress reporting:
```swift
progress(0.05, "Collecting students…")
let students = safeFetch(Student.self, using: modelContext)
progress(0.10, "Collecting lessons…")
let lessons = safeFetch(Lesson.self, using: modelContext)
// etc.
```

### 12. No Backup Size Estimation
**Problem:** Users don't know backup size before starting export.

**Solution:** Quick pre-export estimate based on entity counts:
```swift
func estimateBackupSize(entityCounts: [String: Int]) -> Int64 {
    // Rough estimate: average bytes per entity type
    let estimates: [String: Int] = [
        "Student": 500,
        "Lesson": 2000,
        // etc.
    ]
    return entityCounts.reduce(0) { $0 + (estimates[$1.key] ?? 1000) * $1.value }
}
```

## 🔧 Code Quality

### 13. Hardcoded Entity Type Lists
**Location:** Multiple locations

**Problem:** Entity types are listed in multiple places (deleteAll, fetchOne, export, import), making it easy to miss a type when adding new entities.

**Solution:** Create a centralized entity registry:
```swift
struct BackupEntityRegistry {
    static let allTypes: [any PersistentModel.Type] = [
        Student.self,
        Lesson.self,
        // etc.
    ]
    
    static func fetchAll(using context: ModelContext) -> [String: [any PersistentModel]] {
        // Generic fetching logic
    }
}
```

### 14. Magic Numbers in Progress Reporting
**Location:** Various progress calls

**Problem:** Progress percentages (0.05, 0.35, etc.) are magic numbers scattered throughout.

**Solution:** Use a structured progress tracker:
```swift
struct BackupProgress {
    enum Phase: Double {
        case collecting = 0.0
        case encoding = 0.3
        case encrypting = 0.5
        case writing = 0.7
        case verifying = 0.9
        case complete = 1.0
    }
    
    static func progress(for phase: Phase, subProgress: Double = 0) -> Double {
        // Calculate based on phase
    }
}
```

## 🔐 Security Enhancements

### 15. Password Handling
**Problem:** Passwords passed as `String` which may linger in memory.

**Solution:** (If available on platform)
- Use SecureString or similar for password input
- Clear password from memory after use
- Add password strength indicator
- Option to save password in keychain (with warning)

### 16. Backup File Permissions
**Problem:** No explicit file permissions set on backup files.

**Solution:** Set appropriate permissions:
```swift
try envBytes.write(to: url, options: .atomic)
try FileManager.default.setAttributes([
    .posixPermissions: NSNumber(value: 0o600) // rw------- for encrypted backups
], ofItemAtPath: url.path)
```

## 📈 Future Enhancements

### 17. Automatic Backups
- **Status**: ✅ IMPLEMENTED (see `IMPROVEMENTS_APPLIED.md` #12)
- Automatic backup on app quit (implemented)
- Retention policy (implemented)
- Settings UI for configuration (implemented)
- **Future enhancements still possible:**
  - Scheduled backups (daily, weekly)
  - Automatic backup before major operations

### 18. Cloud Backup Integration
- iCloud Drive integration
- Dropbox/OneDrive support
- End-to-end encrypted cloud backups

### 19. Partial Restore
- Restore only specific entity types
- Restore by date range
- Selective merge (choose which entities to merge)

### 20. Backup Comparison
- Compare two backups
- Show differences between backups
- Visual diff of changes

### 21. Backup Health Checks
- Periodic verification of backup files
- Alert on corrupted backups
- Backup age warnings

## Priority Recommendations

**High Priority (Do First):**
1. Re-enable checksum validation (#1) - ✅ COMPLETE
2. Add backup verification after creation (#2) - ✅ COMPLETE
3. Improve error messages with entity details (#7) - ✅ COMPLETE
4. Fix repetitive fetchOne code (#5) - ⚠️ Out of scope (SwiftData limitations)

**Medium Priority:**
5. Add compression (#6) - ✅ COMPLETE
6. Batch processing for large datasets (#3) - ✅ COMPLETE
7. Better progress reporting (#11) - ✅ COMPLETE
8. Centralized entity registry (#13) - ✅ COMPLETE

**Low Priority (Nice to Have):**
9. Incremental backups (#8)
10. Backup metadata browsing (#10)
11. Automatic backups (#17) - ✅ IMPLEMENTED (backup on quit, retention policy)

## Implementation Notes

- Most improvements are backward compatible
- Test thoroughly with large datasets (1000+ students, 5000+ lessons)
- Consider performance impact of additional validation
- Maintain format version compatibility
- Update tests for any changes

