# Maria's Notebook - Option A Aggressive Refactoring Plan

**Start Date:** 2026-02-03
**Target Completion:** 2026-08-03 (6 months)
**Strategy:** Aggressive sequential execution with safety checkpoints

---

## 🔒 SAFETY & ROLLBACK PROCEDURES

### How to Revert to Pre-Refactor State

#### Option 1: Complete Rollback (safest)
```bash
# Return to the exact state before refactoring started
git checkout pre-refactor-snapshot
git checkout -b recovery-branch
```

#### Option 2: Rollback to Specific Phase
```bash
# Each phase has a checkpoint tag
git tag --list "phase-*-complete"
git checkout phase-1-complete  # or phase-2-complete, etc.
git checkout -b recovery-from-phase-N
```

#### Option 3: Cherry-pick Specific Features
```bash
# If you want to keep some refactoring but revert others
git checkout Main
git cherry-pick <commit-hash>  # Pick specific improvements
```

### Branch Strategy

- `Main` - Production-ready code (never breaks)
- `refactor/phase-N-foundation` - Active development branch
- `phase-N-complete` - Git tags for each completed phase
- `pre-refactor-snapshot` - Emergency rollback point

### Testing Requirements Before Merging to Main

- [ ] All unit tests pass
- [ ] Integration tests pass
- [ ] Manual smoke test of critical paths
- [ ] Performance benchmarks meet thresholds
- [ ] Backup/restore round-trip test succeeds

---

## PHASE 1: Foundation Fixes (Weeks 1-3)

**Branch:** `refactor/phase-1-foundation`
**Goal:** Low-risk improvements with immediate impact

### Tasks

#### 1.1 Create @RawCodable Property Wrapper (3 days)
**Files:** New `PropertyWrappers.swift`, refactor 20 model files

**Current Pattern (80+ instances):**
```swift
// WorkModel.swift - BEFORE
private var statusRaw: String = WorkStatus.active.rawValue
var status: WorkStatus {
    get { WorkStatus(rawValue: statusRaw) ?? .active }
    set { statusRaw = newValue.rawValue }
}
```

**New Pattern:**
```swift
// PropertyWrappers.swift - NEW
@propertyWrapper
struct RawCodable<T: RawRepresentable> where T.RawValue == String {
    private var storage: String
    private let defaultValue: T

    var wrappedValue: T {
        get { T(rawValue: storage) ?? defaultValue }
        set { storage = newValue.rawValue }
    }

    init(wrappedValue: T) {
        self.defaultValue = wrappedValue
        self.storage = wrappedValue.rawValue
    }
}

// WorkModel.swift - AFTER
@RawCodable var status: WorkStatus = .active
// Reduces 80+ properties × 3 lines = 240+ lines eliminated
```

**Models to Refactor:**
1. WorkModel (statusRaw, kindRaw, completionOutcomeRaw)
2. Note (categoryRaw, sourceContextTypeRaw)
3. LessonAssignment (stateRaw)
4. AttendanceRecord (statusRaw)
5. Student (gradeRaw)
6. Lesson (subjectRaw)
7. ProjectSession (statusRaw)
8. Track (levelRaw)
9. WorkStep (statusRaw)
10. StudentMeeting (purposeRaw)
11. CommunityTopic (statusRaw)
12. Reminder (priorityRaw)
13. WorkPlanItem (statusRaw)
14. StudentTrackEnrollment (statusRaw)
15. SchoolDayOverride (typeRaw)
16. Document (typeRaw)
17. Supply (categoryRaw)
18. Procedure (categoryRaw)
19. ContractRelatedProcedure (roleRaw)
20. ScheduleSlot (periodRaw)

**Testing:**
- [ ] Unit tests for @RawCodable wrapper
- [ ] Verify default fallback behavior
- [ ] Backup/restore round-trip test
- [ ] SwiftData persistence test

---

#### 1.2 Document Service Dependencies (2 days)
**Files:** New `Services/SERVICE_REGISTRY.md`

Create comprehensive service documentation:
- List all 118 services
- Document dependencies between services
- Create visual dependency graph
- Identify circular dependencies
- Prioritize services for Phase 4 DI refactor

**No code changes - documentation only**

---

#### 1.3 Remove Legacy Migration Fields (2 days)
**Files:** 10 model files

Remove completed migration tracking fields:

```swift
// WorkModel.swift - REMOVE
var legacyContractID: UUID?  // DELETE
var legacyStudentLessonID: String?  // DELETE

// LessonAssignment.swift - REMOVE
var migratedFromStudentLessonID: String?  // DELETE
var migratedFromPresentationID: String?  // DELETE

// Student.swift - REMOVE
var legacyImportID: String?  // DELETE (if exists)
```

**Safety Check:**
- Query database for any non-nil values before removal
- If found, run final cleanup migration first
- Add deprecation warning to backup/restore

---

#### 1.4 Consolidate Presentation/LessonAssignment Naming (3 days)
**Files:** AppSchema, LifecycleService, 15 view files

**Current State:**
```swift
// AppSchema.swift
typealias Presentation = LessonAssignment  // Confusing!
```

**Decision:** Choose ONE canonical name
- **Option A:** Rename class to `Presentation` (simpler domain term)
- **Option B:** Keep `LessonAssignment`, remove typealias (technical accuracy)

**Recommendation:** Option A (Presentation)

```swift
// After refactor:
@Model
final class Presentation {
    // All references updated throughout codebase
}
```

**Files to Update:**
- AppSchema.swift
- LifecycleService.swift
- PresentationsViewModel.swift
- QuickNewPresentationSheet.swift
- All view files referencing LessonAssignment

---

#### 1.5 Add Missing Unit Tests (4 days)
**Files:** New test files

Create tests for critical untested services:

1. **WorkLifecycleServiceTests.swift**
   - Test all state transitions
   - Test invalid transitions
   - Test side effects (reminders, notifications)

2. **GroupTrackServiceTests.swift**
   - Test progress calculations
   - Test student enrollment edge cases
   - Test circular dependency with LifecycleService

3. **DataCleanupServiceTests.swift**
   - Test orphan detection
   - Test deduplication logic
   - Test edge cases (missing IDs, null relationships)

4. **ReminderSyncServiceTests.swift**
   - Test EventKit sync
   - Test conflict resolution
   - Mock EventStore usage

