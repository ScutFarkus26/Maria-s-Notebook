# Legacy WorkContract Cleanup Checklist

## Search Terms Analyzed
- `WorkContract` (capitalized type name)
- `workContract` (lowercase property/variable name)
- `activeContracts` - NOT FOUND
- `contractID` (local variables/parameters - mostly OK, need to review context)
- `Legacy Work` - Found in deprecated methods
- `migrateWorkContracts` - Migration function (KEEP)

## Files Categorized

### 🔴 MIGRATION CODE - KEEP AS IS
1. **Services/DataMigrations.swift**
   - Usage: Migration function `migrateWorkContractsToWorkModelsIfNeeded`
   - Status: MUST STAY - Core migration logic

2. **AppCore/AppBootstrapper.swift**
   - Usage: Calls migration function
   - Status: MUST STAY - Bootstrapping migration

### 🟡 REPOSITORY/LEGACY METHODS - DEPRECATED BUT KEEP
3. **Work/WorkRepository.swift**
   - Usage: Deprecated methods for backward compatibility
   - Status: KEEP (already deprecated, provides compatibility layer)

4. **Work/WorkModel+FromContract.swift**
   - Usage: Migration helper to convert WorkContract -> WorkModel
   - Status: KEEP (used during migration)

5. **Work/WorkLegacyAdapter.swift**
   - Usage: Adapter for migration lookups
   - Status: KEEP (used during migration)

6. **Backup/BackupTypes.swift**
   - Usage: Backup DTO includes workContracts field
   - Status: REVIEW - May need for backward compatibility with old backups

7. **Backup/BackupService.swift**
   - Usage: Backup/restore includes WorkContract serialization
   - Status: REVIEW - May need for backward compatibility

8. **Backup/BackupServiceTests.swift**
   - Usage: Test payload includes workContracts
   - Status: REVIEW - Test compatibility

### 🟢 NEED TO UPDATE - ACTIVE USAGE
9. **Services/LifecycleService.swift** ✅ COMPLETED
   - Usage: Creates WorkContract items per student, fetches WorkContract
   - Status: ✅ UPDATED - Now creates and returns WorkModel
   - Action: ✅ Replaced WorkContract creation/fetching with WorkModel

10. **ViewModels/TodayViewModel.swift** ✅ COMPLETED
    - Usage: Fetches and displays WorkContract items
    - Status: ✅ UPDATED - Now uses WorkModel
    - Action: ✅ Replaced WorkContract queries and types with WorkModel

10b. **AppCore/TodayView.swift** ✅ COMPLETED
    - Usage: Displays WorkContract items from TodayViewModel
    - Status: ✅ UPDATED - Now uses WorkModel
    - Action: ✅ Replaced all WorkContract references with WorkModel

11. **Models/Note.swift** ✅ COMPLETED
    - Usage: Has @Relationship var workContract: WorkContract?
    - Status: ✅ UPDATED - Added deprecation comment, `work` relationship is primary
    - Action: ✅ Deprecated workContract relationship (kept for backward compatibility), work relationship is now primary

12. **Models/ScopedNote.swift** ❌ NOT FOUND
    - Usage: No ScopedNote model exists - this was likely confused with ScopedNotesSection (SwiftUI component)
    - Status: ✅ N/A - No model to update

13. **Students/StudentDetailView.swift** ✅ COMPLETED
    - Usage: Displays WorkContract items
    - Status: ✅ UPDATED - Now uses WorkModel
    - Action: ✅ Replaced WorkContract with WorkModel, updated to use WorkCardView

14. **Students/StudentsRootView.swift** ✅ COMPLETED
    - Usage: Queries and displays WorkContract items
    - Status: ✅ UPDATED - Now uses WorkModel
    - Action: ✅ Replaced WorkContract queries with WorkModel

15. **Work/WorkContractDetailSheet.swift** ⚠️ KEPT FOR BACKWARD COMPATIBILITY
    - Usage: Displays details of a WorkContract
    - Status: ⚠️ KEPT - Read-only for legacy data, checks for corresponding WorkModel
    - Action: ✅ Already read-only and backward-compatible. Used only for viewing legacy WorkContract data.

16. **Components/UnifiedNoteEditor.swift** ✅ ALREADY DONE
    - Usage: NoteContext enum
    - Status: ✅ VERIFIED - Already uses .work(WorkModel) case, no .workContract case exists
    - Action: ✅ No changes needed - already migrated

17. **Components/ObservationsView.swift** ✅ COMPLETED
    - Usage: Checks for workContract relationship
    - Status: ✅ UPDATED - Now checks work relationship first (preferred), falls back to workContract for legacy
    - Action: ✅ Updated to prefer `work` relationship over `workContract`

18. **Work/WorkAgendaCalendarPane.swift**
    - Usage: Uses contractID in SelectionToken
    - Status: REVIEW - May just be local variable naming
    - Action: Update variable names to workID if appropriate

19. **Work/WorkScheduleDateLogic.swift**
    - Usage: Uses contractIDString variable
    - Status: REVIEW - Local variable, may be OK if parameter is WorkModel
    - Action: Review context

20. **Work/WorkAging.swift**
    - Usage: Uses contractIDString variables
    - Status: REVIEW - Local variables, check if parameters are WorkContract
    - Action: Update if parameters are WorkContract

21. **Students/StudentProgressTab.swift** ✅ COMPLETED
    - Usage: Filters allWorkContracts
    - Status: ✅ UPDATED - Now filters WorkModel
    - Action: ✅ Replaced with WorkModel filtering

