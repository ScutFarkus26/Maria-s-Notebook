# Phase 5: Testing Infrastructure

**Status:** 🟢 Starting Now (Option C: Low-Risk First)
**Duration:** 6 weeks
**Risk Level:** 🟢 Low
**Dependencies:** None (can start immediately)

---

## Overview

Build comprehensive test coverage before tackling risky data model changes. This creates a safety net that will catch regressions during Phases 2, 3, 6, and 8.

**Current State:**
- ✅ 2080 existing tests
- ✅ PerformanceBenchmarks.swift ready (8 benchmarks)
- ⚠️ Missing: Service layer tests, ViewModel tests, integration tests
- ⚠️ Coverage gaps: Core business logic (LifecycleService, WorkCompletion, etc.)

**Goal State:**
- 🎯 3500+ total tests
- 🎯 80%+ coverage on service layer
- 🎯 Integration tests for critical user flows
- 🎯 Performance regression suite running in CI
- 🎯 Migration integrity verification tests

---

## Week 1: Service Layer Tests (Foundation)

### Task 5.1.1: Core Service Tests (3 days)

**Priority: CRITICAL** - These services power the entire app

**Services to Test:**

1. **LifecycleService** (Most Critical)
   - `recordPresentationAndExplodeWork()` - Work creation logic
   - State transitions and validation
   - Error handling and rollback
   - **Target:** 25 tests

2. **GroupTrackService**
   - Track creation and progression
   - Step completion logic
   - Curriculum sequencing
   - **Target:** 20 tests

3. **WorkCompletionService**
   - Completion recording
   - History tracking
   - Duplicate prevention
   - **Target:** 15 tests

4. **DataQueryService**
   - Complex multi-model queries
   - Performance under load
   - Cache invalidation
   - **Target:** 20 tests

**Test Pattern:**
```swift
@Suite("LifecycleService Tests")
struct LifecycleServiceTests {
    @Test("Record presentation creates work items")
    func recordPresentationCreatesWork() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext

        // Given: A student and lesson
        let student = Student(name: "Test Student")
        let lesson = Lesson(name: "Test Lesson")
        context.insert(student)
        context.insert(lesson)

        // When: Recording a presentation
        let result = try await LifecycleService.recordPresentationAndExplodeWork(
            studentID: student.id,
            lessonID: lesson.id,
            givenAt: Date(),
            in: context
        )

        // Then: Work items created
        #expect(result.workItemsCreated > 0)

        let descriptor = FetchDescriptor<WorkModel>()
        let work = try context.fetch(descriptor)
        #expect(work.count > 0)
        #expect(work.first?.status == .active)
    }
}
```

### Task 5.1.2: Backup Service Tests (2 days)

**Services to Test:**

1. **BackupService**
   - Export with encryption
   - Restore with conflict resolution
   - Size estimation accuracy
   - **Target:** 15 tests

2. **GenericBackupCodec** (NEW infrastructure)
   - Entity discovery
   - Encoding/decoding round-trip
   - Version compatibility
   - **Target:** 12 tests

**Deliverables:**
- `Tests/Services/LifecycleServiceTests.swift` (25 tests)
- `Tests/Services/GroupTrackServiceTests.swift` (20 tests)
- `Tests/Services/WorkCompletionServiceTests.swift` (15 tests)
- `Tests/Services/DataQueryServiceTests.swift` (20 tests)
- `Tests/Backup/BackupServiceTests.swift` (15 tests)
- `Tests/Backup/GenericBackupCodecTests.swift` (12 tests)

**Total Week 1:** 107 new tests

---

## Week 2: ViewModel Tests (User-Facing Logic)

### Task 5.2.1: Critical ViewModel Tests (3 days)

**ViewModels to Test:**

1. **TodayViewModel** (Most Complex)
   - Data fetching and caching
   - Date navigation
   - Filtering and sorting
   - Performance under 1000+ lessons
   - **Target:** 20 tests

2. **WorksPlanningViewModel**
   - Work item creation
   - Status transitions
   - Scheduling logic
   - **Target:** 15 tests

