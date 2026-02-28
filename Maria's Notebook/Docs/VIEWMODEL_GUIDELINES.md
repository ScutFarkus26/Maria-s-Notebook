# ViewModel Pattern Guidelines

**Created:** 2026-02-13
**Phase:** 6 - ViewModel Guidelines
**Purpose:** Document ViewModel patterns and best practices for Maria's Notebook

---

## Table of Contents

1. [Overview](#overview)
2. [Current State](#current-state)
3. [When to Use ViewModels](#when-to-use-viewmodels)
4. [ViewModel Patterns](#viewmodel-patterns)
5. [Best Practices](#best-practices)
6. [Examples](#examples)
7. [Migration Strategy](#migration-strategy)

---

## Overview

### What is a ViewModel?

A ViewModel is an `@Observable` class that sits between SwiftUI views and the data layer, providing:

- ✅ **Business Logic Separation** - Complex logic separate from view code
- ✅ **State Management** - Centralized state for complex views
- ✅ **Testability** - Logic can be tested without UI
- ✅ **Dependency Injection** - Clean dependency management
- ✅ **Performance Optimization** - Caching and debouncing strategies
- ✅ **Reusability** - Shared logic across multiple views

### Benefits

1. **Testability** - ViewModels can be unit tested without SwiftUI views
2. **Separation of Concerns** - Views focus on layout, ViewModels handle logic
3. **Maintainability** - Complex business logic in one place
4. **Performance** - Caching, debouncing, and optimization strategies
5. **Type Safety** - Strongly-typed state and methods

---

## Current State

### Existing ViewModels (20 total)

**Audit Results:**
- All use `@Observable` macro (Swift 5.9+)
- All marked `@MainActor` for UI safety
- Most inject dependencies via constructor
- Mix of simple and complex patterns

**Complexity Distribution:**
- **Simple (5-10 properties):** 8 ViewModels
  - InboxSheetViewModel
  - QuickNoteViewModel
  - PostPresentationFormViewModel
  - PresentationProgressViewModel
  - ClassSubjectChecklistViewModel
  - SettingsStatsViewModel
  - TopicDetailViewModel
  - GiveLessonViewModel

- **Medium (10-20 properties):** 7 ViewModels
  - SettingsViewModel
  - PresentationDetailViewModel
  - WorkDetailViewModel
  - AttendanceViewModel
  - LessonsViewModel
  - StudentsViewModel
  - StudentNotesViewModel
  - StudentProgressTabViewModel
  - WorksPlanningViewModel

- **Complex (20+ properties):** 5 ViewModels
  - **TodayViewModel** (340 lines, highly optimized)
  - **PresentationsViewModel** (486 lines, advanced patterns)
  - **StudentDetailViewModel** (414 lines, comprehensive caching)

### Key Patterns Identified

1. **Dependency Injection** - All ViewModels use constructor injection
2. **@Observable** - Modern Swift observation framework
3. **@MainActor** - All ViewModels marked for UI safety
4. **Repository Integration** - Most use repositories, not @Query
5. **Caching Strategies** - Complex ViewModels use aggressive caching
6. **Debouncing** - Performance-critical ViewModels use debouncing
7. **Separation of Concerns** - Delegate to service classes for complex logic

---

## When to Use ViewModels

### ✅ Use ViewModel When:

1. **Complex Business Logic** - More than simple CRUD operations
   - Multi-step workflows
   - Complex validation
   - Data transformations
   - Calculations

2. **Performance Optimization Needed**
   - Caching required
   - Debouncing needed
   - Batch operations
   - Background processing

3. **Multiple Data Sources**
   - Combining data from multiple repositories
   - Complex filtering/sorting
   - Derived state from multiple entities

4. **Testability Required**
   - Business logic needs unit tests
   - Complex state machines
   - Critical workflows

5. **Reusable Logic**
   - Logic used by multiple views
   - Shared state management
   - Common workflows

6. **Dependency Management**
   - Multiple service dependencies
   - Complex dependency graph
   - Need to mock dependencies for testing

### ❌ Keep State in View When:

1. **Simple UI State** - Toggle, selection, sheet presentation
   ```swift
   struct SimpleView: View {
       @State private var isShowingSheet = false
       @State private var selectedItem: Item? = nil
   }
   ```

2. **Direct @Query** - Simple list with no complex logic
   ```swift
   struct StudentsListView: View {
       @Query(sort: \Student.lastName) private var students: [Student]
       
       var body: some View {
           List(students) { student in
               StudentRow(student: student)
           }
       }
   }
   ```

3. **Form Data** - Simple forms with no validation
   ```swift
   struct SimpleFormView: View {
       @State private var name = ""
       @State private var age = 0
   }
   ```

4. **Single Responsibility** - View handles one simple task
   - Single entity display
   - Basic CRUD with repositories
   - Simple navigation

---

## ViewModel Patterns

### Pattern 1: Simple State Management

**Use When:** View has complex UI state but simple business logic

**Structure:**
```swift
@Observable
@MainActor
final class MyViewModel {
    // MARK: - State
    var selectedItems: Set<UUID> = []
    var isShowingSheet = false
    
    // MARK: - Dependencies
    private let service: MyService
    
    // MARK: - Initialization
    init(service: MyService = MyService.shared) {
        self.service = service
    }
    
    // MARK: - Actions
    func toggleSelection(_ id: UUID) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }
}
```

**Examples:**
- `InboxSheetViewModel` - Selection state management
- `QuickNoteViewModel` - Form state with photo picker
- `PostPresentationFormViewModel` - Form state management

---

### Pattern 2: Repository Integration

**Use When:** ViewModel needs to fetch/manipulate data

**Structure:**
```swift
@Observable
@MainActor
final class MyViewModel {
    // MARK: - State
    var items: [Item] = []
    
    // MARK: - Dependencies
    private let repository: ItemRepository
    private let modelContext: ModelContext
    
    // MARK: - Initialization
    init(repository: ItemRepository, modelContext: ModelContext) {
        self.repository = repository
        self.modelContext = modelContext
    }
    
    // MARK: - Data Loading
    func loadData() {
        items = repository.fetchAll()
    }
    
    // MARK: - Actions
    func createItem(name: String) {
        let item = repository.create(name: name)
        loadData() // Refresh
    }
}
```

**Examples:**
- `StudentDetailViewModel` - Uses repositories extensively
- `SettingsViewModel` - Backup operations with BackupService

---

### Pattern 3: Performance-Optimized Caching

**Use When:** Performance is critical, avoid repeated database queries

**Structure:**
```swift
@Observable
@MainActor
final class MyViewModel {
    // MARK: - State
    var items: [Item] = []
    
    // MARK: - Caches
    private(set) var itemsByID: [UUID: Item] = [:]
    private(set) var duplicateNames: Set<String> = []
    
    // MARK: - Cache Manager
    private let cacheManager = MyCacheManager()
    
    // MARK: - Data Loading
    func reload() {
        // PERFORMANCE: Fetch once, build caches
        let fetchedItems = repository.fetchAll()
        
        // Build lookup dictionaries
        itemsByID = Dictionary(fetchedItems.map { ($0.id, $0) }, 
                               uniquingKeysWith: { first, _ in first })
        
        // Build derived data
        duplicateNames = findDuplicateNames(fetchedItems)
        
        // BATCH UPDATE: Set all @Published properties together
        items = fetchedItems
    }
    
    // MARK: - Cache Accessors
    func displayName(for id: UUID) -> String {
        itemsByID[id]?.name ?? "Unknown"
    }
}
```

**Examples:**
- **TodayViewModel** (340 lines) - Extensive caching with TodayCacheManager
- **StudentDetailViewModel** - lessonsByID, presentationsByID caches
- **PresentationsViewModel** - Hash-based change detection

**Key Techniques:**
- Dictionary lookups instead of array filtering
- Batch property updates to minimize SwiftUI re-renders
- Separate cache manager classes for complex caching
- Derived state computed once and cached

---

### Pattern 4: Debounced Operations

**Use When:** User input triggers expensive operations

**Structure:**
```swift
@Observable
@MainActor
final class MyViewModel {
    // MARK: - State
    var searchText: String = "" {
        didSet { scheduleSearch() }
    }
    var results: [Item] = []
    
    // MARK: - Debouncing
    // Swift 6: nonisolated(unsafe) required for deinit access
    nonisolated(unsafe) private var searchTask: Task<Void, Never>?
    
    // MARK: - Actions
    private func scheduleSearch() {
        // Cancel previous task
        searchTask?.cancel()
        
        // Debounce search (400ms delay)
        searchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                performSearch()
            } catch {
                // Task cancelled, ignore
            }
        }
    }
    
    private func performSearch() {
        results = repository.search(searchText)
    }
    
    deinit {
        // Cancel pending task to prevent leaks
        searchTask?.cancel()
    }
}
```

**Examples:**
- **TodayViewModel.scheduleReload()** - Debounces database queries during rapid date changes
- **QuickNoteViewModel.analyzeText()** - Debounces AI analysis during typing

**Benefits:**
- Reduces database queries during rapid input
- Prevents excessive API calls
- Improves energy efficiency
- Better user experience (less lag)

---

### Pattern 5: Delegate to Service Classes

**Use When:** ViewModel logic becomes too complex (200+ lines)

**Structure:**
```swift
// ViewModel - Coordinates services
@Observable
@MainActor
final class MyViewModel {
    // MARK: - State
    var items: [Item] = []
    
    // MARK: - Services (delegate complex logic)
    private let dataFetcher = MyDataFetcher()
    private let scheduleBuilder = MyScheduleBuilder()
    private let cacheManager = MyCacheManager()
    
    // MARK: - Actions
    func reload() {
        // Delegate to services
        let fetchedData = dataFetcher.fetch(context: context)
        let schedule = scheduleBuilder.build(from: fetchedData)
        
        // Update state
        items = schedule
    }
}

// Service Classes - Pure logic, no @Observable
actor MyDataFetcher {
    func fetch(context: ModelContext) -> [Item] {
        // Complex fetch logic
    }
}

struct MyScheduleBuilder {
    func build(from data: [Item]) -> [ScheduledItem] {
        // Complex scheduling logic
    }
}
```

**Examples:**
- **TodayViewModel** delegates to:
  - `TodayDataFetcher` - Database operations
  - `TodayScheduleBuilder` - Schedule construction
  - `TodayNavigationService` - School day navigation
  - `TodayAttendanceLoader` - Attendance processing
  - `TodayCacheManager` - Student/lesson/work caching

**Benefits:**
- Keeps ViewModels focused and readable
- Services are reusable and testable
- Clear separation of concerns
- Easier to maintain and debug

---

### Pattern 6: Equatable for Performance

**Use When:** ViewModel drives expensive SwiftUI views

**Structure:**
```swift
@Observable
@MainActor
final class MyViewModel: Equatable {
    var items: [Item] = []
    var filter: FilterType = .all
    
    // MARK: - Equatable
    static func == (lhs: MyViewModel, rhs: MyViewModel) -> Bool {
        // Compare only properties that affect rendering
        guard lhs.filter == rhs.filter else { return false }
        
        // Shallow comparison (IDs only, not deep equality)
        guard lhs.items.count == rhs.items.count,
              lhs.items.map(\.id) == rhs.items.map(\.id) else {
            return false
        }
        
        return true
    }
}
```

**Examples:**
- **TodayViewModel** - Implements Equatable for performance
- Compares inputs (date, levelFilter) and output IDs (not full entities)

**Benefits:**
- SwiftUI skips re-rendering when ViewModel hasn't "meaningfully" changed
- Reduces expensive view updates
- Improves scroll performance
- Better energy efficiency

---

## Best Practices

### 1. Always Use @Observable and @MainActor

✅ **DO:**
```swift
@Observable
@MainActor
final class MyViewModel {
    var state: String = ""
}
```

❌ **DON'T:**
```swift
// OLD: ObservableObject (pre-Swift 5.9)
class MyViewModel: ObservableObject {
    @Published var state: String = ""
}

// UNSAFE: Missing @MainActor
@Observable
class MyViewModel {
    var state: String = "" // ⚠️ Can cause threading issues
}
```

**Why:**
- `@Observable` is modern Swift observation (faster, less boilerplate)
- `@MainActor` ensures all property access happens on main thread
- Required for SwiftUI safety and performance

---

### 2. Inject Dependencies via Constructor

✅ **DO:**
```swift
@Observable
@MainActor
final class MyViewModel {
    private let repository: ItemRepository
    private let service: MyService
    
    init(repository: ItemRepository, service: MyService = MyService.shared) {
        self.repository = repository
        self.service = service
    }
}
```

❌ **DON'T:**
```swift
@Observable
@MainActor
final class MyViewModel {
    private let repository = ItemRepository.shared // Hard-coded
    
    func doSomething() {
        MyService.shared.doWork() // Hard to test
    }
}
```

**Why:**
- Testability - Can inject mocks for unit tests
- Flexibility - Can swap implementations
- Clarity - Dependencies are explicit
- Backward compatibility - Default parameters preserve existing behavior

---

### 3. Separate State from Actions

✅ **DO:**
```swift
@Observable
@MainActor
final class MyViewModel {
    // MARK: - State
    var items: [Item] = []
    var selectedID: UUID? = nil
    var isLoading = false
    
    // MARK: - Actions
    func loadData() { ... }
    func selectItem(_ id: UUID) { ... }
}
```

❌ **DON'T:**
```swift
@Observable
@MainActor
final class MyViewModel {
    var items: [Item] = []
    func loadData() { ... }
    var selectedID: UUID? = nil
    var isLoading = false
    func selectItem(_ id: UUID) { ... }
}
```

**Why:**
- Readability - Clear organization
- Maintainability - Easy to find properties vs methods
- Convention - Consistent with existing ViewModels

---

### 4. Use Private for Dependencies

✅ **DO:**
```swift
@Observable
@MainActor
final class MyViewModel {
    private let repository: ItemRepository // Private
    
    func loadData() {
        items = repository.fetchAll()
    }
}
```

❌ **DON'T:**
```swift
@Observable
@MainActor
final class MyViewModel {
    let repository: ItemRepository // Public - view can bypass ViewModel
}
```

**Why:**
- Encapsulation - Views can't bypass ViewModel logic
- Single source of truth - All data access goes through ViewModel methods
- Maintainability - Can change repository implementation without breaking views

---

### 5. Batch Property Updates for Performance

✅ **DO:**
```swift
func reload() {
    // PERFORMANCE: Fetch all data first
    let items = repository.fetchItems()
    let summary = computeSummary(items)
    let cache = buildCache(items)
    
    // BATCH UPDATE: Set all properties together
    // This triggers ONE SwiftUI view update
    self.items = items
    self.summary = summary
    self.cache = cache
}
```

❌ **DON'T:**
```swift
func reload() {
    // BAD: Each property update triggers a view re-render
    self.items = repository.fetchItems() // Re-render 1
    self.summary = computeSummary(items)  // Re-render 2
    self.cache = buildCache(items)        // Re-render 3
}
```

**Why:**
- Performance - 1 view update instead of N
- Prevents visual glitches from intermediate states
- Better energy efficiency

---

### 6. Use Caches for Expensive Lookups

✅ **DO:**
```swift
@Observable
@MainActor
final class MyViewModel {
    var items: [Item] = []
    private(set) var itemsByID: [UUID: Item] = [:]
    
    func reload() {
        let fetched = repository.fetchAll()
        itemsByID = Dictionary(fetched.map { ($0.id, $0) }, 
                               uniquingKeysWith: { first, _ in first })
        items = fetched
    }
    
    func displayName(for id: UUID) -> String {
        itemsByID[id]?.name ?? "Unknown" // O(1) lookup
    }
}
```

❌ **DON'T:**
```swift
@Observable
@MainActor
final class MyViewModel {
    var items: [Item] = []
    
    func displayName(for id: UUID) -> String {
        items.first { $0.id == id }?.name ?? "Unknown" // O(n) lookup
    }
}
```

**Why:**
- Performance - Dictionary lookup is O(1) vs array filter O(n)
- Critical for row rendering in Lists
- Prevents scroll lag

---

### 7. Debounce Expensive Operations

✅ **DO:**
```swift
@Observable
@MainActor
final class MyViewModel {
    var searchText: String = "" {
        didSet { scheduleSearch() }
    }
    
    nonisolated(unsafe) private var searchTask: Task<Void, Never>?
    
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.performSearch()
        }
    }
    
    deinit {
        searchTask?.cancel()
    }
}
```

❌ **DON'T:**
```swift
@Observable
@MainActor
final class MyViewModel {
    var searchText: String = "" {
        didSet {
            performSearch() // Called on EVERY keystroke
        }
    }
}
```

**Why:**
- Performance - Reduces database queries during typing
- Energy efficiency - Fewer CPU cycles
- Better UX - Less lag

---

### 8. Delegate Complex Logic to Services

✅ **DO:**
```swift
@Observable
@MainActor
final class MyViewModel {
    private let dataFetcher = MyDataFetcher()
    private let scheduler = MyScheduler()
    
    func reload() {
        let data = dataFetcher.fetch(context: context)
        items = scheduler.schedule(data)
    }
}

actor MyDataFetcher {
    func fetch(context: ModelContext) -> [Item] { ... }
}
```

❌ **DON'T:**
```swift
@Observable
@MainActor
final class MyViewModel {
    // 500 lines of complex logic in ViewModel
    func reload() {
        // Massive method with all logic inline
    }
}
```

**Why:**
- Maintainability - Easier to understand and test
- Reusability - Services can be used by other ViewModels
- Single Responsibility - ViewModel coordinates, services implement

---

## Examples

### Example 1: Simple ViewModel (InboxSheetViewModel)

**Use Case:** Manage selection state for inbox items

```swift
@Observable
@MainActor
final class InboxSheetViewModel {
    // MARK: - State
    var selected: Set<UUID> = []
    
    // MARK: - Dependencies
    private let toastService: ToastService
    
    init(toastService: ToastService = ToastService.shared) {
        self.toastService = toastService
    }
    
    // MARK: - Actions
    func toggleSelection(_ id: UUID) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }
    
    func consolidateSelected(lessons: [LessonAssignment], modelContext: ModelContext) {
        guard !selected.isEmpty else { return }

        // Business logic
        let selectedLessons = lessons.filter { selected.contains($0.id) }
        PresentationMergeService.merge(
            presentations: selectedLessons,
            modelContext: modelContext,
            toastService: toastService
        )
        
        // Clear selection
        selected.removeAll()
    }
}
```

**Characteristics:**
- ~100 lines total
- Simple state management
- Delegates complex logic to services
- Minimal dependencies

---

### Example 2: Medium Complexity (SettingsViewModel)

**Use Case:** Manage backup/restore operations

```swift
@Observable
@MainActor
final class SettingsViewModel {
    // MARK: - UI State
    var restoreMode: BackupService.RestoreMode = .merge
    var backupProgress: Double = 0
    var backupMessage: String = ""
    var importProgress: Double = 0
    var resultSummary: String? = nil
    var exportData: Data? = nil
    
    // MARK: - Dependencies
    private let dependencies: AppDependencies
    private var backupService: BackupService { dependencies.backupService }
    
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }
    
    // MARK: - Actions
    func performExport(modelContext: ModelContext, encryptBackups: Bool) async {
        do {
            backupProgress = 0
            backupMessage = "Preparing…"
            
            let summary = try await backupService.exportBackup(
                modelContext: modelContext,
                to: url,
                password: encryptBackups ? "password" : nil
            ) { [weak self] progress, message in
                MainActor.assumeIsolated {
                    self?.backupProgress = progress
                    self?.backupMessage = message
                }
            }
            
            resultSummary = "Exported successfully"
            setLastBackupNow()
        } catch {
            importError = "Failed: \(error.localizedDescription)"
        }
    }
}
```

**Characteristics:**
- ~240 lines total
- Async operations with progress tracking
- Service delegation (BackupService)
- User-facing error handling

---

### Example 3: Complex Optimized (TodayViewModel)

**Use Case:** Today hub with extensive caching and performance optimization

```swift
@Observable
@MainActor
final class TodayViewModel: Equatable {
    // MARK: - Dependencies
    private let context: ModelContext
    private let cacheManager = TodayCacheManager()
    
    // MARK: - Inputs
    var date: Date {
        didSet {
            let normalized = date.startOfDay
            if date != normalized {
                date = normalized
                return
            }
            scheduleReload()
        }
    }
    var levelFilter: LevelFilter = .all { didSet { scheduleReload() } }
    
    // MARK: - Outputs
    var todaysLessons: [LessonAssignment] = []
    var todaysSchedule: [ScheduledWorkItem] = []
    var completedWork: [WorkModel] = []
    var attendanceSummary: AttendanceSummary = AttendanceSummary()
    
    // MARK: - Cache Accessors
    var studentsByID: [UUID: Student] { cacheManager.studentsByID }
    var lessonsByID: [UUID: Lesson] { cacheManager.lessonsByID }
    
    // MARK: - Debouncing
    nonisolated(unsafe) private var reloadTask: Task<Void, Never>?
    
    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
    
    func reload() {
        // PERFORMANCE: Delegate to specialized services
        let lessonsResult = TodayLessonsLoader.fetchLessonsWithIDs(...)
        let workResult = TodayWorkLoader.loadWork(...)
        let attendanceResult = TodayDataFetcher.fetchAttendance(...)
        
        // Build caches
        cacheManager.loadStudentsIfNeeded(...)
        cacheManager.loadLessonsIfNeeded(...)
        
        // BATCH UPDATE: All properties together
        todaysLessons = lessonsResult.lessons
        todaysSchedule = workResult.todaysSchedule
        completedWork = workResult.completedWork
        attendanceSummary = attendanceResult.summary
    }
    
    // MARK: - Equatable
    static func == (lhs: TodayViewModel, rhs: TodayViewModel) -> Bool {
        // Shallow comparison for performance
        guard lhs.date == rhs.date,
              lhs.levelFilter == rhs.levelFilter,
              lhs.todaysLessons.map(\.id) == rhs.todaysLessons.map(\.id) else {
            return false
        }
        return true
    }
}
```

**Characteristics:**
- 340 lines total
- Extensive service delegation (6 service classes)
- Advanced caching (TodayCacheManager)
- Debouncing for performance
- Equatable for SwiftUI optimization
- Batch property updates

---

## Migration Strategy

### Pragmatic Approach (Recommended)

**Don't force ViewModel adoption**. Use ViewModels when:
1. Adding new complex features
2. Refactoring views with business logic
3. Performance optimization needed
4. Testing requirements

**Keep state in views when:**
1. Simple UI state (toggles, selections)
2. Direct @Query with no logic
3. Simple forms
4. Works well as-is

### When to Extract ViewModel from View

**Red Flags (Consider ViewModel):**
- View file > 300 lines
- Complex business logic in view
- Multiple repositories accessed
- Difficult to test
- Performance issues
- Reusable logic

**Example Refactor:**
```swift
// BEFORE: Logic in view
struct MyView: View {
    @Query private var items: [Item]
    @State private var selected: Set<UUID> = []
    
    var body: some View {
        List(filteredItems) { item in ... }
    }
    
    private var filteredItems: [Item] {
        // Complex filtering logic
        items.filter { ... }
             .sorted { ... }
    }
    
    private func processItem(_ item: Item) {
        // Complex business logic
    }
}

// AFTER: Logic in ViewModel
@Observable
@MainActor
final class MyViewModel {
    var items: [Item] = []
    var selected: Set<UUID> = []
    
    func reload() {
        items = repository.fetchAll()
    }
    
    func processItem(_ item: Item) {
        // Complex business logic moved here
    }
}

struct MyView: View {
    @State private var viewModel: MyViewModel
    
    var body: some View {
        List(viewModel.items) { item in ... }
    }
}
```

---

## Success Criteria

✅ **Phase 6 Complete When:**
1. ViewModel patterns documented (this file) ✅
2. Examples provided for each complexity level ✅
3. Best practices defined ✅
4. When to use ViewModels vs direct state clearly defined ✅
5. Migration strategy established ✅

**No code changes required** - patterns already exist in 20 ViewModels, just need documentation and future adoption.

---

## Related Documentation

- `PresentationsViewModel.swift` - Complex example with advanced patterns
- `TodayViewModel.swift` - Performance-optimized example
- `StudentDetailViewModel.swift` - Comprehensive caching example
- `InboxSheetViewModel.swift` - Simple example
- `REPOSITORY_GUIDELINES.md` - Repository pattern (used by ViewModels)
- `ERROR_HANDLING_GUIDELINES.md` - Error handling (used by ViewModels)

---

## Conclusion

Maria's Notebook has excellent ViewModel patterns across 20 ViewModels. Key patterns to follow:

**Key Takeaways:**
1. ✅ Always use `@Observable` and `@MainActor`
2. ✅ Inject dependencies via constructor
3. ✅ Use caches for expensive lookups (Dictionary over Array)
4. ✅ Debounce expensive operations (400ms recommended)
5. ✅ Delegate to service classes for complex logic
6. ✅ Batch property updates for performance
7. ✅ Only use ViewModels when they add value

**Decision Framework:**
- Simple UI state → `@State` in view
- Complex business logic → ViewModel
- Performance issues → ViewModel with caching
- Testing required → ViewModel
- When in doubt → Start with `@State`, refactor to ViewModel if needed

---

**Document Version:** 1.0
**Last Updated:** 2026-02-13
**Author:** Claude Sonnet 4.5
**Status:** Living Document
