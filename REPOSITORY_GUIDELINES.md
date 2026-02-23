# Repository Pattern Guidelines

**Created:** 2026-02-13
**Phase:** 3 - Repository Standardization
**Purpose:** Document repository patterns and migration strategies for Maria's Notebook

---

## Table of Contents

1. [Overview](#overview)
2. [Current State](#current-state)
3. [Repository Architecture](#repository-architecture)
4. [When to Use Repositories](#when-to-use-repositories)
5. [Migration Patterns](#migration-patterns)
6. [SwiftUI Reactivity](#swiftui-reactivity)
7. [Best Practices](#best-practices)
8. [Examples](#examples)

---

## Overview

### What is a Repository?

A repository is a data access layer that encapsulates SwiftData queries and provides a clean, testable interface for views and view models. Repositories:

- ✅ **Abstract data access** - Views don't know about SwiftData implementation details
- ✅ **Enable testing** - Can inject mock repositories for unit tests
- ✅ **Centralize queries** - Reusable query logic across the app
- ✅ **Coordinate saves** - Integrate with SaveCoordinator for error handling

### Benefits

1. **Testability** - Views can be tested with mock data without a real database
2. **Maintainability** - Query logic in one place, not scattered across views
3. **Type Safety** - Strongly-typed methods instead of string-based predicates
4. **Error Handling** - Centralized save coordination and error recovery
5. **Separation of Concerns** - Views focus on UI, repositories handle data

---

## Current State

### Existing Infrastructure

**Base Protocol:** `RepositoryProtocol.swift`
```swift
protocol Repository {
    associatedtype Model: PersistentModel
    var context: ModelContext { get }
}

protocol SavingRepository: Repository {
    var saveCoordinator: SaveCoordinator? { get }
}
```

**Container:** `RepositoryContainer.swift`
- Provides access to all repositories via `dependencies.repositories`
- Handles consistent context and save coordinator injection

**Existing Repositories:** (14 total)
1. `StudentRepository` - Student CRUD
2. `LessonRepository` - Lesson CRUD
3. `StudentLessonRepository` - Presentation/StudentLesson CRUD
4. `PresentationRepository` - Unified presentation model
5. `NoteRepository` - Note CRUD
6. `NoteTemplateRepository` - Note template CRUD
7. `DocumentRepository` - Document CRUD
8. `AttendanceRepository` - Attendance CRUD
9. `MeetingRepository` - Meeting CRUD
10. `MeetingTemplateRepository` - Meeting template CRUD
11. `ReminderRepository` - Reminder CRUD
12. `ProjectRepository` - Project CRUD
13. `WorkRepository` - Work/practice CRUD
14. `PracticeSessionRepository` - Practice session CRUD

### Current @Query Usage

**Audit Results:**
- **163 @Query usages** across **73 files**
- Most common patterns:
  - `@Query` for list views (StudentLesson, Lesson, Student, Work)
  - `@Query` for dropdown/picker data
  - `@Query` for change detection
  - `@Query` for filtered views (inbox, scheduled items)

**High-Impact Files** (3+ @Query usages):
- `PlanningWeekViewMac.swift` (7)
- `PresentationsView.swift` (6)
- `StudentMeetingsTab.swift` (5)
- `LessonAssignmentHistoryView.swift` (5)
- `StudentsView.swift` (5)
- `MeetingsWorkflowView.swift` (6)
- `WorkDetailView.swift` (6)
- `WorksAgendaView.swift` (4)
- `PracticePartnershipsView.swift` (4)
- `ProjectWeeksEditorView.swift` (4)

---

## Repository Architecture

### Structure

```
Repositories/
├── RepositoryProtocol.swift       # Base protocols
├── RepositoryContainer.swift      # Central factory
├── StudentRepository.swift        # Student CRUD
├── LessonRepository.swift         # Lesson CRUD
├── StudentLessonRepository.swift  # Presentation CRUD
└── ... (11 more repositories)
```

### Standard Repository Pattern

```swift
@MainActor
struct EntityRepository: SavingRepository {
    typealias Model = EntityModel

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch Methods

    func fetchEntity(id: UUID) -> EntityModel? {
        var descriptor = FetchDescriptor<EntityModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func fetchEntities(
        predicate: Predicate<EntityModel>? = nil,
        sortBy: [SortDescriptor<EntityModel>] = []
    ) -> [EntityModel] {
        var descriptor = FetchDescriptor<EntityModel>()
        descriptor.predicate = predicate
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Domain-Specific Queries

    func fetchActive() -> [EntityModel] {
        let predicate = #Predicate<EntityModel> { !$0.isArchived }
        return fetchEntities(predicate: predicate)
    }

    // MARK: - Create/Update

    func create(...) -> EntityModel {
        let entity = EntityModel(...)
        context.insert(entity)
        return entity
    }

    func update(_ entity: EntityModel, ...) {
        // Update properties
        save(reason: "Updating entity")
    }

    // MARK: - Delete

    func delete(_ entity: EntityModel) {
        context.delete(entity)
        save(reason: "Deleting entity")
    }
}
```

### Integration with AppDependencies

```swift
// AppDependencies.swift
private var _repositories: RepositoryContainer?
var repositories: RepositoryContainer {
    if let container = _repositories {
        return container
    }
    let container = RepositoryContainer(
        context: modelContext,
        saveCoordinator: nil  // Or inject saveCoordinator
    )
    _repositories = container
    return container
}
```

---

## When to Use Repositories

### ✅ Use Repositories When:

1. **ViewModels** - Always use repositories in ViewModels
2. **Complex Queries** - Multi-predicate or computed queries
3. **Reusable Logic** - Query used in multiple places
4. **Testable Code** - Need to mock data for tests
5. **Business Logic** - CRUD operations with validation/side effects
6. **Services** - Background services accessing data

### ❌ Keep @Query When:

1. **Simple List Views** - Single entity type, no complex filtering (TEMPORARY)
2. **Change Detection** - Using @Query IDs to trigger view updates (HYBRID PATTERN)
3. **Dropdown/Picker Data** - Small reference data sets (TEMPORARY)
4. **Preview Code** - SwiftUI previews with static data

### 🟡 Hybrid Pattern (Recommended):

Use @Query for change detection + Repository for data fetching:

```swift
struct MyView: View {
    @Environment(\.dependencies) private var dependencies

    // Change detection only - extract IDs immediately
    @Query private var itemsForChangeDetection: [Item]
    private var itemIDs: [UUID] { itemsForChangeDetection.map(\.id) }

    var body: some View {
        List {
            // Use repository for actual data fetching
            ForEach(dependencies.repositories.items.fetchActive()) { item in
                ItemRow(item: item)
            }
        }
        // Re-fetch when IDs change
        .onChange(of: itemIDs) {
            // Trigger refresh if needed
        }
    }
}
```

---

## Migration Patterns

### Pattern 1: Simple View Migration

**Before:**
```swift
struct StudentsView: View {
    @Query(sort: \\Student.lastName) private var students: [Student]

    var body: some View {
        List(students) { student in
            StudentRow(student: student)
        }
    }
}
```

**After:**
```swift
struct StudentsView: View {
    @Environment(\\.dependencies) private var dependencies

    private var students: [Student] {
        dependencies.repositories.students.fetchAll(
            sortBy: [SortDescriptor(\\.lastName)]
        )
    }

    var body: some View {
        List(students) { student in
            StudentRow(student: student)
        }
    }
}
```

### Pattern 2: Filtered View Migration

**Before:**
```swift
struct InboxView: View {
    @Query(filter: #Predicate<StudentLesson> {
        $0.scheduledFor == nil && !$0.isPresented
    }) private var inboxItems: [StudentLesson]

    var body: some View {
        List(inboxItems) { item in
            InboxRow(item: item)
        }
    }
}
```

**After:**
```swift
struct InboxView: View {
    @Environment(\\.dependencies) private var dependencies

    private var inboxItems: [StudentLesson] {
        dependencies.repositories.studentLessons.fetchInboxItems()
    }

    var body: some View {
        List(inboxItems) { item in
            InboxRow(item: item)
        }
    }
}
```

### Pattern 3: ViewModel Migration

**Before:**
```swift
@Observable
final class MyViewModel {
    @Query private var items: [Item]  // ❌ Can't use @Query in ViewModels

    func doSomething() {
        // Access items...
    }
}
```

**After:**
```swift
@Observable
final class MyViewModel {
    private let repository: ItemRepository

    init(repository: ItemRepository) {
        self.repository = repository
    }

    func doSomething() {
        let items = repository.fetchAll()
        // Process items...
    }
}
```

### Pattern 4: Hybrid Pattern (Best for Large Views)

**Before:**
```swift
struct ComplexView: View {
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    @Query private var presentations: [StudentLesson]

    var body: some View {
        // Complex layout using all three queries
    }
}
```

**After (Hybrid):**
```swift
struct ComplexView: View {
    @Environment(\\.dependencies) private var dependencies

    // Change detection only
    @Query private var studentsForChange: [Student]
    @Query private var lessonsForChange: [Lesson]
    @Query private var presentationsForChange: [StudentLesson]

    private var studentIDs: [UUID] { studentsForChange.map(\\.id) }
    private var lessonIDs: [UUID] { lessonsForChange.map(\\.id) }
    private var presentationIDs: [UUID] { presentationsForChange.map(\\.id) }

    var body: some View {
        // Use repositories for actual data fetching
        let students = dependencies.repositories.students.fetchAll()
        let lessons = dependencies.repositories.lessons.fetchAll()
        let presentations = dependencies.repositories.studentLessons.fetchAll()

        // Complex layout
    }
}
```

---

## SwiftUI Reactivity

### The Challenge

SwiftUI's `@Query` automatically triggers view updates when data changes. When migrating to repositories, we need to maintain this reactivity.

### Solution 1: Manual Change Detection

```swift
struct MyView: View {
    @Environment(\\.dependencies) private var dependencies
    @State private var items: [Item] = []
    @State private var refreshTrigger = UUID()

    var body: some View {
        List(items) { item in
            ItemRow(item: item)
        }
        .task {
            await loadItems()
        }
        .onChange(of: refreshTrigger) {
            Task { await loadItems() }
        }
    }

    private func loadItems() async {
        items = dependencies.repositories.items.fetchAll()
    }

    func refresh() {
        refreshTrigger = UUID()
    }
}
```

### Solution 2: Hybrid Pattern (Recommended)

```swift
struct MyView: View {
    @Environment(\\.dependencies) private var dependencies

    // Lightweight change detection
    @Query private var itemsForChange: [Item]
    private var itemIDs: [UUID] { itemsForChange.map(\\.id) }

    var body: some View {
        // Repository for data
        let items = dependencies.repositories.items.fetchAll()

        List(items) { item in
            ItemRow(item: item)
        }
    }
}
```

### Solution 3: ViewModel with ObservableObject

```swift
@Observable
final class MyViewModel {
    private let repository: ItemRepository
    private var items: [Item] = []

    init(repository: ItemRepository) {
        self.repository = repository
    }

    func load() {
        items = repository.fetchAll()
    }

    func refresh() {
        load()
    }
}

struct MyView: View {
    @State private var viewModel: MyViewModel

    var body: some View {
        List(viewModel.items) { item in
            ItemRow(item: item)
        }
        .task {
            viewModel.load()
        }
    }
}
```

---

## Best Practices

### 1. Repository Design

✅ **DO:**
- Keep repositories focused on a single entity type
- Use domain-specific method names (`fetchInboxItems()` not `fetchWhere()`)
- Return arrays, not optionals (empty array for no results)
- Use `@MainActor` for all repositories
- Inject `SaveCoordinator` for coordinated saves

❌ **DON'T:**
- Mix multiple entity types in one repository
- Use generic `fetch(predicate:)` for everything
- Return `nil` for empty results
- Access UI code from repositories
- Save directly without SaveCoordinator

### 2. Query Design

✅ **DO:**
- Name fetch methods clearly (`fetchActive()`, `fetchScheduled(for:)`)
- Accept predicates for flexible filtering
- Accept sort descriptors for custom ordering
- Return unwrapped arrays with `?? []`
- Use `fetchLimit` for single-item queries

❌ **DON'T:**
- Force-unwrap query results
- Ignore errors silently (log them)
- Create overly-specific fetch methods
- Duplicate query logic

### 3. Save Coordination

✅ **DO:**
- Use `save(reason:)` for all saves
- Use `saveWithToast(successMessage:reason:)` for user-facing saves
- Provide descriptive reasons ("Deleting student", "Updating lesson")
- Check save results

❌ **DON'T:**
- Call `context.save()` directly
- Ignore save failures
- Use generic reasons ("Saving", "Update")

### 4. Testing

✅ **DO:**
- Create mock repositories for tests
- Inject repositories via init
- Test repository methods in isolation
- Verify save coordinator integration

❌ **DON'T:**
- Test against real database in unit tests
- Hard-code repository instances
- Skip repository tests

---

## Examples

### Example 1: StudentRepository Usage

```swift
struct StudentDetailView: View {
    @Environment(\\.dependencies) private var dependencies
    let studentID: UUID

    private var student: Student? {
        dependencies.repositories.students.fetch(id: studentID)
    }

    var body: some View {
        if let student = student {
            VStack {
                Text(student.fullName)
                Button("Archive") {
                    dependencies.repositories.students.archive(student)
                }
            }
        }
    }
}
```

### Example 2: Complex Filtering

```swift
struct WorkLogView: View {
    @Environment(\\.dependencies) private var dependencies
    let workID: UUID
    let dateRange: ClosedRange<Date>

    private var sessions: [PracticeSession] {
        dependencies.repositories.practiceSessions.fetchSessions(
            workID: workID,
            dateRange: dateRange
        )
    }

    var body: some View {
        List(sessions) { session in
            PracticeSessionRow(session: session)
        }
    }
}
```

### Example 3: Create with Validation

```swift
struct NewStudentSheet: View {
    @Environment(\\.dependencies) private var dependencies
    @Environment(\\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""

    var body: some View {
        Form {
            TextField("First Name", text: $firstName)
            TextField("Last Name", text: $lastName)
            Button("Create") {
                createStudent()
            }
        }
    }

    private func createStudent() {
        let student = dependencies.repositories.students.create(
            firstName: firstName,
            lastName: lastName
        )
        dependencies.repositories.saveWithToast(
            successMessage: "Student created"
        )
        dismiss()
    }
}
```

---

## Migration Priority

### Phase 3A: High-Impact Views (Week 1-2)
1. `PresentationsView` - 6 @Query ✅ (Already hybrid)
2. `PlanningWeekViewMac` - 7 @Query
3. `MeetingsWorkflowView` - 6 @Query
4. `WorkDetailView` - 6 @Query
5. `StudentsView` - 5 @Query

### Phase 3B: ViewModels (Week 2-3)
1. `PresentationsViewModel` - Already uses repository
2. `StudentDetailViewModel` - 1 @Query
3. Other ViewModels as needed

### Phase 3C: Remaining Views (Week 3+)
- Migrate remaining 60+ files incrementally
- Use hybrid pattern for complex views
- Full migration not required if @Query works well

---

## Success Criteria

✅ **Phase 3 Complete When:**
1. All ViewModels use repositories (not @Query)
2. Top 10 high-impact views migrated to repositories or hybrid pattern
3. New code uses repositories by default
4. Repository guidelines documented (this file)
5. Zero behavior changes
6. Build succeeds with no warnings

---

## Related Documentation

- `PHASE3_COMPLETION.md` - Phase 3 completion report
- `MIGRATION_STRATEGY.md` - Overall migration strategy
- `RepositoryProtocol.swift` - Base protocol implementation
- `RepositoryContainer.swift` - Container implementation

---

## Conclusion

Repositories provide a clean, testable data access layer for Maria's Notebook. The hybrid pattern (@ Query for change detection + repositories for data fetching) offers the best balance of SwiftUI reactivity and clean architecture.

**Key Takeaway:** Not all @Query usages need migration. Focus on ViewModels and high-complexity views. Simple views can keep @Query if it works well.

---

**Document Version:** 1.0
**Last Updated:** 2026-02-13
**Author:** Claude Sonnet 4.5
**Status:** Living Document (update as patterns evolve)
