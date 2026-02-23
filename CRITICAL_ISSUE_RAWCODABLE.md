# CRITICAL ISSUE: @RawCodable Incompatible with SwiftData Predicates

## Problem

The @RawCodable property wrapper approach is **fundamentally incompatible** with SwiftData's `#Predicate` query system.

### Root Cause

SwiftData Predicates require direct access to **stored properties**. Property wrappers expose computed properties (`wrappedValue`), which Predicates cannot access.

### Example Failure

```swift
// Model with @RawCodable
@Model
final class WorkModel {
    @RawCodable var status: WorkStatus = .active  // Creates computed property
}

// Query attempting to use it
@Query(filter: #Predicate<WorkModel> { $0.status != .complete })  // ❌ FAILS
private var openWork: [WorkModel]

// Error: Predicate cannot access computed properties from property wrappers
```

### Impact

- **37 references** to `.statusRaw` across codebase
- **6 Predicate queries** that filter on status
- **Multiple models** affected: WorkModel, AttendanceRecord, Note, Student, etc.

## Files Affected

### Predicate Queries (CRITICAL)
1. `Maria's Notebook/Work/WorksAgendaView.swift:15`
2. `Maria's Notebook/Presentations/PresentationsViewModel.swift`
3. `Maria's Notebook/Students/StudentsRootView.swift`
4. Multiple service files

### Direct Property Access (37 files)
- BlockingAlgorithmEngine.swift
- BlockingCacheBuilder.swift
- DataQueryService.swift
- FollowUpInboxEngine.swift
- InboxDataLoader.swift
- StudentLessonAssignmentService.swift
- TodayDataFetcher.swift
- WorkModelTests.swift
- (and 29 more...)

## Attempted Solutions

### Agent aa465f9 Refactoring
- **Status**: IN PROGRESS (must be stopped)
- **Completed**: 14 models refactored to @RawCodable
- **Issue**: All Predicate queries now broken
- **Compilation Errors**: 13 errors from this approach

## Correct Solution

### Option 1: Keep Manual Pattern (RECOMMENDED)
Revert to the manual raw value pattern for **all properties used in Predicates**:

```swift
@Model
final class WorkModel {
    // Keep manual pattern for queried properties
    private var statusRaw: String = WorkStatus.active.rawValue
    var status: WorkStatus {
        get { WorkStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    // Can use @RawCodable for non-queried properties
    @RawCodable var completionOutcome: CompletionOutcome = .mastered
}
```

### Option 2: Create Query-Safe Wrapper (ADVANCED)
Create a property wrapper that exposes the storage property:

```swift
@propertyWrapper
struct QueryableRawCodable<T: RawRepresentable> where T.RawValue == String {
    var storage: String  // PUBLIC for Predicate access

    var wrappedValue: T {
        get { T(rawValue: storage) ?? defaultValue }
        set { storage = newValue.rawValue }
    }
}

// Usage
@Model
final class WorkModel {
    @QueryableRawCodable var status: WorkStatus = .active

    // Query using storage property
    @Query(filter: #Predicate<WorkModel> { $0._status.storage != "complete" })
}
```

**Issue with Option 2**: Requires `_status.storage` syntax in Predicates, which is ugly and error-prone.

### Option 3: Hybrid Approach (RECOMMENDED)
- Use manual pattern for **frequently queried properties** (status, level, category)
- Use @RawCodable for **rarely queried properties** (completionOutcome, scheduledReason)

## Action Items

1. **STOP agent aa465f9** immediately
2. **Revert WorkModel** to manual pattern for `status`
3. **Revert AttendanceRecord** to manual pattern for `status` and `absenceReason`
4. **Update REFACTORING_PLAN.md** with corrected approach
5. **Keep @RawCodable** only for non-queried enum properties
6. **Document pattern** in ARCHITECTURE.md

## Affected Models Analysis

### Must Keep Manual Pattern (Used in Predicates)
- ✅ **WorkModel.status** - 6 Predicate queries
- ✅ **AttendanceRecord.status** - Potential queries
- ✅ **AttendanceRecord.absenceReason** - Related to status

### Can Use @RawCodable (No Predicate Usage)
- ✅ **WorkModel.completionOutcome** - Only direct access
- ✅ **WorkModel.scheduledReason** - Only direct access
- ✅ **WorkModel.sourceContextType** - Only direct access
- ✅ **Note.category** - Filtered in code, not Predicates
- ✅ **Student.level** - Need to verify query usage
- ✅ **Procedure.category** - Need to verify query usage

## Lessons Learned

1. **Property wrappers ≠ SwiftData Predicates**
   - Predicates work at the **storage level**
   - Property wrappers hide storage behind **computed properties**

2. **Performance implications**
   - Manual pattern: 3 lines per property × 80 properties = 240 lines
   - @RawCodable savings: Only for ~40 non-queried properties = 120 lines saved
   - **Net benefit: 50% reduction, not 100%**

3. **Architecture matters**
   - Must understand framework constraints before designing abstractions
   - "Elegant" solutions can be incompatible with platform requirements

## Recommended Path Forward

1. **Phase 1 Revision**: Use hybrid approach
   - Manual pattern for queried properties (status, level)
   - @RawCodable for non-queried properties (completionOutcome, scheduledReason)

2. **Phase 2**: CloudKitUUID still viable
   - UUIDs are not used in Predicate comparisons
   - String storage works for equality/fetch operations

3. **Phase 3**: Focus on other refactorings
   - Migration consolidation
   - Service dependency injection
   - These have no SwiftData compatibility issues

## Timeline Impact

- **Original estimate**: 2 hours for @RawCodable refactoring
- **Actual time spent**: 3 hours (including agent work)
- **Revert time**: 1 hour
- **Hybrid approach time**: 2 hours
- **Total delay**: +4 hours on Phase 1

## Status: BLOCKING

This issue is **blocking Phase 1 completion** until resolved.

---

**Created**: 2026-02-04T04:55:00Z
**Severity**: CRITICAL
**Assigned**: Immediate fix required
