# Phase 4: Dependency Injection - Implementation Plan

**Status:** 🟡 In Progress
**Branch:** `refactor/phase-1-foundation`
**Started:** 2026-02-05

---

## Executive Summary

Phase 4 will systematically migrate all service initialization to use the existing `AppDependencies` DI container. This provides centralized service management, improves testability, and eliminates inconsistent singleton patterns.

**Scope:** 23+ services, 60+ files
**Risk Level:** 🟢 Low - No behavior changes, pure architectural refactoring
**Test Coverage:** ✅ 2,373+ tests provide comprehensive regression detection

---

## Critical Constraints

### MUST NOT Change:
- ✅ **No UI/UX changes** - All visual behavior must remain identical
- ✅ **No behavior changes** - All business logic must function exactly as before
- ✅ **No API changes** - Service public interfaces remain unchanged
- ✅ **No data changes** - SwiftData models and persistence unchanged

### Success Criteria:
- ✅ All tests pass (2,373+ tests)
- ✅ Build succeeds with 0 errors, 0 warnings
- ✅ App launches and functions identically to before
- ✅ No visible changes to user experience

---

## Current State Analysis

### Infrastructure Already Complete ✅

**AppDependencies.swift** (322 lines) provides:
- Centralized DI container with lazy initialization
- Environment key integration (`@Environment(\.dependencies)`)
- Test helper (`AppDependencies.makeTest()`)
- 18 services already registered

### Migration Targets

From codebase analysis (agent a6a16c3), identified:

| Category | Count | Pattern | Files |
|----------|-------|---------|-------|
| Direct Service Instantiation | 9 files | `= Service()` | SettingsViewModel, SelectiveRestoreService, etc. |
| Singleton Access in Views | 5+ files | `.shared` | CloudKitStatusSettingsView, SyncStatusBadge, etc. |
| Service-to-Service Dependencies | 7 services | Nested instantiation | Backup services creating BackupService |
| Orphaned Singletons | 4+ services | Not in DI container | ToastService, SyncedPreferencesStore, etc. |

---

## Implementation Strategy

### Step 1: Add Missing Services to AppDependencies ✅ Already Present

These services need registration in AppDependencies:
- [ ] ToastService (currently `.shared` singleton)
- [ ] SyncedPreferencesStore (currently `.shared` singleton)
- [ ] AppCalendar (currently `.shared` utility)
- [ ] CurriculumIntroductionStore (currently `.shared` singleton)
- [ ] EntityFetcherRegistry (currently `.shared` singleton)

### Step 2: Refactor Service-to-Service Dependencies (7 services)

**Pattern Change:**
```swift
// BEFORE: Service creates own dependencies
class CloudBackupService {
    private let backupService = BackupService()
}

// AFTER: Service receives dependencies via init
class CloudBackupService {
    private let backupService: BackupService

    init(backupService: BackupService, modelContext: ModelContext) {
        self.backupService = backupService
        self.modelContext = modelContext
    }
}
```

**Files to Update:**
1. `Backup/Services/CloudBackupService.swift` (line 112)
2. `Backup/Services/SelectiveRestoreService.swift` (line 120)
3. `Backup/Services/IncrementalBackupService.swift` (line 53)
4. `Backup/Services/BackupSharingService.swift` (line 83)
5. `Backup/Services/BackupTransactionManager.swift` (line 47)
6. `Backup/Services/SelectiveExportService.swift` (line 285)
7. `Backup/AutoBackupManager.swift` (line 56)

### Step 3: Refactor ViewModels (3 files)

**Pattern Change:**
```swift
// BEFORE: ViewModel creates own services
class SettingsViewModel {
    private let backupService = BackupService()
}

// AFTER: ViewModel receives dependencies
class SettingsViewModel {
    private let dependencies: AppDependencies

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    // Access services via dependencies.backupService
}
```

**Files to Update:**
1. `Settings/SettingsViewModel.swift` (line 28)
2. `Students/StudentDetailViewModel.swift` (line 174 - ToastService.shared)
3. `Components/ReportGeneratorView.swift` (line 24)

### Step 4: Refactor Views to Use Environment (5+ files)

**Pattern Change:**
```swift
// BEFORE: View accesses singleton
struct CloudKitStatusSettingsView: View {
    @StateObject private var syncService = CloudKitSyncStatusService.shared
}

// AFTER: View uses environment dependencies
struct CloudKitStatusSettingsView: View {
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        // Access via dependencies.cloudKitSyncStatusService
    }
}
```

**Files to Update:**
1. `Settings/CloudKitStatusSettingsView.swift` (line 6)
2. `Components/SyncStatusBadge.swift` (line 6, 39)
3. `Settings/CalendarSyncSettingsView.swift` (line 9)
4. `Settings/ReminderSyncSettingsView.swift` (implicit singleton access)
5. `Backup/BackupRestoreSettingsView.swift` (potential)

### Step 5: Update AppDependencies Registrations

Ensure all lazy services use init-based dependency injection:

```swift
// Example pattern in AppDependencies.swift
lazy var cloudBackupService: CloudBackupService = {
    CloudBackupService(
        backupService: backupService,  // ← Inject dependency
        modelContext: modelContext
    )
}()
```

---

## Incremental Rollout Plan