3. **AttendanceViewModel**
   - Bulk operations (mark all present)
   - Status changes with reason clearing
   - Date range queries
   - **Target:** 12 tests

### Task 5.2.2: Supporting ViewModel Tests (2 days)

**ViewModels to Test:**

4. **StudentDetailViewModel**
5. **PresentationsViewModel**
6. **InboxSheetViewModel**

**Target:** 10 tests each = 30 tests

**Test Pattern:**
```swift
@Suite("TodayViewModel Tests")
@MainActor
struct TodayViewModelTests {
    @Test("Today view loads lessons for selected date")
    func loadsLessonsForDate() async throws {
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext

        // Given: Lessons on specific date
        let targetDate = Date()
        let lesson1 = Lesson(name: "Math", scheduledFor: targetDate)
        let lesson2 = Lesson(name: "Science", scheduledFor: targetDate)
        context.insert(lesson1)
        context.insert(lesson2)
        try context.save()

        // When: ViewModel loads for date
        let viewModel = TodayViewModel(dependencies: deps)
        await viewModel.loadData(for: targetDate)

        // Then: Lessons appear
        #expect(viewModel.lessons.count == 2)
        #expect(viewModel.lessons.contains { $0.name == "Math" })
    }
}
```

**Deliverables:**
- `Tests/ViewModels/TodayViewModelTests.swift` (20 tests)
- `Tests/ViewModels/WorksPlanningViewModelTests.swift` (15 tests)
- `Tests/ViewModels/AttendanceViewModelTests.swift` (12 tests)
- `Tests/ViewModels/StudentDetailViewModelTests.swift` (10 tests)
- `Tests/ViewModels/PresentationsViewModelTests.swift` (10 tests)
- `Tests/ViewModels/InboxSheetViewModelTests.swift` (10 tests)

**Total Week 2:** 77 new tests

---

## Week 3: Integration Tests (Critical User Flows)

### Task 5.3.1: Core User Flow Tests (5 days)

**Integration Tests to Create:**

1. **Today View Load Flow** (CRITICAL)
   ```
   App Launch → Today View → Load Lessons/Work/Attendance → Display
   ```
   - Tests full data pipeline
   - Performance under load
   - Error recovery
   - **Target:** 8 tests

2. **Work Completion Flow**
   ```
   View Work → Mark Complete → Record Outcome → Update Status → Refresh Lists
   ```
   - End-to-end work lifecycle
   - Status transitions
   - UI updates
   - **Target:** 6 tests

3. **Presentation Recording Flow**
   ```
   Select Student → Choose Lesson → Record Presentation → Create Work → Update Progress
   ```
   - Tests LifecycleService integration
   - Multi-model updates
   - Rollback on error
   - **Target:** 7 tests

4. **Attendance Marking Flow**
   ```
   Open Attendance → Mark Students → Save → Email Summary
   ```
   - Bulk operations
   - Email generation
   - Status validation
   - **Target:** 5 tests

5. **Backup/Restore Flow**
   ```
   Export Backup → Encrypt → Import → Restore All Data → Verify Integrity
   ```
   - Full backup round-trip
   - Conflict resolution
   - Data integrity checks
   - **Target:** 6 tests

**Test Pattern:**
```swift
@Suite("Integration: Today View Load")
@MainActor
struct TodayViewLoadIntegrationTests {
    @Test("Complete today view load with realistic data")
    func completeLoadFlow() async throws {
        // Given: Realistic dataset
        let deps = AppDependencies.makeTest()
        let context = deps.modelContext

        // Seed 100 students, 1000 lessons, 500 work items
        try await seedRealisticData(context: context)

        // When: Load today view
        let startTime = Date()
        let viewModel = TodayViewModel(dependencies: deps)
        await viewModel.loadData(for: Date())
        let duration = Date().timeIntervalSince(startTime)

        // Then: Loads successfully and quickly
        #expect(viewModel.lessons.count > 0)
        #expect(viewModel.workItems.count > 0)
        #expect(duration < 0.200) // < 200ms target

        // And: Data is correct
        #expect(viewModel.lessons.allSatisfy { $0.scheduledFor != nil })
        #expect(viewModel.workItems.allSatisfy { $0.status != .complete })
    }
}
```