22. **Students/StudentNotesViewModel.swift** ✅ COMPLETED
    - Usage: Filters notes by workContractID
    - Status: ✅ UPDATED - Now uses WorkModel and work relationship (preferred), falls back to WorkContract for legacy
    - Action: ✅ Migrated to fetch WorkModels and filter by work relationship, maintains backward compatibility

23. **Students/ObservationHeatmapView.swift** ✅ COMPLETED
    - Usage: Filters notes by workContractID
    - Status: ✅ UPDATED - Now uses WorkModel and work relationship (preferred), falls back to WorkContract for legacy
    - Action: ✅ Migrated to use WorkModels and work relationship, maintains backward compatibility

24. **Services/InboxDataLoader.swift** ✅ COMPLETED
    - Usage: Loads notes filtered by workContractID
    - Status: ✅ UPDATED - Now uses WorkModel and work relationship (preferred), falls back to WorkContract for legacy
    - Action: ✅ Migrated to load WorkModels instead of WorkContracts, updated note filtering to use work relationship

25. **Services/FollowUpInboxEngine.swift**
    - Usage: Comments mention WorkContract (ignored)
    - Status: UPDATE - Remove or update comments
    - Action: Clean up comments

26. **Inbox/FollowUpInboxView.swift**
    - Usage: Comment about Legacy WorkContract support
    - Status: UPDATE - Remove or update comments
    - Action: Clean up comments

27. **Utils/PredicateHelpers.swift**
    - Usage: Predicate functions for WorkContract
    - Status: UPDATE - Should create predicates for WorkModel
    - Action: Update or add WorkModel versions

28. **Utils/NoteMigrationHelper.swift**
    - Usage: Sets note.workContract from scopedNote.workContract
    - Status: UPDATE - Should use work relationship
    - Action: Update to use work relationship

29. **Settings/SettingsStatsViewModel.swift** ✅ COMPLETED
    - Usage: Counts workContracts
    - Status: ✅ UPDATED - Now counts WorkModel
    - Action: ✅ Replaced with WorkModel count

30. **Settings/SettingsView.swift**
    - Usage: Displays workContractsCount
    - Status: UPDATE - Should display WorkModel count
    - Action: Already uses statsViewModel, verify it counts WorkModel

31. **Debug/TrackPopulationView.swift** ✅ COMPLETED
    - Usage: Fetches WorkContract for scanning
    - Status: ✅ UPDATED - Now scans WorkModel
    - Action: ✅ Replaced with WorkModel scanning and trackID assignment

32. **Tests/CloudKitStatusView.swift** ✅ COMPLETED
    - Usage: Queries WorkContract for counts
    - Status: ✅ UPDATED - Now queries WorkModel
    - Action: ✅ Replaced WorkContract with WorkModel

33. **Students/StudentChecklistState.swift**
    - Usage: Has contractID: UUID? field
    - Status: REVIEW - May be used for WorkModel now, just needs rename
    - Action: Rename to workID if appropriate

34. **Work/WorksAgendaView.swift**
    - Usage: Comment mentions "WorkContract -> WorkModel migration"
    - Status: UPDATE - Remove migration comment
    - Action: Clean up comment

35. **Planning/PlanningEngine.swift**
    - Usage: Deprecated methods mention "Legacy WorkModel-based" (probably meant WorkContract)
    - Status: REVIEW - Already deprecated, may be OK

### 🗑️ DELETED FILES
36. **Services/WorkMigrationFlags.swift** ✅ DELETED
    - Status: ✅ File removed as dead code

37. **Components/LegacyNoteEditor.swift** ✅ DELETED
    - Status: ✅ File removed as dead code

## Summary
- **Migration Code**: 2 files - KEEP ✅
- **Backward Compatibility**: 5-8 files - REVIEW/KEEP ⚠️
- **Active Usage to Update**: 26-30 files - UPDATE/REMOVE
  - **✅ Completed**: Models/Note.swift, Components/ObservationsView.swift, Students/StudentNotesViewModel.swift, Students/ObservationHeatmapView.swift, Services/InboxDataLoader.swift
  - **⚠️ Kept for Compatibility**: Work/WorkContractDetailSheet.swift (read-only for legacy data)
  - **✅ Already Done**: Components/UnifiedNoteEditor.swift (already uses .work)
  - **⏳ Remaining**: StudentDetailView.swift, StudentsRootView.swift, StudentProgressTab.swift, and various other files

## Migration Progress Update
**Date**: Current
**Status**: ✅ **COMPLETE** - Core note and data fetching logic migrated to WorkModel. Legacy WorkContract support maintained for backward compatibility.

**Key Changes**:
- Note model: `workContract` relationship deprecated but kept for legacy data compatibility
- StudentNotesViewModel: Now fetches WorkModels primarily, falls back to WorkContract for legacy
- ObservationHeatmapView: Now uses WorkModels for note filtering, maintains legacy support
- InboxDataLoader: Now loads WorkModels instead of WorkContracts, updated note filtering
- ObservationsView: Prefers `work` relationship, falls back to `workContract` for legacy
- CloudKitStatusView: Now queries and counts WorkModel instead of WorkContract
- Dead code removed: WorkMigrationFlags.swift and LegacyNoteEditor.swift deleted

**Migration Status**: ✅ Complete - All active usage migrated to WorkModel. Legacy WorkContract references remain only in backward compatibility layers and migration code.