5. **BackupServiceIntegrationTests.swift**
   - Test all entity types included
   - Test encryption/decryption
   - Test version compatibility

**Target:** 50+ new tests, focus on critical paths

---

### Phase 1 Checkpoint

**Before Merging to Main:**
- [ ] All new tests passing
- [ ] No regressions in existing tests
- [ ] Manual testing of Today view, Work management, Backup/Restore
- [ ] Performance benchmark: startup time < 2s
- [ ] Git tag: `phase-1-complete`

**Rollback Plan:**
```bash
git checkout pre-refactor-snapshot
```

---

## PHASE 2: Type Safety Improvements (Weeks 4-7)

**Branch:** `refactor/phase-2-type-safety`
**Goal:** Eliminate string ID anti-pattern

⚠️ **HIGH RISK PHASE** - Extensive testing required

### Tasks

#### 2.1 Create CloudKitUUID Property Wrapper (2 days)
**Files:** New `CloudKitUUID.swift`

```swift
import Foundation
import SwiftData

@propertyWrapper
struct CloudKitUUID: Codable, Hashable {
    private var storage: String

    var wrappedValue: UUID {
        get { UUID(uuidString: storage) ?? UUID() }
        set { storage = newValue.uuidString }
    }

    init(wrappedValue: UUID) {
        self.storage = wrappedValue.uuidString
    }

    // For SwiftData persistence
    var projectedValue: String {
        get { storage }
        set { storage = newValue }
    }
}

// Usage:
@Model
final class WorkModel {
    @CloudKitUUID var studentID: UUID = UUID()  // Type-safe!
    // SwiftData stores as String, code uses UUID
}
```

**Features:**
- Automatic UUID ↔ String conversion
- SwiftData compatible (stores as String)
- Type-safe access
- Invalid string → generates new UUID (safe default)

---

#### 2.2 Migrate WorkModel to CloudKitUUID (5 days)
**Files:** WorkModel.swift, WorkCompletionService, WorkStepService, LifecycleService

**Before:**
```swift
var studentID: String = ""
var lessonID: String = ""
var presentationID: String? = nil
```

**After:**
```swift
@CloudKitUUID var studentID: UUID = UUID()
@CloudKitUUID var lessonID: UUID = UUID()
@CloudKitUUID var presentationID: UUID? = nil
```

**Migration Required:**
```swift
// Add to DataMigrations
static func migrateWorkModelToTypedIDs(context: ModelContext) throws {
    let descriptor = FetchDescriptor<WorkModel>()
    let allWork = try context.fetch(descriptor)

    for work in allWork {
        // CloudKitUUID handles conversion automatically
        // No manual migration needed if property wrapper correct
    }

    MigrationFlag.set(.workModelTypedIDs, in: context)
}
```

**Testing:**
- [ ] Query performance benchmark (before/after)
- [ ] Backup/restore with mixed old/new data
- [ ] Student lookup accuracy
- [ ] Relationship integrity

---

#### 2.3 Migrate Note, StudentLesson to CloudKitUUID (5 days)
**Files:** Note.swift, StudentLesson.swift, 12 related files

Apply same pattern to:
- Note (searchIndexStudentID, lessonID, workID, etc.)
- StudentLesson (lessonID, _studentIDsData array)
- LessonAssignment/Presentation (studentIDs array)
- AttendanceRecord (studentID)
- WorkParticipantEntity (studentID)
- ProjectRole (studentID)
- StudentMeeting (studentID)

**Complexity:** StudentLesson._studentIDsData
```swift
// Before: JSON-encoded [String]
@Attribute(.externalStorage) var _studentIDsData: Data

// After: Still store as [String], but expose as [UUID]
var studentIDs: [UUID] {
    get {
        (try? JSONDecoder().decode([String].self, from: _studentIDsData))
            .compactMap { UUID(uuidString: $0) } ?? []
    }
    set {
        _studentIDsData = (try? JSONEncoder().encode(newValue.map(\.uuidString))) ?? Data()
    }
}
```

---

#### 2.4 Add Integration Tests for UUID Conversions (3 days)
**Files:** UUIDConversionTests.swift, ModelRoundTripTests.swift

Test suite:
1. UUID ↔ String round-trip
2. Query performance (string vs UUID)
3. Relationship lookup accuracy
4. Backup compatibility with old data
5. CloudKit sync (if enabled)
6. Invalid UUID handling

**Performance Targets:**
- Query time: < 100ms (no degradation)
- Conversion overhead: < 1ms per 1000 entities

---

#### 2.5 Replace String ID Queries with Relationship Queries (6 days)
**Files:** LifecycleService, GroupTrackService, WorkCompletionService, 20+ files

**Before:**
```swift
// Manual string ID lookup
let students = try context.fetch(FetchDescriptor<Student>())
let matchingStudent = students.first { $0.id.uuidString == work.studentID }
```

**After:**
```swift
// Direct relationship (Phase 3 preparation)
let student = work.student  // Type-safe, optimized by SwiftData
```

**Interim Approach (Phase 2):**
```swift
// Use typed UUID for queries
let predicate = #Predicate<Student> {
    $0.id == work.studentID  // Now both are UUID type
}
```

---

### Phase 2 Checkpoint

**Critical Testing:**
- [ ] Full test suite passes
- [ ] Performance benchmarks meet targets
- [ ] Backup/restore with pre-Phase-2 data
- [ ] Manual testing: Student detail, Work tracking, Attendance
- [ ] Git tag: `phase-2-complete`

**Rollback Plan:**
```bash
git checkout phase-1-complete
# Or keep Phase 2 but feature-flag it:
UserDefaults.useTypedUUIDs = false
```

---

## PHASE 3: Data Model Refactoring (Weeks 8-11)

**Branch:** `refactor/phase-3-data-model`
**Goal:** Fix Note polymorphism, remove denormalized fields

⚠️ **HIGH RISK PHASE** - Requires data migration

### Tasks

#### 3.1 Split Note Model into Domain-Specific Types (8 days)

**Current Problem:**
```swift
@Model final class Note {
    @Relationship var lesson: Lesson?
    @Relationship var work: WorkModel?
    @Relationship var studentLesson: StudentLesson?
    // ... 12 total optional relationships

    var attachedTo: String {
        if lesson != nil { return "lesson" }
        if work != nil { return "work" }
        // ... 12 if statements
    }
}
```

