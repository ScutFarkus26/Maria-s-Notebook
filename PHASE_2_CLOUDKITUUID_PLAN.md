# Phase 2: CloudKitUUID Property Wrapper Migration - Implementation Plan

**Status:** 🟡 Planning Complete, Ready to Execute
**Branch:** `refactor/phase-1-foundation`
**Started:** 2026-02-05

---

## Executive Summary

Phase 2 will migrate **47 String UUID fields** across **20 SwiftData models** to use the `@CloudKitUUID` property wrapper, providing type-safe UUID access while maintaining CloudKit String storage compatibility.

**Scope:** 47 single UUID fields + array handling review
**Risk Level:** 🟡 Medium - Extensive but mechanical changes
**Test Coverage:** ✅ CloudKitUUID tested (20 tests), 2,373+ total tests provide regression detection

---

## Critical Architecture Decision

### ADR-002: CloudKitUUID is SAFE ✅

Unlike the failed `@RawCodable` approach (ADR-001), `@CloudKitUUID` is **approved for use** because:

✅ **UUIDs are NOT used in Predicate comparisons**
- Queries filter by the underlying String field
- Property wrapper provides computed UUID access only
- No SwiftData Predicate conflicts

```swift
// ✅ SAFE - Predicate doesn't access the property wrapper
@CloudKitUUID var studentID: UUID = UUID()

// Query uses the underlying String storage
let predicate = #Predicate<WorkModel> { work in
    work.$studentID == someStringID  // Uses projected value (String)
}
```

**Reference:** ARCHITECTURE_DECISIONS.md (ADR-002)

---

## Migration Analysis Summary

**Total UUID Fields Found:** 47 single UUID fields across 20 models

### Breakdown by Model Category:

1. **Work System (18 fields):**
   - WorkModel (7 fields): studentID, lessonID, presentationID, trackID, trackStepID, sourceContextID, legacyStudentLessonID
   - WorkCheckIn (1 field): workID
   - WorkPlanItem (1 field): workID
   - WorkCompletionRecord (2 fields): workID, studentID
   - WorkParticipantEntity (1 field): studentID
   - LessonPresentation (5 fields): studentID, lessonID, presentationID, trackID, trackStepID
   - Presentation/LessonAssignment (7 fields): lessonID, trackID, trackStepID, migratedFromStudentLessonID, migratedFromPresentationID

2. **Student System (9 fields):**
   - StudentLessonModel (1 field): lessonID
   - StudentModel (array field - already handled)
   - StudentMeeting (1 field): studentID
   - StudentTrackEnrollment (2 fields): studentID, trackID
   - AttendanceModels (1 field): studentID
   - NoteStudentLink (2 fields): noteID, studentID

3. **Project System (9 fields):**
   - ProjectAssignmentTemplate (2 fields): projectID, defaultLinkedLessonID
   - ProjectSession (2 fields): projectID, templateWeekID
   - ProjectRole (1 field): projectID
   - ProjectTemplateWeek (1 field): projectID
   - ProjectWeekRoleAssignment (3 fields): weekID, studentID, roleID

4. **Other Models (11 fields):**
   - IssueAction (1 field): issueID
   - ScheduleSlot (2 fields): scheduleID, studentID
   - SupplyTransaction (1 field): supplyID
   - PracticeSession (2 array fields - already handled)

---

## Migration Strategy

### Phase 2A: Infrastructure Verification (30 min)
- [x] CloudKitUUID implementation exists (Utils/CloudKitUUID.swift)
- [x] CloudKitUUID tests passing (20 tests)
- [x] ADR-002 documents approval
- [ ] Create migration helper utilities if needed

### Phase 2B: High-Priority Models (2 hours)
Migrate the most frequently accessed models first:

**Priority 1: WorkModel** (7 UUID fields)
- `@CloudKitUUID var studentID: UUID`
- `@CloudKitUUID var lessonID: UUID`
- `@CloudKitUUID var presentationID: UUID?`
- `@CloudKitUUID var trackID: UUID?`
- `@CloudKitUUID var trackStepID: UUID?`
- `@CloudKitUUID var sourceContextID: UUID?`
- `@CloudKitUUID var legacyStudentLessonID: UUID?`

**Priority 2: Presentation/LessonAssignment** (7 UUID fields)
- Critical for lesson scheduling system
- High query frequency

