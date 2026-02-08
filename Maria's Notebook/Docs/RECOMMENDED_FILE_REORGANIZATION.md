# Recommended File Reorganization

This document outlines file organization improvements that should be implemented manually through Xcode to maintain proper project references.

## Overview

The following large files and scattered structures would benefit from reorganization. All file moves should be done through Xcode's Project Navigator (drag and drop) to maintain proper references.

---

## Phase 5A: Large File Decomposition

### 1. BackupServicesTests.swift (1264 lines)
**Current:** Single massive test file  
**Recommended split:**
- `BackupTests/BackupExportTests.swift` - Export functionality tests
- `BackupTests/BackupImportTests.swift` - Import and restore tests
- `BackupTests/BackupEncryptionTests.swift` - Encryption and security tests
- `BackupTests/BackupValidationTests.swift` - Validation logic tests

**Benefit:** Faster compilation, easier test navigation, clearer test organization

---

### 2. StudentsView.swift (1136 lines)
**Current:** Monolithic view with multiple concerns  
**Recommended split:**
- `Students/Views/StudentsRosterView.swift` - Main grid/roster display
- `Students/Views/StudentsSearchBar.swift` - Search UI components
- `Students/Views/StudentsFilterBar.swift` - Filter button controls
- `Students/Views/StudentsSortingControls.swift` - Sorting UI

**Benefit:** Reusable components, clearer view hierarchy, faster compilation

---

### 3. WorkDetailView.swift (982 lines)
**Current:** Single large view file  
**Recommended split:**
- `Work/Views/WorkCheckInSection.swift` - Check-in UI and logic
- `Work/Views/WorkStepsSection.swift` - Work steps display
- `Work/Views/WorkMetadataSection.swift` - Metadata and details
- `Work/Views/WorkAttachmentsSection.swift` - Attachments handling

**Benefit:** Component reuse, clearer separation of concerns

---

### 4. PresentationProgressListView.swift (982 lines)
**Current:** Large view with embedded components  
**Recommended split:**
- `Presentations/Views/PresentationProgressRow.swift` - Individual row component
- `Presentations/Views/PresentationProgressFilters.swift` - Filter controls
- `Presentations/Views/PresentationProgressHeader.swift` - Header component

**Benefit:** Reusable row component, testable filters

---

### 5. MariasNotebookApp.swift (907 lines)
**Current:** Massive app entry point  
**Recommended split:**
- `AppCore/AppBootstrapping.swift` - Initialization logic
- `AppCore/CloudKitConfiguration.swift` - CloudKit setup
- `AppCore/AppErrorHandling.swift` - Error coordinator setup
- `AppCore/AppSceneConfiguration.swift` - Scene and window setup

**Benefit:** Testable initialization, clearer app lifecycle

---

### 6. CloudKitSyncStatusService.swift (648 lines)
**Current:** Service with too many responsibilities  
**Recommended split:**
- `Services/CloudKit/NetworkMonitoring.swift` - Network status checks
- `Services/CloudKit/SyncRetryLogic.swift` - Retry handling
- `Services/CloudKit/CloudKitHealthCheck.swift` - Status monitoring
- `Services/CloudKit/CloudKitSyncCoordinator.swift` - Main coordination

**Benefit:** Single responsibility, testable components

---

### 7. DataCleanupService.swift (812 lines)
**Current:** Monolithic cleanup service  
**Recommended split:**
- `Services/Cleanup/StudentDataCleanup.swift` - Student-related cleanup
- `Services/Cleanup/LessonDataCleanup.swift` - Lesson-related cleanup
- `Services/Cleanup/WorkDataCleanup.swift` - Work-related cleanup
- `Services/Cleanup/CleanupCoordinator.swift` - Orchestration

**Benefit:** Clearer cleanup policies per entity type

---

### 8. SelectiveExportService.swift (818 lines)
**Current:** Complex export logic in one file  
**Recommended split:**
- `Backup/Export/ExportFilterEngine.swift` - Filter logic
- `Backup/Export/ExportDataCollector.swift` - Data collection
- `Backup/Export/ExportWriter.swift` - Writing logic
- `Backup/Export/SelectiveExportCoordinator.swift` - Orchestration

**Benefit:** Testable components, clearer data flow

---