**Deliverables:**
- `Tests/Integration/TodayViewLoadIntegrationTests.swift` (8 tests)
- `Tests/Integration/WorkCompletionFlowTests.swift` (6 tests)
- `Tests/Integration/PresentationRecordingFlowTests.swift` (7 tests)
- `Tests/Integration/AttendanceMarkingFlowTests.swift` (5 tests)
- `Tests/Integration/BackupRestoreFlowTests.swift` (6 tests)

**Total Week 3:** 32 new tests

---

## Week 4: Performance & Regression Suite

### Task 5.4.1: Expand Performance Benchmarks (3 days)

**Build on existing PerformanceBenchmarks.swift:**

Add benchmarks for:
1. **Migration Performance** (Phase 8 prep)
   - Large dataset migration timing
   - Rollback performance
   - **Target:** 3 benchmarks

2. **Cache Effectiveness** (Phase 7 prep)
   - Cache hit rates
   - Invalidation performance
   - **Target:** 3 benchmarks

3. **DI Container Overhead** (Phase 4 prep)
   - Service initialization timing
   - Lazy loading efficiency
   - **Target:** 2 benchmarks

### Task 5.4.2: Regression Detection Tests (2 days)

Create tests that detect common regressions:

1. **Query Performance Regression**
   - Baseline: 50ms for 1000 lessons
   - Alert if > 75ms

2. **Memory Leak Detection**
   - ViewModel cleanup verification
   - Retain cycle detection

3. **Startup Time Regression**
   - Baseline: < 2s cold start
   - Alert if > 3s

**Deliverables:**
- 8 new performance benchmarks
- 10 regression detection tests
- CI integration guide

**Total Week 4:** 18 new benchmarks/tests

---

## Week 5: Migration Integrity Tests (Phase 8 Prep)

### Task 5.5.1: Migration Verification Tests (5 days)

**Critical for Phase 8 safety:**

1. **Schema Migration Tests**
   - UUID to String conversion correctness
   - Date normalization accuracy
   - Enum raw value consistency
   - **Target:** 10 tests

2. **Data Integrity Tests**
   - Relationship preservation
   - No data loss verification
   - Foreign key validity
   - **Target:** 8 tests

3. **Rollback Tests**
   - Rollback to previous version
   - State consistency after rollback
   - **Target:** 5 tests

**Test Pattern:**
```swift
@Suite("Migration Integrity Tests")
struct MigrationIntegrityTests {
    @Test("UUID to String migration preserves all relationships")
    func uuidToStringPreservesRelationships() async throws {
        let context = ModelContext(...)

        // Given: Pre-migration data with UUIDs
        let student = Student(id: UUID())
        let work = WorkModel(studentID: student.id.uuidString)
        context.insert(student)
        context.insert(work)
        try context.save()

        // When: Run migration
        try await MigrationRegistry.runPending(context: context)

        // Then: Relationships still valid
        let fetchedWork = try context.fetch(FetchDescriptor<WorkModel>())
        #expect(fetchedWork.first?.studentID == student.id.uuidString)

        // And: Can still query
        let studentFromWork = try context.fetch(
            FetchDescriptor<Student>(
                predicate: #Predicate { $0.id.uuidString == work.studentID }
            )
        )
        #expect(studentFromWork.count == 1)
    }
}
```

**Deliverables:**
- `Tests/Migrations/SchemaMigrationTests.swift` (10 tests)
- `Tests/Migrations/DataIntegrityTests.swift` (8 tests)
- `Tests/Migrations/RollbackTests.swift` (5 tests)

**Total Week 5:** 23 new tests

---

## Week 6: Edge Cases & Polish

### Task 5.6.1: Edge Case Tests (3 days)

Test boundary conditions and error cases:

1. **Empty Data Tests**
   - App with no students
   - App with no lessons
   - Fresh install behavior
   - **Target:** 8 tests

2. **Large Dataset Tests**
   - 10k+ work items
   - 1000+ students
   - Performance degradation
   - **Target:** 5 tests

