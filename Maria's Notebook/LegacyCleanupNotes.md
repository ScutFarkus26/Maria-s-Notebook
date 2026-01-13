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

11. **Models/Note.swift**
    - Usage: Has @Relationship var workContract: WorkContract?
    - Status: MIGRATE - Should use work relationship instead (WorkModel)
    - Action: Update code to use `work` relationship, deprecate `workContract`

12. **Models/ScopedNote.swift**
    - Usage: Has @Relationship var workContract: WorkContract? and workContractID: String?
    - Status: MIGRATE - Should use work relationship instead (WorkModel)
    - Action: Update code to use `work` relationship, deprecate `workContract` and `workContractID`

13. **Students/StudentDetailView.swift**
    - Usage: Displays WorkContract items
    - Status: REMOVE - Should display WorkModel
    - Action: Replace WorkContract with WorkModel

14. **Students/StudentsRootView.swift**
    - Usage: Queries and displays WorkContract items
    - Status: REMOVE - Should use WorkModel
    - Action: Replace WorkContract queries with WorkModel

15. **Work/WorkContractDetailSheet.swift**
    - Usage: Displays details of a WorkContract
    - Status: REMOVE - Should use WorkModelDetailSheet or update to WorkModel
    - Action: Replace or update to use WorkModel

16. **Components/UnifiedNoteEditor.swift**
    - Usage: Has .workContract case in NoteContext enum
    - Status: REMOVE - Should use .work case
    - Action: Replace .workContract with .work

17. **Components/ObservationsView.swift**
    - Usage: Checks for workContract relationship
    - Status: REMOVE - Should check work relationship
    - Action: Update to use work relationship

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

21. **Students/StudentProgressTab.swift**
    - Usage: Filters allWorkContracts
    - Status: REMOVE - Should filter WorkModel
    - Action: Replace with WorkModel

22. **Students/StudentNotesViewModel.swift**
    - Usage: Filters notes by workContractID
    - Status: UPDATE - Should filter by work relationship
    - Action: Update to use work relationship

23. **Students/ObservationHeatmapView.swift**
    - Usage: Filters notes by workContractID
    - Status: UPDATE - Should filter by work relationship
    - Action: Update to use work relationship

24. **Services/InboxDataLoader.swift**
    - Usage: Loads notes filtered by workContractID
    - Status: UPDATE - Should filter by work relationship
    - Action: Update to use work relationship

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

29. **Settings/SettingsStatsViewModel.swift**
    - Usage: Counts workContracts
    - Status: UPDATE - Should count WorkModel
    - Action: Replace with WorkModel count

30. **Settings/SettingsView.swift**
    - Usage: Displays workContractsCount
    - Status: UPDATE - Should display WorkModel count
    - Action: Already uses statsViewModel, verify it counts WorkModel

31. **Debug/TrackPopulationView.swift**
    - Usage: Fetches WorkContract for scanning
    - Status: UPDATE - Should scan WorkModel
    - Action: Replace with WorkModel

32. **Tests/CloudKitStatusView.swift**
    - Usage: Queries WorkContract for counts
    - Status: UPDATE - Should query WorkModel
    - Action: Replace with WorkModel

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

## Summary
- **Migration Code**: 2 files - KEEP
- **Backward Compatibility**: 5-8 files - REVIEW/KEEP
- **Active Usage to Update**: 26-30 files - UPDATE/REMOVE