**Priority 3: StudentLessonModel** (1 UUID field)
- Core relationship model

### Phase 2C: Relationship Models (1 hour)
Junction tables and relationship models:
- WorkCheckIn, WorkPlanItem, WorkCompletionRecord
- StudentMeeting, StudentTrackEnrollment
- NoteStudentLink
- ProjectWeekRoleAssignment

### Phase 2D: Project System (1 hour)
- ProjectAssignmentTemplate
- ProjectSession
- ProjectRole
- ProjectTemplateWeek

### Phase 2E: Supporting Models (30 min)
- IssueAction
- ScheduleSlot
- SupplyTransaction
- AttendanceModels

### Phase 2F: Repository & Service Updates (1.5 hours)
Update all code accessing the String fields:
- Remove manual `UUID(uuidString:)` conversions
- Update Predicate queries to use projected value `$fieldName`
- Update service methods expecting String parameters

### Phase 2G: Testing & Validation (1 hour)
- Run full test suite (2,373+ tests)
- Verify no new failures
- Manual smoke testing
- Performance verification

---

## Migration Pattern

### Before: String Storage
```swift
@Model
final class WorkModel {
    var studentID: String = ""  // CloudKit compatible but not type-safe

    // Computed property for UUID access
    var studentUUID: UUID? {
        UUID(uuidString: studentID)
    }
}

// Usage - manual conversion everywhere
if let uuid = work.studentUUID {
    // Use uuid
}
```

### After: @CloudKitUUID
```swift
@Model
final class WorkModel {
    @CloudKitUUID var studentID: UUID = UUID()  // Type-safe access, String storage
}

// Usage - direct UUID access
let uuid = work.studentID  // Already a UUID!

// Predicate queries use projected value
let predicate = #Predicate<WorkModel> { work in
    work.$studentID == someStringID  // Uses String storage
}
```

---

## Code Changes Breakdown

### Model Files to Modify (20 files):
1. `Work/WorkModel.swift` - 7 fields
2. `Models/Presentation.swift` - 7 fields
3. `Students/StudentLessonModel.swift` - 1 field
4. `Work/WorkCheckIn.swift` - 1 field
5. `Work/WorkPlanItem.swift` - 1 field
6. `Work/WorkCompletionRecord.swift` - 2 fields
7. `Work/WorkParticipantEntity.swift` - 1 field
8. `Models/LessonPresentation.swift` - 5 fields
9. `Students/StudentMeeting.swift` - 1 field
10. `Models/StudentTrackEnrollment.swift` - 2 fields
11. `Attendance/AttendanceModels.swift` - 1 field
12. `Models/NoteStudentLink.swift` - 2 fields
13. `Models/IssueModels.swift` - 1 field (IssueAction)
14. `Models/Schedule.swift` - 2 fields (ScheduleSlot)
15. `Models/Supply.swift` - 1 field (SupplyTransaction)
16. `Projects/ProjectModels.swift` - 4 fields (ProjectAssignmentTemplate, ProjectSession)
17. `Projects/ProjectTemplateModels.swift` - 5 fields (ProjectRole, ProjectTemplateWeek, ProjectWeekRoleAssignment)

### Repository/Service Files to Update (estimated 30-50 files):
- All repositories accessing UUID String fields
- Services creating or querying models with UUID fields
- ViewModels passing UUID strings
- Migration services handling legacy UUIDs

---

## Incremental Rollout Plan

### Step 1: Single Model Pilot (WorkModel)
1. Update WorkModel with @CloudKitUUID
2. Remove computed `studentUUID` property (breaking change - but property wrapper provides same access)
3. Update WorkRepository Predicate queries
4. Run WorkModel tests
5. Verify no regressions
6. **Commit:** "Migrate WorkModel to @CloudKitUUID"

### Step 2: Batch Migration (5 models at a time)
Repeat for each batch:
1. Update 5 model files
2. Update related repositories
3. Update related services
4. Run tests
5. Commit batch

**Batches:**
- Batch 1: WorkModel, WorkCheckIn, WorkPlanItem, WorkCompletionRecord, WorkParticipantEntity
- Batch 2: Presentation, StudentLessonModel, StudentMeeting, StudentTrackEnrollment, AttendanceModels
- Batch 3: LessonPresentation, NoteStudentLink, IssueAction, ScheduleSlot, SupplyTransaction
- Batch 4: All Project models (5 models)