**New Approach:**
```swift
// Base protocol
protocol NoteProtocol {
    var id: UUID { get }
    var content: String { get }
    var createdAt: Date { get }
    var authorID: UUID? { get }
}

// Domain-specific types
@Model final class LessonNote: NoteProtocol {
    @Relationship var lesson: Lesson  // Required, not optional
}

@Model final class WorkNote: NoteProtocol {
    @Relationship var work: WorkModel
    var checkInID: UUID?  // Optional: if attached to WorkCheckIn
}

@Model final class AttendanceNote: NoteProtocol {
    @Relationship var attendance: AttendanceRecord
}

@Model final class PresentationNote: NoteProtocol {
    @Relationship var presentation: Presentation
}

@Model final class ProjectNote: NoteProtocol {
    @Relationship var projectSession: ProjectSession
}

@Model final class StudentNote: NoteProtocol {
    @Relationship var student: Student
    var meetingID: UUID?  // Optional: if part of StudentMeeting
}

@Model final class GeneralNote: NoteProtocol {
    // No required relationship - standalone note
    var scope: NoteScope
}
```

**Benefits:**
- Type safety (can't attach WorkNote to Lesson)
- Single required relationship (not 12 optional)
- Query optimization (no multi-join needed)
- Clear intent (LessonNote vs WorkNote)

**Migration Challenge:** 3.2 (next task)

---

#### 3.2 Create Migration for Note Split (4 days)

```swift
@MainActor
struct NoteSplitMigration {
    static func execute(context: ModelContext) throws {
        let allNotes = try context.fetch(FetchDescriptor<Note>())

        for note in allNotes {
            let newNote: any NoteProtocol

            switch note.attachedTo {
            case "lesson":
                newNote = LessonNote(
                    content: note.content,
                    lesson: note.lesson!
                )
            case "work":
                newNote = WorkNote(
                    content: note.content,
                    work: note.work!
                )
            case "attendance":
                newNote = AttendanceNote(
                    content: note.content,
                    attendance: note.attendanceRecord!
                )
            // ... handle all 12 types
            default:
                newNote = GeneralNote(
                    content: note.content,
                    scope: note.scope
                )
            }

            context.insert(newNote)
        }

        // Keep old Note model for 2 releases (dual-write period)
        // Mark as @available(*, deprecated)

        MigrationFlag.set(.noteSplit, in: context)
    }
}
```

**Safety Strategy:**
- Dual-write period: Write to both old Note + new types for 2 releases
- Validation queries: Verify all notes migrated correctly
- Rollback data: Keep old Note table for 6 months

---

#### 3.3 Remove Denormalized Fields (5 days)

**Fields to Remove:**
```swift
// StudentLesson
var scheduledForDay: Date  // DELETE - compute from scheduledFor

// LessonAssignment/Presentation
var studentGroupKeyPersisted: String  // DELETE - compute on demand

// Note (after split)
var scopeIsAll: Bool  // DELETE - check scope enum
var searchIndexStudentID: UUID?  // DELETE - use relationship
```

**Replacement Strategy:**
```swift
// Before: Denormalized field + manual sync
var scheduledFor: Date? {
    didSet {
        if let date = scheduledFor {
            scheduledForDay = Calendar.current.startOfDay(for: date)
        }
    }
}

// After: Computed property
var scheduledForDay: Date? {
    scheduledFor.map { Calendar.current.startOfDay(for: $0) }
}
```

**Query Optimization:**
```swift
// If queries are too slow, add SwiftData index
@Attribute(.indexed) var scheduledFor: Date?
```

**Testing:**
- [ ] Query performance regression test
- [ ] Verify no nil scheduledForDay bugs
- [ ] Backup compatibility

---

#### 3.4 Add Query Performance Tests (4 days)

Create performance benchmark suite:

```swift
@MainActor
struct QueryPerformanceTests {
    func testFetchTodaysLessons() async throws {
        let context = makeContext()
        seedData(context, studentLessons: 1000)

        let start = Date()
        let today = Calendar.current.startOfDay(for: .now)

        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate {
                $0.scheduledFor >= today && $0.scheduledFor < today.addingTimeInterval(86400)
            }
        )

        let lessons = try context.fetch(descriptor)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.1, "Query must complete in < 100ms")
        XCTAssertGreaterThan(lessons.count, 0)
    }

    func testWorkStudentLookup() async throws {
        // Test relationship lookup performance
    }
}
```

**Benchmarks:**
- Today view query: < 100ms for 1000 lessons
- Student detail query: < 50ms
- Work list query: < 150ms for 500 work items
- Attendance grid: < 200ms for 30 students × 180 days

---

#### 3.5 Reorganize Models/ Directory (2 days)

**Current:** Flat directory with 48 model files

**New Structure:**
```
Models/
├── Students/
│   ├── Student.swift
│   ├── StudentLesson.swift
│   ├── StudentMeeting.swift
│   └── StudentTrackEnrollment.swift
├── Lessons/
│   ├── Lesson.swift
│   ├── Presentation.swift (formerly LessonAssignment)
│   ├── Procedure.swift
│   └── LessonNote.swift
├── Work/
│   ├── WorkModel.swift
│   ├── WorkStep.swift
│   ├── WorkCheckIn.swift
│   ├── WorkCompletionRecord.swift
│   ├── WorkParticipantEntity.swift
│   ├── WorkPlanItem.swift
│   └── WorkNote.swift
├── Attendance/
│   ├── AttendanceRecord.swift
│   └── AttendanceNote.swift
├── Projects/
│   ├── Project.swift
│   ├── ProjectSession.swift
│   ├── ProjectRole.swift
│   └── ProjectNote.swift
├── Curriculum/
│   ├── Track.swift
│   ├── TrackStep.swift
│   └── GroupTrack.swift
├── Schedule/
│   ├── Schedule.swift
│   ├── ScheduleSlot.swift
│   └── SchoolDayOverride.swift
├── Notes/
│   ├── NoteProtocol.swift
│   ├── GeneralNote.swift
│   └── StudentNote.swift
└── Core/
    ├── Document.swift
    ├── Supply.swift
    ├── Reminder.swift
    └── CommunityTopic.swift
```

**Benefits:**
- Clear feature boundaries
- Easier navigation
- Logical grouping
- Scalable structure

**Xcode Project Update:**
- Create groups matching directory structure
- Update imports (absolute paths)
- Verify build succeeds

---

### Phase 3 Checkpoint

**Critical Validations:**
- [ ] All tests pass
- [ ] Performance benchmarks meet targets
- [ ] Note migration 100% successful (validation query)
- [ ] Backup/restore round-trip with pre-Phase-3 data
- [ ] Manual testing: All major features
- [ ] Git tag: `phase-3-complete`

**Rollback Plan:**
```bash
git checkout phase-2-complete
# Or restore from backup created before Phase 3
```

---

## PHASE 4: Service Layer Modernization (Weeks 12-15)

**Branch:** `refactor/phase-4-services`
**Goal:** Dependency injection, remove singletons

### Tasks

#### 4.1 Create AppDependencies Container (3 days)

```swift
import SwiftUI
import SwiftData

@MainActor
final class AppDependencies: ObservableObject {
    let modelContext: ModelContext

    // Lazy services
    private(set) lazy var workLifecycle: WorkLifecycleService =
        WorkLifecycleServiceImpl(context: modelContext)

    private(set) lazy var reminderSync: ReminderSyncService =
        ReminderSyncServiceImpl(context: modelContext)

    private(set) lazy var groupTrack: GroupTrackService =
        GroupTrackServiceImpl(
            context: modelContext,
            lifecycleService: workLifecycle
        )

    private(set) lazy var workCompletion: WorkCompletionService =
        WorkCompletionServiceImpl(
            context: modelContext,
            lifecycleService: workLifecycle
        )

    // Add all 118 services...

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // For testing
    static var preview: AppDependencies {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: AppSchema.self, configurations: [config])
        return AppDependencies(modelContext: container.mainContext)
    }
}

// Environment key
struct AppDependenciesKey: EnvironmentKey {
    static let defaultValue = AppDependencies.preview
}

extension EnvironmentValues {
    var dependencies: AppDependencies {
        get { self[AppDependenciesKey.self] }
        set { self[AppDependenciesKey.self] = newValue }
    }
}
```

**Usage:**
```swift
@main
struct MariasNotebookApp: App {
    let container: ModelContainer
    let dependencies: AppDependencies

    init() {
        container = try! ModelContainer(for: AppSchema.self)
        dependencies = AppDependencies(modelContext: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(dependencies)
        }
    }
}
```

---

#### 4.2 Refactor ViewModels to Use DI (8 days)

**Before:**
```swift
@MainActor
final class TodayViewModel: ObservableObject {
    @Published var todaysLessons: [StudentLesson] = []

    func loadData() {
        // Directly accesses ModelContext from environment
        // Creates services inline
    }
}

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
}
```

**After:**
```swift
@MainActor
final class TodayViewModel: ObservableObject {
    private let dependencies: AppDependencies
    @Published var todaysLessons: [StudentLesson] = []

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func loadData() {
        // Use injected services
        dependencies.reminderSync.sync()
    }
}

struct TodayView: View {
    @Environment(\.dependencies) private var dependencies
    @StateObject private var viewModel: TodayViewModel

    init() {
        // Inject dependencies via initializer
        _viewModel = StateObject(wrappedValue: TodayViewModel(dependencies: .preview))
    }
}
```

**ViewModels to Refactor:**
1. TodayViewModel
2. InboxSheetViewModel
3. StudentDetailViewModel
4. WorkDetailViewModel
5. AttendanceViewModel
6. PresentationsViewModel
7. ProjectDetailViewModel
8. LessonsViewModel
9. StudentsViewModel
10. PlanningViewModel
11. SettingsViewModel
12. BackupViewModel
13. TopicDetailViewModel
14. ClassSubjectChecklistViewModel
15. GiveLessonViewModel
16. StudentLessonDetailViewModel
17. ScheduleViewModel

---

#### 4.3 Remove Singleton Services (6 days)

**Singletons to Remove:**
```swift
// Before
ReminderSyncService.shared
AppRouter.shared
AppBootstrapper.shared
DatabaseErrorCoordinator.shared
```

**After:**
```swift
// AppDependencies provides instances
dependencies.reminderSync  // Not .shared
dependencies.appRouter
dependencies.appBootstrapper
dependencies.databaseErrorCoordinator
```

**Migration Strategy:**
1. Add service to AppDependencies
2. Update all call sites to use dependencies
3. Mark .shared as @available(*, deprecated)
4. Remove .shared after 1 release

**High-Risk Services:**
- AppRouter (used in 50+ places)
- ReminderSyncService (EventKit integration)
- AppBootstrapper (app startup critical)

**Testing:**
- [ ] Each service works with DI
- [ ] No singleton references remain
- [ ] App startup succeeds
- [ ] Navigation works

---

#### 4.4 Extract TodayViewModel Sub-Services to Protocols (4 days)

**Current:**
```swift
@MainActor
final class TodayViewModel: ObservableObject {
    // 80+ properties
    // 20+ methods
    // 6 nested service types
}
```

**After:**
```swift
protocol TodayDataFetching {
    func fetchLessons(for date: Date) async throws -> [StudentLesson]
}

protocol TodayScheduleBuilding {
    func buildSchedule(from lessons: [StudentLesson]) -> [ScheduledWorkItem]
}

@MainActor
final class TodayViewModel: ObservableObject {
    private let dataFetcher: TodayDataFetching
    private let scheduleBuilder: TodayScheduleBuilding

    init(
        dataFetcher: TodayDataFetching,
        scheduleBuilder: TodayScheduleBuilding
    ) {
        self.dataFetcher = dataFetcher
        self.scheduleBuilder = scheduleBuilder
    }

    @Published var lessons: [StudentLesson] = []

    func reload() async {
        lessons = try await dataFetcher.fetchLessons(for: date)
    }
}
```

**Benefits:**
- Testable (mock protocols)
- Single responsibility
- Clearer dependencies
- Reusable components

---

#### 4.5 Create Service Factory Functions (2 days)

```swift
enum ServiceFactory {
    @MainActor
    static func makeWorkLifecycleService(
        context: ModelContext
    ) -> WorkLifecycleService {
        WorkLifecycleServiceImpl(context: context)
    }

    @MainActor
    static func makeAppDependencies(
        context: ModelContext
    ) -> AppDependencies {
        AppDependencies(modelContext: context)
    }

    // Testing variants
    @MainActor
    static func makeTestDependencies() -> AppDependencies {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: AppSchema.self, configurations: [config])
        return AppDependencies(modelContext: container.mainContext)
    }
}
```

---

### Phase 4 Checkpoint

**Validations:**
- [ ] All tests pass
- [ ] No singleton references (grep for ".shared")
- [ ] App startup time < 2s
- [ ] Navigation works correctly
- [ ] Memory usage stable (no leaks from DI)
- [ ] Git tag: `phase-4-complete`

**Rollback Plan:**
```bash
git checkout phase-3-complete
```

---

## PHASE 5: Testing & Quality (Weeks 16-22)

**Branch:** `refactor/phase-5-testing`
**Goal:** Achieve 50%+ test coverage

**Runs concurrently with Phases 2-4 to catch regressions early**

### Tasks

#### 5.1 Add Snapshot Tests for Key Views (10 days)

Install SnapshotTesting:
```swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.15.0")
]
```

**30 Views to Test:**
1. TodayView (3 states: empty, populated, loading)
2. StudentDetailView
3. StudentLessonDetailView
4. WorkDetailView
5. WorkListView
6. AttendanceGrid
7. AttendanceCard
8. LessonDetailView
9. LessonListView
10. PresentationDetailView
11. ProjectDetailView
12. ProjectSessionDetailView
13. InboxSheet
14. ScheduleView
15. CalendarMonthGridView
16. WeekGrid
17. BackupStatusView
18. RestorePreviewView
19. SettingsView (5 tabs)
20. NoteEditSheet
21. QuickNewWorkItemSheet
22. QuickNewPresentationSheet
23. StudentChipsList
24. LessonSection
25. RootSidebar
26. MainToolbar
27. PieMenu
28. AttendanceExpandedView
29. TopicDetailView
30. ProceduresListView

**Example:**
```swift
import SnapshotTesting

@MainActor
final class TodayViewSnapshotTests: XCTestCase {
    func testTodayViewEmpty() {
        let view = TodayView()
            .environment(\.dependencies, .makeTest())

        assertSnapshot(matching: view, as: .image)
    }

    func testTodayViewWithLessons() {
        let deps = AppDependencies.makeTest()
        seedLessons(in: deps.modelContext, count: 5)

        let view = TodayView()
            .environment(\.dependencies, deps)

        assertSnapshot(matching: view, as: .image)
    }
}
```

---

#### 5.2 Add Error Condition Tests (6 days)

**Services to Test:**
1. DataCleanupService (orphan detection edge cases)
2. MigrationService (corrupt data handling)
3. BackupService (encryption failures, disk full)
4. ReminderSyncService (EventKit permission denied)
5. WorkLifecycleService (invalid state transitions)
6. GroupTrackService (circular dependencies)
7. RelationshipBackfillService (missing relationships)
8. SelectiveRestoreService (partial restore failures)
9. ConflictResolutionService (merge conflicts)
10. DatabaseInitializationService (schema mismatch)

**Example:**
```swift
final class DataCleanupServiceErrorTests: XCTestCase {
    @MainActor
    func testOrphanDetectionWithNilIDs() throws {
        let context = makeTestContext()

        // Create work with empty studentID
        let work = WorkModel()
        work.studentID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        context.insert(work)

        let orphans = try DataCleanupService.findOrphanedWork(in: context)
        XCTAssertEqual(orphans.count, 1)
    }

    @MainActor
    func testDeduplicationWithIdenticalUUIDs() throws {
        // Test merge logic when CloudKit creates duplicates
    }
}
```

---

#### 5.3 Add Performance Benchmarks (4 days)

```swift
import XCTest

final class PerformanceBenchmarks: XCTestCase {
    @MainActor
    func testAppStartupTime() {
        measure {
            let container = try! ModelContainer(for: AppSchema.self)
            let deps = AppDependencies(modelContext: container.mainContext)
            _ = deps.appBootstrapper.runStartupMigrations()
        }

        // Target: < 2 seconds
    }

    @MainActor
    func testTodayViewLoadTime() {
        let context = makeTestContext()
        seedData(context, lessons: 1000)

        measure {
            let viewModel = TodayViewModel(dependencies: .makeTest(context: context))
            viewModel.reload()
        }

        // Target: < 100ms
    }

    @MainActor
    func testBackupExportTime() {
        let context = makeTestContext()
        seedFullDatabase(context)

        measure {
            try! BackupService.exportBackup(
                modelContext: context,
                to: tempURL
            )
        }

        // Target: < 10 seconds for 10k entities
    }
}
```

**Benchmarks:**
- App startup: < 2s
- Today view: < 100ms
- Work list: < 150ms
- Attendance grid: < 200ms
- Backup export: < 10s
- Backup restore: < 15s
- Migration (fresh): < 5s

---

#### 5.4 Increase Unit Test Coverage to 50% (12 days)

**Current Coverage:** ~15% (95 test files / 635 source files)

**Target:** 50% (320 test files or 50% line coverage)

**Priority Areas:**
1. **Core Services** (100% coverage)
   - WorkLifecycleService
   - GroupTrackService
   - DataCleanupService
   - BackupService
   - ReminderSyncService

2. **Data Models** (80% coverage)
   - Test all computed properties
   - Test relationship integrity
   - Test validation logic

3. **ViewModels** (70% coverage)
   - Test state transitions
   - Test error handling
   - Test cache invalidation

4. **Utilities** (60% coverage)
   - AgeUtils
   - CSVUtils
   - Date extensions
   - Color utilities

**Tools:**
```bash
# Generate coverage report
xcodebuild test -scheme "Maria's Notebook" \
    -enableCodeCoverage YES \
    -resultBundlePath TestResults.xcresult

xcrun xccov view --report TestResults.xcresult
```

---

#### 5.5 Add UI Automation Tests (8 days)

Create UITests target with critical flows:

1. **Student Management Flow**
   - Create student
   - Edit student details
   - Archive student
   - Restore student

2. **Lesson Planning Flow**
   - Create lesson
   - Schedule lesson for student
   - Give lesson (mark as presented)
   - Generate work from lesson

3. **Work Tracking Flow**
   - Create work item
   - Add work step
   - Record check-in
   - Mark work complete

4. **Attendance Flow**
   - Open attendance grid
   - Mark students present/absent
   - Add attendance note
   - Send attendance email

5. **Backup/Restore Flow**
   - Create backup
   - Verify backup file
   - Restore from backup
   - Verify data integrity

**Example:**
```swift
final class StudentManagementUITests: XCTestCase {
    func testCreateStudent() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Students"].tap()
        app.buttons["Add Student"].tap()

        let firstNameField = app.textFields["First Name"]
        firstNameField.tap()
        firstNameField.typeText("John")

        let lastNameField = app.textFields["Last Name"]
        lastNameField.tap()
        lastNameField.typeText("Doe")

        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["John Doe"].exists)
    }
}
```

---

### Phase 5 Checkpoint

**Coverage Targets:**
- [ ] Line coverage: 50%+
- [ ] Function coverage: 60%+
- [ ] Branch coverage: 40%+
- [ ] 30 snapshot tests passing
- [ ] 10 UI automation tests passing
- [ ] Git tag: `phase-5-complete`

---

## PHASE 6: Backup System Refactor (Weeks 23-26)

**Branch:** `refactor/phase-6-backup`
**Goal:** Generic protocol-based backup

⚠️ **HIGH RISK** - Affects data safety

### Tasks

#### 6.1 Create BackupEncodable Protocol (2 days)

```swift
protocol BackupEncodable: Codable {
    static var entityName: String { get }
    var backupVersion: Int { get }
}

extension BackupEncodable {
    var backupVersion: Int { 1 }
}

// Models conform automatically
extension Student: BackupEncodable {
    static var entityName: String { "Student" }
}

extension WorkModel: BackupEncodable {
    static var entityName: String { "WorkModel" }
}

// ... all 48 models
```

---

#### 6.2 Implement Generic Backup Codec (5 days)

**Before:** 25 parallel DTO types

**After:** Generic encoding

```swift
struct BackupContainer: Codable {
    var version: Int = 1
    var createdAt: Date
    var entities: [String: [Data]]  // entityName -> [encoded entities]

    mutating func add<T: BackupEncodable>(_ entities: [T]) throws {
        let data = try entities.map { try JSONEncoder().encode($0) }
        self.entities[T.entityName] = data
    }

    func decode<T: BackupEncodable>(_ type: T.Type) throws -> [T] {
        guard let data = entities[T.entityName] else { return [] }
        return try data.map { try JSONDecoder().decode(T.self, from: $0) }
    }
}

struct GenericBackupService {
    static func exportBackup(context: ModelContext) throws -> BackupContainer {
        var container = BackupContainer(createdAt: .now, entities: [:])

        // Automatically discover all BackupEncodable types
        for modelType in AppSchema.models {
            if let backupType = modelType as? BackupEncodable.Type {
                let entities = try fetchAll(backupType, in: context)
                try container.add(entities)
            }
        }

        return container
    }
}
```

**Benefits:**
- No parallel DTO types
- Automatic entity discovery
- Type-safe decode
- Easy to add new models

---

#### 6.3 Remove Parallel DTO Hierarchies (6 days)

**Delete 25 DTO files:**
- StudentDTO.swift
- LessonDTO.swift
- WorkModelDTO.swift
- BackupDTOTransformers.swift
- (22 more...)

**Update:**
- BackupService.swift (use generic codec)
- BackupEntityImporter.swift (use generic decode)
- RestoreCoordinator.swift (type-safe restore)
- BackupPreviewAnalyzer.swift (generic preview)

**Migration:**
```swift
// Support old backup format for 2 releases
enum BackupFormat {
    case legacy(LegacyBackupPayload)
    case modern(BackupContainer)
}

func detectFormat(_ data: Data) -> BackupFormat {
    if let legacy = try? JSONDecoder().decode(LegacyBackupPayload.self, from: data) {
        return .legacy(legacy)
    }
    return .modern(try JSONDecoder().decode(BackupContainer.self, from: data))
}
```

---

#### 6.4 Add Backup Version Compatibility (4 days)

```swift
struct BackupContainer: Codable {
    var version: Int
    var compatibleVersions: ClosedRange<Int>

    static let currentVersion = 2
    static let compatibleRange = 1...2

    func isCompatible() -> Bool {
        compatibleVersions.contains(Self.currentVersion)
    }
}

struct BackupMigrator {
    static func migrate(_ container: BackupContainer) throws -> BackupContainer {
        var migrated = container

        if container.version == 1 {
            // Migrate v1 -> v2
            migrated = try migrateV1ToV2(container)
        }

        return migrated
    }
}
```

---

#### 6.5 Add Backward Compatibility Tests (3 days)

```swift
final class BackupCompatibilityTests: XCTestCase {
    @MainActor
    func testRestoreV1Backup() throws {
        let v1Data = loadFixture("backup-v1.mariasnotebook")
        let container = try BackupService.loadBackup(from: v1Data)

        XCTAssertEqual(container.version, 1)
        XCTAssertTrue(container.isCompatible())

        let context = makeTestContext()
        try RestoreCoordinator.restore(container, to: context)

        // Verify all entities restored
        let students = try context.fetch(FetchDescriptor<Student>())
        XCTAssertGreaterThan(students.count, 0)
    }

    @MainActor
    func testRestoreV2Backup() throws {
        // Test modern format
    }

    @MainActor
    func testRejectIncompatibleBackup() throws {
        // Test future version rejection
    }
}
```

---

### Phase 6 Checkpoint

**Critical Tests:**
- [ ] Backup v1 (legacy) restore works
- [ ] Backup v2 (modern) export/restore works
- [ ] All 48 entity types included
- [ ] Encryption still works
- [ ] File size comparable to legacy format
- [ ] Git tag: `phase-6-complete`

**Rollback Plan:**
```bash
git checkout phase-5-complete
# Keep legacy backup code for 6 months
```

---

## PHASE 7: State Management Refinement (Weeks 27-29)

**Branch:** `refactor/phase-7-state`
**Goal:** Reactive state with Combine

### Tasks

#### 7.1 Introduce Combine Pipelines (6 days)

**Before:**
```swift
@Published var date: Date {
    didSet { scheduleReload() }
}
@Published var filter: LevelFilter {
    didSet { scheduleReload() }
}

private func scheduleReload() {
    reloadTask?.cancel()
    reloadTask = Task {
        try await Task.sleep(for: .milliseconds(300))
        reload()
    }
}
```

**After:**
```swift
import Combine

@Published var date: Date = .now
@Published var filter: LevelFilter = .all
@Published private(set) var lessons: [StudentLesson] = []

private var cancellables = Set<AnyCancellable>()

init() {
    Publishers.CombineLatest($date, $filter)
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] date, filter in
            self?.reload(date: date, filter: filter)
        }
        .store(in: &cancellables)
}
```

**Benefits:**
- Declarative reactive state
- Automatic debouncing
- Cancellation handled automatically
- Testable pipelines

**ViewModels to Update:**
- TodayViewModel (10+ published properties)
- InboxSheetViewModel
- StudentDetailViewModel
- AttendanceViewModel
- ScheduleViewModel

---

#### 7.2 Replace Manual Cache Invalidation (5 days)

**Before:**
```swift
var date: Date {
    didSet {
        cacheManager.invalidate()
        reload()
    }
}

var filter: LevelFilter {
    didSet {
        cacheManager.invalidate()
        reload()
    }
}
```

**After:**
```swift
let cacheInvalidationTrigger = PassthroughSubject<Void, Never>()

Publishers.Merge3(
    $date.dropFirst().map { _ in },
    $filter.dropFirst().map { _ in },
    cacheInvalidationTrigger
)
.sink { [weak self] in
    self?.cacheManager.invalidate()
}
.store(in: &cancellables)
```

---

#### 7.3 Centralize Cache Lifecycle (3 days)

```swift
@MainActor
final class CacheCoordinator: ObservableObject {
    private var caches: [String: any Caching] = [:]

    func register<C: Caching>(_ cache: C, key: String) {
        caches[key] = cache
    }

    func invalidate(key: String) {
        caches[key]?.invalidate()
    }

    func invalidateAll() {
        caches.values.forEach { $0.invalidate() }
    }
}

protocol Caching {
    func invalidate()
}
```

**Usage:**
```swift
// Register caches
coordinator.register(todayCacheManager, key: "today")
coordinator.register(schoolDayCache, key: "schoolDay")

// Invalidate on significant events
coordinator.invalidateAll()  // On date change
```

---

#### 7.4 Add Cache Performance Monitoring (2 days)

```swift
protocol CacheMetrics {
    var hitCount: Int { get }
    var missCount: Int { get }
    var hitRate: Double { get }
}

extension TodayCacheManager: CacheMetrics {
    var hitRate: Double {
        guard (hitCount + missCount) > 0 else { return 0 }
        return Double(hitCount) / Double(hitCount + missCount)
    }
}

// Monitoring
#if DEBUG
struct CacheMonitorView: View {
    @ObservedObject var coordinator: CacheCoordinator

    var body: some View {
        List {
            ForEach(coordinator.cacheMetrics) { metric in
                VStack(alignment: .leading) {
                    Text(metric.name)
                    Text("Hit rate: \(metric.hitRate)%")
                    Text("Hits: \(metric.hitCount) | Misses: \(metric.missCount)")
                }
            }
        }
    }
}
#endif
```

---

### Phase 7 Checkpoint

**Validations:**
- [ ] No manual cache invalidation remaining
- [ ] Combine pipelines working correctly
- [ ] Cache hit rates monitored
- [ ] Performance unchanged or improved
- [ ] Git tag: `phase-7-complete`

---

## PHASE 8: Migration Cleanup (Weeks 30-32)

**Branch:** `refactor/phase-8-migrations`
**Goal:** Remove completed migrations

⚠️ **HIGH RISK** - Could break upgrades

### Tasks

#### 8.1 Create Versioned Migration Registry (3 days)

```swift
struct MigrationRegistry {
    struct Migration {
        let version: Int
        let description: String
        let execute: (ModelContext) async throws -> Void
    }

    static let migrations: [Migration] = [
        Migration(
            version: 1,
            description: "UUID to String conversion",
            execute: SchemaMigrationService.migrateUUIDToString
        ),
        Migration(
            version: 2,
            description: "Note model extraction",
            execute: LegacyNotesMigrationService.migrateAllNotes
        ),
        Migration(
            version: 3,
            description: "Note split to domain types",
            execute: NoteSplitMigration.execute
        ),
        // Future migrations...
    ]

    @MainActor
    static func runPending(context: ModelContext) async throws {
        let current = UserDefaults.standard.integer(forKey: "MigrationVersion")

        for migration in migrations where migration.version > current {
            print("Running migration \(migration.version): \(migration.description)")
            try await migration.execute(context)
            UserDefaults.standard.set(migration.version, forKey: "MigrationVersion")
        }
    }
}
```

---

#### 8.2 Remove Completed One-Time Migrations (4 days)

**Delete migration services:**
- SchemaMigrationService (UUID→String, done in Phase 2)
- LegacyNotesMigrationService (Note extraction, done in Phase 3)
- RelationshipBackfillService (deprecated relationships removed)
- LessonAssignmentMigrationService (Presentation rename done)
- LessonAssignmentMigrationValidator (no longer needed)

**Keep:**
- DataCleanupService (ongoing orphan detection)
- MigrationDiagnosticService (debugging tool)

**Safety:**
```swift
// Set minimum compatible version
struct AppConstants {
    static let minimumCompatibleVersion = 3

    static func checkCompatibility() -> Bool {
        let current = UserDefaults.standard.integer(forKey: "MigrationVersion")
        return current >= minimumCompatibleVersion
    }
}
```

**User-facing:**
```swift
if !AppConstants.checkCompatibility() {
    // Show alert
    """
    This version of Maria's Notebook requires data from version 3.0 or later.
    Please restore from a recent backup or reinstall the previous version.
    """
}
```

---

#### 8.3 Add Migration Rollback Capability (5 days)

```swift
extension MigrationRegistry {
    struct Rollback {
        let fromVersion: Int
        let toVersion: Int
        let execute: (ModelContext) async throws -> Void
    }

    static let rollbacks: [Rollback] = [
        Rollback(
            fromVersion: 3,
            toVersion: 2,
            execute: { context in
                // Reverse Note split (combine back to generic Note)
                try await reverseNoteSplit(context)
            }
        )
    ]

    @MainActor
    static func rollback(to targetVersion: Int, context: ModelContext) async throws {
        let current = UserDefaults.standard.integer(forKey: "MigrationVersion")

        for rollback in rollbacks.reversed() where rollback.fromVersion <= current && rollback.toVersion >= targetVersion {
            print("Rolling back from \(rollback.fromVersion) to \(rollback.toVersion)")
            try await rollback.execute(context)
        }

        UserDefaults.standard.set(targetVersion, forKey: "MigrationVersion")
    }
}
```

**UI:**
```swift
#if DEBUG
struct MigrationDebugView: View {
    @State private var targetVersion = 1

    var body: some View {
        VStack {
            Text("Current: \(currentMigrationVersion)")
            Picker("Rollback to", selection: $targetVersion) {
                ForEach(1...3, id: \.self) { version in
                    Text("Version \(version)").tag(version)
                }
            }
            Button("Rollback") {
                Task {
                    try await MigrationRegistry.rollback(to: targetVersion, context: modelContext)
                }
            }
        }
    }
}
#endif
```

---

#### 8.4 Document Migration History (1 day)

Create `MIGRATIONS.md`:

```markdown
# Migration History

## Version 3 (Phase 3) - Note Split
**Date:** 2026-03-15
**Description:** Split generic Note model into domain-specific types (LessonNote, WorkNote, etc.)

**Reason:** Generic Note with 12 optional relationships violated single responsibility and hindered query performance.

**Breaking Changes:**
- Note model deprecated
- Use LessonNote, WorkNote, etc. instead
- Migration runs automatically on first launch

**Rollback:** `MigrationRegistry.rollback(to: 2)`

---

## Version 2 (Phase 3) - Legacy Note Extraction
**Date:** 2026-03-01
**Description:** Extracted string notes fields into Note model objects

**Reason:** Consolidate scattered note strings into unified Note system.

**Breaking Changes:**
- WorkModel.notes removed
- StudentLesson.notes removed
- Use `work.notes` relationship instead

**Rollback:** Not supported (data loss)

---

## Version 1 (Phase 2) - UUID to String
**Date:** 2026-02-15
**Description:** Convert UUID foreign keys to String for CloudKit compatibility

**Reason:** CloudKit requires string-based references.

**Breaking Changes:**
- All UUID fields now stored as String
- Automatic conversion via CloudKitUUID property wrapper

**Rollback:** Not supported (schema change)
```

---

### Phase 8 Checkpoint

**Final Checks:**
- [ ] Migration registry tested
- [ ] Rollback capability tested
- [ ] Documentation complete
- [ ] Minimum version check works
- [ ] Git tag: `phase-8-complete`

---

## FINAL MERGE TO MAIN (Week 32)

### Pre-Merge Checklist

- [ ] All 8 phases completed
- [ ] All tests passing (500+ tests)
- [ ] Test coverage: 50%+
- [ ] Performance benchmarks met
- [ ] No compiler warnings
- [ ] Documentation updated
- [ ] CHANGELOG.md created
- [ ] Backup compatibility verified

### Merge Strategy

```bash
# Final integration
git checkout Main
git merge refactor/phase-8-migrations --no-ff -m "Complete Option A aggressive refactoring

- Phase 1: Foundation fixes (@RawCodable, service docs, tests)
- Phase 2: Type safety (CloudKitUUID, relationship queries)
- Phase 3: Data model (Note split, denormalization removal)
- Phase 4: Service layer (DI container, remove singletons)
- Phase 5: Testing (50% coverage, snapshot tests, UI tests)
- Phase 6: Backup system (generic protocol-based codec)
- Phase 7: State management (Combine pipelines, cache coordination)
- Phase 8: Migration cleanup (versioned registry, rollbacks)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"

git tag -a "v2.0.0" -m "Major refactoring complete - Option A"
git push origin Main --tags
```

---

## POST-COMPLETION

### Monitoring (First 2 Weeks)

1. **User Feedback**
   - Watch for crash reports
   - Monitor app store reviews
   - Check support emails

2. **Performance Metrics**
   - Startup time
   - Query performance
   - Memory usage
   - Backup/restore times

3. **Data Integrity**
   - Run validation queries daily
   - Check for orphaned records
   - Verify relationship integrity

### Rollback Triggers

Immediately rollback if:
- Crash rate > 5%
- Data corruption reports
- Backup restore failures > 10%
- Critical feature broken

### Success Metrics (6 Months Post-Launch)

- [ ] Developer velocity: +40% (feature development speed)
- [ ] Bug rate: -30% (fewer production bugs)
- [ ] Onboarding time: -50% (new developer ramp-up)
- [ ] Test coverage: 50%+ maintained
- [ ] Technical debt: -60% (code complexity metrics)
- [ ] User satisfaction: Maintained or improved

---

## RESOURCES

### Documentation
- `REFACTORING_PLAN.md` (this file)
- `Services/SERVICE_REGISTRY.md` (Phase 1.2)
- `MIGRATIONS.md` (Phase 8.4)
- `CHANGELOG.md` (Final merge)

### Tags & Branches
- `pre-refactor-snapshot` - Emergency rollback
- `phase-N-complete` - Phase checkpoints
- `v2.0.0` - Final release

### Tools
- Xcode 15+
- Swift 5.9+
- SwiftData
- SnapshotTesting library
- XCTest

---

## TEAM COMMUNICATION

### Weekly Status Reports

Send to stakeholders every Friday:
- Phase progress (% complete)
- Blockers encountered
- Test results
- Performance metrics
- Next week's goals

### Risk Communication

Immediately escalate:
- Critical bugs discovered
- Performance regressions > 20%
- Timeline slippage > 1 week
- Breaking changes required

---

## CONCLUSION

This aggressive 6-month refactoring plan transforms Maria's Notebook from a CloudKit-constrained architecture to a modern, type-safe, testable codebase while maintaining full backward compatibility and easy rollback at every phase.

**Total Effort:** 170 days / 6 months
**Risk Level:** High (mitigated by checkpoints)
**Impact:** Transformational

**Next Step:** Begin Phase 1.1 - Create @RawCodable Property Wrapper

Good luck! 🚀
