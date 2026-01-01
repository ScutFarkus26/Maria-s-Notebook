# Backup System Improvements - Applied

This document summarizes the improvements that have been applied to the backup and restore system.

## ✅ Completed Improvements

### 1. Re-enabled Checksum Validation (Critical)
- **Status**: ✅ Complete
- **Changes**: 
  - Checksum validation is now enforced for format version 5+
  - Older format versions can bypass checksum validation using the existing UI setting
  - Improved error messages show expected vs actual checksum values
- **Files Modified**: `BackupService.swift` (both `previewImport` and `importBackup` methods)

### 2. Backup Verification After Creation
- **Status**: ✅ Complete
- **Changes**: 
  - Backup files are now verified after creation by reading them back and decoding the envelope
  - This ensures the backup file was written correctly and is readable
- **Files Modified**: `BackupService.swift` (export method)

### 3. Centralized Entity Registry
- **Status**: ✅ Complete
- **Changes**: 
  - Created `BackupEntityRegistry.swift` with a single source of truth for all entity types
  - Includes `BackupProgress` helper for structured progress tracking
  - Eliminates hardcoded entity lists scattered throughout the codebase
- **Files Created**: `BackupEntityRegistry.swift`

### 4. Improved Progress Reporting
- **Status**: ✅ Complete
- **Changes**: 
  - Progress updates now show which entity type is being processed (e.g., "Collecting students…", "Collecting lessons…")
  - Uses structured `BackupProgress` helper for consistent progress calculation
  - More granular progress updates during data collection phase
- **Files Modified**: `BackupService.swift` (export method)

### 5. Comprehensive Duplicate ID Validation
- **Status**: ✅ Complete
- **Changes**: 
  - Now validates duplicate IDs for ALL entity types, not just Students
  - Provides detailed error messages listing all entity types with duplicates
  - Shows first 5 duplicate IDs for each entity type
- **Files Modified**: `BackupService.swift` (import method)

### 6. File Permissions
- **Status**: ✅ Complete
- **Changes**: 
  - Encrypted backup files now have restricted permissions (600: rw-------)
  - Ensures encrypted backups are only readable by the file owner
- **Files Modified**: `BackupService.swift` (export method)

### 7. Updated Format Version
- **Status**: ✅ Complete
- **Changes**: 
  - Format version increased to 5
  - Documents that version 5+ enforces checksum validation with deterministic JSON encoding
  - Maintains backward compatibility with older format versions
- **Files Modified**: `BackupTypes.swift`

### 8. Improved Error Messages
- **Status**: ✅ Complete
- **Changes**: 
  - Checksum errors now show expected vs actual checksum values (first 16 chars)
  - Duplicate ID errors list all affected entity types
  - StudentLesson import errors show truncated UUIDs for readability
- **Files Modified**: `BackupService.swift`

### 9. Use Entity Registry for deleteAll
- **Status**: ✅ Complete
- **Changes**: 
  - `deleteAll` method now uses `BackupEntityRegistry.allTypes` instead of hardcoded list
  - Ensures consistency and makes it easier to add new entity types in the future
- **Files Modified**: `BackupService.swift`

### 10. Compression Support (Issue #6)
- **Status**: ✅ Complete
- **Changes**: 
  - Added LZFSE compression support using the Compression framework
  - Format version increased to 6
  - New `compressedPayload` field in `BackupEnvelope` for compressed but unencrypted backups
  - Compression metadata stored in `BackupManifest.compression`
  - Compression applied before encryption (compressed data is then encrypted if password is provided)
  - Checksum is calculated on uncompressed data for integrity verification
  - Full backward compatibility: old backups (format version < 6) continue to work without compression
  - Automatic decompression during import and preview
- **Files Modified**: 
  - `BackupTypes.swift` (added compression field to manifest, new compressedPayload field, format version 6)
  - `BackupService.swift` (compression/decompression helpers, updated export/import logic)
- **Benefits**: Significantly reduces backup file sizes (typically 2-4x compression for JSON), enabling automatic backups without storage bloat