### Phase 4.1: Infrastructure Preparation (30 min)
- [x] Create Phase 4 plan document
- [ ] Add missing singleton services to AppDependencies
- [ ] Update AppDependencies service registrations
- [ ] Build and test infrastructure changes

### Phase 4.2: Service Layer Refactoring (2 hours)
- [ ] Refactor 7 backup services to accept dependencies via init
- [ ] Update AppDependencies to inject dependencies
- [ ] Run BackupServiceTests (existing tests)
- [ ] Verify no behavior changes

### Phase 4.3: ViewModel Refactoring (1 hour)
- [ ] Refactor SettingsViewModel
- [ ] Refactor StudentDetailViewModel
- [ ] Refactor ReportGeneratorView
- [ ] Run ViewModel tests (150+ existing tests)
- [ ] Verify functionality unchanged

### Phase 4.4: View Layer Refactoring (1 hour)
- [ ] Refactor CloudKitStatusSettingsView
- [ ] Refactor SyncStatusBadge
- [ ] Refactor CalendarSyncSettingsView
- [ ] Refactor ReminderSyncSettingsView
- [ ] Build and verify UI unchanged

### Phase 4.5: Integration Testing (30 min)
- [ ] Run all 2,373+ tests
- [ ] Build project (verify 0 errors, 0 warnings)
- [ ] Manual smoke test: Launch app
- [ ] Manual smoke test: Today view
- [ ] Manual smoke test: Settings → Backup
- [ ] Manual smoke test: Settings → Sync
- [ ] Verify no visual or behavioral changes

### Phase 4.6: Documentation & Commit (15 min)
- [ ] Update REFACTORING_PROGRESS.md
- [ ] Create PHASE_4_COMPLETE.md
- [ ] Commit with detailed message
- [ ] Tag `phase-4-di-complete`

---

## Risk Mitigation

### Low-Risk Approach
1. **Incremental changes** - One service category at a time
2. **Continuous testing** - Run tests after each subsection
3. **Build verification** - Ensure compilation after each change
4. **Git safety** - Commit working states frequently

### Rollback Strategy
- Each phase commits to git
- Can revert to previous phase if issues arise
- Tag `pre-phase-4-di` before starting

### Zero Behavior Change Guarantee
- All service logic remains unchanged
- Only initialization mechanism changes
- Public APIs remain identical
- Tests verify exact same behavior

---

## Files Modified Summary

### Core DI Files (1 file)
- `AppCore/AppDependencies.swift` - Add 5+ services, update registrations

### Service Layer (7 files)
- `Backup/Services/CloudBackupService.swift`
- `Backup/Services/SelectiveRestoreService.swift`
- `Backup/Services/IncrementalBackupService.swift`
- `Backup/Services/BackupSharingService.swift`
- `Backup/Services/BackupTransactionManager.swift`
- `Backup/Services/SelectiveExportService.swift`
- `Backup/AutoBackupManager.swift`

### ViewModel Layer (3 files)
- `Settings/SettingsViewModel.swift`
- `Students/StudentDetailViewModel.swift`
- `Components/ReportGeneratorView.swift`

### View Layer (5 files)
- `Settings/CloudKitStatusSettingsView.swift`
- `Components/SyncStatusBadge.swift`
- `Settings/CalendarSyncSettingsView.swift`
- `Settings/ReminderSyncSettingsView.swift`
- `Backup/BackupRestoreSettingsView.swift` (if needed)

**Total:** ~16 files modified, 0 files added, 0 files deleted

---

## Expected Outcomes

### Code Quality Improvements
- ✅ Consistent service access pattern throughout codebase
- ✅ Eliminated 4+ orphaned singleton patterns
- ✅ Centralized service lifecycle management
- ✅ Improved testability with `AppDependencies.makeTest()`

### Maintainability Benefits
- ✅ Single source of truth for service initialization
- ✅ Clear dependency relationships
- ✅ Easier to mock services in tests
- ✅ Reduced coupling between components

### No Negative Impact
- ✅ Zero behavior changes
- ✅ Zero UI/UX changes
- ✅ Zero performance impact
- ✅ Zero breaking changes to APIs

---

## Success Metrics

| Metric | Target | Verification |
|--------|--------|--------------|
| Build Errors | 0 | Xcode build |
| Build Warnings | 0 | Xcode build |
| Test Failures | 0 | Run 2,373+ tests |
| Singleton Access | 0 | Code review (eliminate .shared) |
| Direct Instantiation | 0 | Code review (eliminate = Service()) |
| UI Changes | 0 | Manual smoke test |
| Behavior Changes | 0 | Test suite + manual verification |

---

## Next Steps After Phase 4

With DI complete, subsequent phases become easier:

### Phase 2: CloudKitUUID Migration
- Services easily testable with DI
- Can inject mock services for UUID migration testing

### Phase 7: Reactive Caching
- CacheCoordinator already in DI container
- Easy to wire up cache invalidation across services

### Phase 6: Backup Overhaul
- GenericBackupCodec already tested
- DI makes backup service coordination cleaner

---

**Last Updated:** 2026-02-05
**Status:** Ready to begin Phase 4.1
**Estimated Duration:** 5 hours
**Risk Level:** 🟢 Low (pure refactoring, no behavior changes)
