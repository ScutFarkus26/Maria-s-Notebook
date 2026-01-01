# Legacy Code Analysis

This document identifies legacy code that can potentially be removed from the codebase.

## Files That Can Be Safely Deleted

### 1. `Work/WorkDetailVM.swift`
- **Status**: Completely blank file with only a comment
- **Reason**: Explicitly states "This file is intentionally left blank"
- **Action**: ✅ **Safe to delete**

### 2. `Work/WorkSplitService.swift`
- **Status**: Deprecated, marked as no-op
- **Usage**: No references found in codebase
- **Action**: ✅ **Safe to delete**

### 3. `Work/WorkLookupService.swift`
- **Status**: Deprecated, "being phased out"
- **Usage**: No references found in codebase
- **Action**: ✅ **Safe to delete**

### 4. `Backup/BackupManager.swift`
- **Status**: Marked `@available(*, unavailable)` and replaced by `BackupService`
- **Usage**: No references found (would fail to compile if referenced)
- **Action**: ✅ **Safe to delete** (compiler guard served its purpose)

## Files That Are No-Op But Still Called

### 5. `Work/WorkDataMaintenance.swift`
- **Status**: Methods exist but are intentionally disabled/no-op
- **Usage**: Still called in `Students/StudentDetailView.swift` (lines 445-446)
- **Recommendation**: Remove the calls from `StudentDetailView.swift`, then delete the file

### 6. `Work/WorkMigrationService.swift`
- **Status**: Intentionally disabled, performs no work
- **Usage**: No calls found (was likely removed already)
- **Action**: ✅ **Safe to delete** (no call sites found)

### 7. `Work/WorkCheckInDefaults.swift`
- **Status**: Deprecated, returns hardcoded values
- **Usage**: Only referenced in a comment in `Work/WorkRepository.swift` (line 32), not actually called
- **Action**: ✅ **Safe to delete** (remove comment reference first)

## Compatibility Shims (Deprecated But May Have Type References)

### 8. `Work/WorkDetailViewModel.swift`
- **Status**: Deprecated compatibility shim
- **Usage**: No instantiations found, but may be referenced as a type
- **Recommendation**: Search for any type references before removing

## Migration Code (One-Time Runs)

### 9. `Services/LegacyNotesMigration.swift`
- **Status**: Migration code that runs once (uses UserDefaults flag)
- **Usage**: Called in `AppBootstrapper.swift`
- **Recommendation**: 
  - If migration flag `DidMigrateLegacyScopedNotes_v1` is already set for all users, can be removed
  - Otherwise, keep for backward compatibility with users who haven't run the migration yet
  - Consider removing in a future release after sufficient time has passed

## Notes on WorkModel

The `WorkModel` class still exists in the codebase and is referenced in:
- `Work/WorkDetailWindowContainer.swift` (to show error message for legacy work)
- Various migration/maintenance files

WorkModel appears to be deprecated in favor of `WorkContract`, but the model itself hasn't been removed yet (likely for data compatibility). The maintenance/migration services related to it can be cleaned up.