### 11. Batch Processing for Large Datasets (Issue #3)
- **Status**: ✅ Complete
- **Changes**: 
  - Implemented batch fetching for all entity types using `fetchOffset` and `fetchLimit`
  - Added `safeFetchInBatches()` helper method that processes entities in chunks of 1000
  - Added `safeFetchInBatchesWithErrorHandling()` for entity types that may have corrupted data
  - All entity fetching now uses batch processing to reduce memory spikes during backup operations
  - Entities are fetched in batches rather than loading all at once into memory
- **Files Modified**: 
  - `BackupService.swift` (batch fetching helpers, updated all fetch calls to use batch processing)
- **Benefits**: 
  - Reduces peak memory usage during backup by processing entities in manageable chunks
  - Prevents memory spikes that could crash the app with large datasets (1000+ students, 5000+ lessons)
  - Critical prerequisite for enabling automatic backups (now implemented)
- **Technical Details**: 
  - Batch size of 1000 provides good balance between memory efficiency and performance
  - Still accumulates all entities before conversion to DTOs (required for BackupPayload structure)
  - Reduces memory pressure by avoiding holding all SwiftData entities in memory simultaneously

### 12. Automatic Backups Implementation
- **Status**: ✅ Complete
- **Changes**: 
  - Created `AutoBackupManager` class to manage automatic backups on app quit
  - Created `AutoBackupAppDelegate` to integrate with macOS app lifecycle
  - Added Settings UI for configuring auto-backup preferences (enable/disable, retention count)
  - Automatic backups run when the app quits (non-intrusive)
  - Backups stored in `~/Documents/Backups/Auto/` with timestamped filenames
  - Automatic cleanup of old backups based on retention policy (default: 10 backups)
- **Files Created**: 
  - `Backup/AutoBackupManager.swift` - Manages automatic backup operations
  - `AppCore/AutoBackupAppDelegate.swift` - App lifecycle integration
- **Files Modified**: 
  - `AppCore/MariasToolboxApp.swift` - Added AppDelegate adapter
  - `Backup/BackupRestoreSettingsView.swift` - Added automatic backup configuration UI
- **Benefits**: 
  - Protects user data automatically without manual intervention
  - Non-intrusive (runs on app quit, doesn't interrupt workflow)
  - Configurable retention policy prevents storage bloat
  - Uses optimized backup format (compressed, batch-processed, checksum-validated)

## 📝 Implementation Notes

### Checksum Validation Logic
The checksum validation uses the following logic:
- Format version >= 5: Always validates (new format with reliable checksums)
- Format version < 5: Validates unless "Allow checksum bypass" setting is enabled

This provides security for new backups while maintaining compatibility with older backups that may have been created before deterministic JSON encoding was guaranteed.

### Format Version Compatibility
- New backups are created with format version 5
- Old backups (version 4 and earlier) can still be restored
- Checksum validation respects the bypass setting for old format versions

### Entity Registry
The `BackupEntityRegistry` serves as the single source of truth for:
- Which entity types should be backed up
- Which entity types should be deleted during replace-mode restore
- Entity type names for progress reporting

When adding new entity types to the app, update `BackupEntityRegistry.allTypes` and the corresponding DTO mapping code in `BackupService`.

## 🔄 Not Implemented (Out of Scope)

The following improvements were considered but not implemented as they require significant architectural changes:

1. **Generic fetchOne Method**: SwiftData's `#Predicate` macro requires compile-time type information, making a truly generic implementation infeasible without code generation or macros.

4. **Incremental Backups**: Would require tracking modification timestamps and significant architectural changes.

## 🧪 Testing Recommendations

1. Test backup/restore with format version 4 backups (backward compatibility)
2. Test backup/restore with format version 5 backups (new format)
3. Test backup/restore with format version 6 backups (compressed format)
4. Test compression/decompression with various data sizes
5. Test encrypted + compressed backups
6. Test unencrypted + compressed backups
7. Test checksum validation with corrupted backup files
8. Test duplicate ID detection with malformed backup files
9. Test file permissions on encrypted backups
10. Test backup verification with write failures (disk full, etc.)

## 📊 Impact

These improvements significantly enhance:
- **Data Integrity**: Checksum validation prevents silent data corruption
- **Reliability**: Backup verification ensures backups are readable
- **Maintainability**: Centralized entity registry reduces duplication
- **User Experience**: Better progress reporting and error messages
- **Security**: Proper file permissions on encrypted backups