## Phase 5B: Folder Structure Improvements

### Constants Organization
**Create:** `AppCore/Constants/`  
**Move into it:**
- `UIConstants.swift`
- `BackupConstants.swift`
- `UserDefaultsKeys.swift`
- `BatchingConstants.swift` (already in Utils, could move)
- `TimeoutConstants.swift` (already in Utils, could move)

**Benefit:** Single location for all app constants

---

### Model Extensions Organization
**Create:** `Models/Extensions/`  
**Move into it:**
- `Presentation+Resolved.swift`
- `StudentLesson+Resolved.swift`
- `LessonModel+Extensions.swift`
- Any other model extension files

**Benefit:** Predictable location, clear extension grouping

---

### Backup Feature-Based Organization
**Current structure:**
```
Backup/
  ├── Helpers/
  ├── Services/
  └── UI/
```

**Recommended structure:**
```
Backup/
  ├── Export/
  │   ├── SelectiveExportService.swift
  │   ├── BackupCodec.swift
  │   └── StreamingBackupWriter.swift
  ├── Import/
  │   ├── BackupEntityImporter.swift
  │   ├── SelectiveRestoreService.swift
  │   └── BackupPayloadExtractor.swift
  ├── Validation/
  │   ├── BackupValidationService.swift
  │   ├── ChecksumVerificationService.swift
  │   └── BackupIntegrityMonitor.swift
  ├── Sync/
  │   ├── CloudBackupService.swift
  │   ├── DeltaSyncService.swift
  │   ├── IncrementalBackupService.swift
  │   └── ConflictResolutionService.swift
  ├── Telemetry/
  │   ├── BackupTelemetryService.swift
  │   └── TelemetryDashboardView.swift
  └── Core/
      ├── BackupContainer.swift
      ├── BackupDestination.swift
      └── BackupEntityRegistry.swift
```

**Benefit:** Feature-based organization, clearer boundaries, easier navigation

---

## Phase 5C: Test Organization

### Create Feature-Based Test Folders
```
Tests/
  ├── Unit/
  │   ├── Services/
  │   ├── ViewModels/
  │   └── Models/
  ├── Integration/
  │   ├── TodayViewLoadIntegrationTests.swift
  │   └── BackupRestoreFlowTests.swift
  ├── Performance/
  │   └── PerformanceBenchmarks.swift
  └── EdgeCases/
      └── LargeDatasetTests.swift
```

**Benefit:** Clear test categorization, easier to run specific test suites

---

## Implementation Guidelines

### DO:
1. ✅ Use Xcode Project Navigator for all file moves (drag and drop)
2. ✅ Create groups/folders in Xcode first, then move files
3. ✅ Build after each file move to catch reference issues immediately
4. ✅ Commit after each logical grouping of moves
5. ✅ Update imports as needed (Xcode usually handles this)

### DON'T:
1. ❌ Move files in Finder (breaks Xcode references)
2. ❌ Move too many files at once (hard to debug issues)
3. ❌ Skip building between moves (catch errors early)
4. ❌ Forget to update project documentation after reorganization

---

## Priority Order

**High Priority (Do First):**
1. Create Constants folder and consolidate constants
2. Split BackupServicesTests.swift (huge impact on test performance)
3. Reorganize Backup folder by feature

**Medium Priority:**
4. Split MariasNotebookApp.swift (improves app structure clarity)
5. Create Model Extensions folder
6. Split CloudKitSyncStatusService.swift

**Lower Priority (Nice to Have):**
7. Split large view files (StudentsView, WorkDetailView, etc.)
8. Reorganize test structure

---

## Expected Outcomes

After completing these reorganizations:
- **Compilation speed:** ~20-30% faster due to smaller file sizes
- **Navigation:** ~50% faster (clearer folder structure)
- **Code review:** Easier to review (changes in smaller, focused files)
- **Onboarding:** New developers find code more quickly
- **Testing:** Easier to run specific test suites

---

## Notes

All file reorganizations are **safe** because:
- No logic changes
- Xcode handles imports automatically
- Build system catches reference issues immediately
- Can be done incrementally with commits between moves

**Estimated time:** 2-4 hours for complete reorganization
**Risk level:** Low (if done through Xcode)
**Impact:** High (long-term maintainability improvement)