3. **Concurrent Access Tests**
   - Multiple view models
   - Race conditions
   - SwiftData thread safety
   - **Target:** 7 tests

### Task 5.6.2: Documentation & CI Setup (2 days)

1. **Test Documentation**
   - Running tests guide
   - Writing new tests guide
   - Performance baseline documentation

2. **CI Integration**
   - GitHub Actions workflow
   - Performance regression alerts
   - Coverage reporting

**Deliverables:**
- `Tests/EdgeCases/EmptyDataTests.swift` (8 tests)
- `Tests/EdgeCases/LargeDatasetTests.swift` (5 tests)
- `Tests/EdgeCases/ConcurrentAccessTests.swift` (7 tests)
- `TESTING.md` - Comprehensive testing guide
- `.github/workflows/tests.yml` - CI configuration

**Total Week 6:** 20 new tests + documentation

---

## Phase 5 Summary

### Deliverables

**New Test Files:** 25+ test files
**New Tests:** 277+ tests (bringing total from 2080 to ~2350+)
**Benchmarks:** 16 performance benchmarks
**Documentation:** TESTING.md comprehensive guide

### Coverage Targets

| Layer | Current | Target | Priority |
|-------|---------|--------|----------|
| Models | ~60% | ~60% | ✅ Sufficient |
| Services | ~20% | ~80% | 🔴 Critical |
| ViewModels | ~10% | ~70% | 🔴 Critical |
| Integration | 0% | New | 🔴 Critical |
| Performance | New | Baseline | 🟡 Medium |

### Success Metrics

✅ **Build passes:** All tests green
✅ **Performance:** Baselines documented
✅ **Coverage:** 80%+ on critical services
✅ **Integration:** 5 major flows tested
✅ **CI:** Automated test runs on PR

### Benefits for Later Phases

**Phase 2 (CloudKitUUID):**
- Migration tests catch UUID conversion bugs
- Integration tests verify no UI breakage

**Phase 3 (Data Model):**
- Service tests catch breaking changes
- Integration tests verify user flows still work

**Phase 4 (Dependency Injection):**
- Service tests verify DI refactoring correctness
- Performance tests catch overhead issues

**Phase 6 (Backup):**
- Backup integrity tests already built
- GenericBackupCodec fully tested

**Phase 8 (Migrations):**
- Migration framework fully tested
- Rollback capability verified

---

## Getting Started

### Immediate Next Steps

1. **Create test structure:**
   ```bash
   mkdir -p "Maria's Notebook/Tests/Services"
   mkdir -p "Maria's Notebook/Tests/ViewModels"
   mkdir -p "Maria's Notebook/Tests/Integration"
   mkdir -p "Maria's Notebook/Tests/Migrations"
   mkdir -p "Maria's Notebook/Tests/EdgeCases"
   ```

2. **Start with Week 1, Task 5.1.1:**
   - Create `LifecycleServiceTests.swift`
   - Write first test: "Record presentation creates work items"
   - Build infrastructure for service testing

3. **Use AppDependencies.makeTest():**
   ```swift
   let deps = AppDependencies.makeTest()
   let context = deps.modelContext
   // In-memory context, no side effects
   ```

4. **Follow existing patterns:**
   - Look at existing tests in `Tests/` directory
   - Use Swift Testing framework (@Test, @Suite)
   - Use #expect() for assertions

---

## Risk Mitigation

**Risk:** Tests take too long to write
**Mitigation:** Start with critical paths only, expand coverage iteratively

**Risk:** Tests are flaky
**Mitigation:** Use in-memory contexts, avoid time-dependent assertions

**Risk:** Performance tests vary too much
**Mitigation:** Generous thresholds (2-3x target), focus on major regressions only

**Risk:** Integration tests break during refactoring
**Mitigation:** Expected! They're catching issues - fix and update tests

---

**Phase 5 Status:** 🟢 Ready to Start
**Next Action:** Create Week 1 test files
**Timeline:** 6 weeks (February - March 2026)
**Success:** Safety net in place for risky phases 2, 3, 6, 8