### Step 3: Service Layer Updates
Update services in dependency order:
1. Core services (LifecycleService, WorkCompletionService)
2. Track services (GroupTrackService, StudentTrackEnrollment)
3. Backup services (already using String storage)
4. UI services (ViewModels)

### Step 4: Integration Testing
- Run full test suite
- Manual smoke test all major workflows
- Performance benchmarks
- CloudKit sync verification

---

## Breaking Changes & Mitigation

### Removed Computed UUID Properties
**Before:**
```swift
var studentUUID: UUID? {
    UUID(uuidString: studentID)
}
```

**After:**
```swift
// Property removed - use studentID directly (now a UUID)
let uuid = work.studentID  // UUID type
```

**Migration:** Global search/replace for `.studentUUID` → `.studentID`

### Predicate Queries
**Before:**
```swift
#Predicate<WorkModel> { work in
    work.studentID == stringID
}
```

**After:**
```swift
#Predicate<WorkModel> { work in
    work.$studentID == stringID  // Use projected value
}
```

**Migration:** Update all Predicate queries to use projected value

---

## Risk Mitigation

### Low-Risk Approach
1. **Incremental batches** - 5 models at a time
2. **Continuous testing** - Run tests after each batch
3. **Build verification** - Ensure compilation after each change
4. **Git safety** - Commit working states for each batch

### Rollback Strategy
- Each batch commits to git
- Can revert individual batches if issues arise
- Tag `pre-phase-2-cloudkituuid` before starting
- CloudKitUUID is additive (doesn't break existing String storage)

### Zero Data Loss Guarantee
- Property wrapper stores as String (CloudKit compatible)
- Existing data remains unchanged
- Only access pattern changes (String → UUID)
- Backward compatible with existing backups

---

## Expected Outcomes

### Code Quality Improvements
- ✅ Type-safe UUID access (no more manual conversions)
- ✅ Eliminated 47 computed UUID properties
- ✅ Reduced boilerplate (no `UUID(uuidString:)` everywhere)
- ✅ Compile-time safety (only UUID values accepted)

### Maintainability Benefits
- ✅ Clear intent (field is a UUID, not a String)
- ✅ Prevents accidental String assignment
- ✅ Easier to understand relationships
- ✅ Consistent pattern across all models

### No Negative Impact
- ✅ Zero behavior changes
- ✅ Zero data migration required
- ✅ Zero CloudKit sync changes
- ✅ Zero performance impact

---

## Success Metrics

| Metric | Target | Verification |
|--------|--------|--------------|
| Build Errors | 0 | Xcode build |
| Build Warnings | 0 | Xcode build |
| Test Failures (new) | 0 | Run 2,373+ tests |
| Models Migrated | 20 | Code review |
| UUID Fields Migrated | 47 | Code review |
| Data Loss | 0 | Backup verification |
| CloudKit Compatibility | 100% | Sync testing |

---

## Timeline Estimate

**Total Duration:** 8-10 hours

| Phase | Duration | Description |
|-------|----------|-------------|
| 2A: Infrastructure | 30 min | Verify CloudKitUUID ready |
| 2B: High-Priority Models | 2 hours | WorkModel, Presentation, StudentLesson |
| 2C: Relationship Models | 1 hour | Junction tables |
| 2D: Project System | 1 hour | Project models |
| 2E: Supporting Models | 30 min | Attendance, Schedule, etc. |
| 2F: Repository/Service Updates | 1.5 hours | Update all access code |
| 2G: Testing & Validation | 1 hour | Full test suite + manual |
| **Buffer** | 1.5 hours | Unexpected issues |
| **Total** | 8-10 hours | Complete migration |

---

## Next Steps After Phase 2

With CloudKitUUID migration complete, subsequent phases benefit:

### Phase 3: Data Model Consolidation
- Type-safe UUIDs simplify relationship tracking
- Easier to identify and fix orphaned references

### Phase 6: Backup Overhaul
- GenericBackupCodec handles @CloudKitUUID seamlessly
- UUID type safety prevents backup corruption

### Phase 7: Reactive Caching
- Cache keys can use UUIDs directly
- No String conversion overhead

---

**Last Updated:** 2026-02-05
**Status:** 📋 Plan Complete - Ready to Execute
**Estimated Completion:** 8-10 hours
**Risk Level:** 🟡 Medium (mechanical changes, well-tested infrastructure)
