# Architecture Guide

## Overview

Maria's Notebook follows a modular MVVM architecture with services:

- **SwiftUI** for the view layer
- **Core Data** for persistence (60 NSManagedObject subclasses)
- **MVVM** pattern for complex views (40+ ViewModels)
- **Service-oriented** backend (70+ services)
- **Repository pattern** for data access (13 repositories)

## App Lifecycle

```
App Launch
    ├─► MariasNotebookApp.init()
    │       └─► Configure Core Data stack (NSPersistentCloudKitContainer)
    │       └─► Initialize CloudKit (if enabled)
    ├─► AppBootstrapper.bootstrap()
    │       └─► Run data migrations
    │       └─► Backfill relationships
    │       └─► Initialize services
    └─► RootView.body
            └─► Display main navigation
```

**Key files:**
- `AppCore/MariasNotebookApp.swift` — App entry point, container config
- `AppCore/AppBootstrapper.swift` — Startup migrations
- `AppCore/RootView.swift` — Root navigation container
- `AppCore/AppRouter.swift` — Programmatic navigation

## Navigation

Pill-based navigation with two layouts:
- **Split View** (iPad/Mac) — `NavigationSplitView` with sidebar
- **Compact** (iPhone) — Tab-based via `RootCompactTabs`

```swift
enum NavigationItem: String, Hashable {
    case today, attendance, note, students, supplies
    case procedures, meetings, lessons, more, todos

    // Planning Sub-items
    case planningChecklist, planningAgenda, planningWork
    case planningProgression, planningProjects

    case community, schedules, issues, askAI, logs, settings
}
```

Navigation via `AppRouter`:
```swift
@Environment(\.appRouter) private var appRouter
appRouter.navigate(to: .openAttendance)
```

## Data Layer

### Core Data Patterns

```swift
// Direct fetch request (simple views)
@FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)])
private var students: FetchedResults<CDStudent>

// Filtered fetch request
@FetchRequest(
    sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)],
    predicate: NSPredicate(format: "statusRaw == %@", "active")
)
private var activeWork: FetchedResults<CDWorkModel>

// ViewModel (complex views)
@State private var viewModel = TodayViewModel()
```

**CloudKit compatibility rules:**
- Enums stored as raw strings (`statusRaw` pattern — see [ADR-001](ADRs/ADR-001-swiftdata-enum-pattern.md))
- Foreign keys as `String`, not `UUID`
- Optional relationship arrays
- No unique constraints (incompatible with CloudKit)

See [DATA_MODELS.md](DATA_MODELS.md) for full model reference.

### Repository Pattern

Repositories for complex data access; `@FetchRequest` for simple cases. See [ADR-003](ADRs/ADR-003-repository-pattern.md).

### Dependency Injection

Centralized via `AppDependencies` with lazy initialization. See [ADR-004](ADRs/ADR-004-dependency-injection.md).

## Service Layer

| Service | Location | Purpose |
|---------|----------|---------|
| `DataMigrations` | Services/ | Schema migrations |
| `LifecycleService` | Services/ | Work lifecycle state transitions |
| `BackupService` | Backup/ | Database backup/restore |
| `ChatService` | Services/Chat/ | AI chat functionality |
| `LessonPlanningService` | Services/LessonPlanning/ | AI-assisted lesson planning |
| `CloudKitSyncStatusService` | Services/ | CloudKit sync monitoring |
| `SyncedPreferencesStore` | Services/ | iCloud KVS preference sync |
| `FollowUpInboxEngine` | Services/ | Inbox and follow-up tasks |

Services accessed via `AppDependencies` or direct instantiation.

## UI Patterns

### View Composition

Views split into smaller files:
```
StudentDetailView.swift           # Main view
StudentDetailComponents.swift     # Subcomponents
StudentDetailViewModel.swift      # State management
StudentDetailSheetModifiers.swift # Sheet presentations
```

### Reusable Components (in Components/)

- `UnifiedNoteEditor` — Multi-context note editing
- `ObservationsView` — Note display with selection
- `DropZone` — Drag-and-drop targets
- `ToastOverlay` — Toast notifications
- `SearchField` — Debounced search input

### Error Handling

```swift
// Using safeSave extension on NSManagedObjectContext
context.safeSave()
// In view body:
.saveErrorAlert()
```

## ViewModel Guidelines

### When to Use ViewModels

**Use ViewModel when:** Complex business logic, performance optimization needed, multiple data sources, testability required, reusable logic.

**Keep `@State` in view when:** Simple UI state (toggles, selections), direct `@FetchRequest` with no logic, simple forms.

### Required Patterns

```swift
@Observable
@MainActor
final class MyViewModel {
    // State
    var items: [Item] = []

    // Dependencies (private, injected)
    private let repository: ItemRepository

    init(repository: ItemRepository) {
        self.repository = repository
    }

    // Actions
    func loadData() { ... }
}
```

### Performance Patterns

**Dictionary caching** — O(1) lookups instead of O(n) array filtering:
```swift
private(set) var itemsByID: [UUID: Item] = [:]
```

**Debouncing** — 400ms delay for expensive operations:
```swift
nonisolated(unsafe) private var searchTask: Task<Void, Never>?

private func scheduleSearch() {
    searchTask?.cancel()
    searchTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        self?.performSearch()
    }
}

deinit { searchTask?.cancel() }
```

**Batch property updates** — Set all `@Observable` properties together to trigger one SwiftUI re-render.

**Service delegation** — Extract complex logic (200+ lines) into service classes (e.g., `TodayDataFetcher`, `TodayCacheManager`).

**Equatable** — Implement on ViewModels driving expensive views for shallow change detection.

### Async Operations

Long-running operations yield periodically:
```swift
for (index, item) in items.enumerated() {
    // Process item
    if index % 5000 == 0 { await Task.yield() }
}
```

## Performance Checklist

### Completed Optimizations
- RootView backfill → async `AppBootstrapper` (50-70% faster launch)
- TodayViewModel → targeted fetches, dictionary caching, debouncing (60-80% memory reduction)
- SettingsView stats → repository-based filtered fetches
- WorksAgendaView → date range filtering (70-90% memory reduction)
- PresentationHistoryView → pagination

### Remaining Opportunities

| Target | Issue | Approach |
|--------|-------|----------|
| `PresentationsListView` | Unfiltered `@FetchRequest` | Repository with student-scoped fetch |
| `PlanningWeekView` | Loads all lessons | Date range filter |
| Heavy view body computations | Filtering in `body` | Move to ViewModel with caching |

### Anti-Patterns to Avoid

- Unfiltered `@FetchRequest` in frequently-accessed views
- O(n) `items.first { $0.id == targetID }` in row rendering (use dictionary)
- Computation in view `body` (cache in ViewModel)
- Blocking main thread with synchronous operations
- Storing UUIDs directly in foreign key fields (use String)

## Best Practices

- Use `@Observable` and `@MainActor` on all ViewModels
- Inject dependencies via constructor
- Use `private(set)` for ViewModel published properties
- Use `safeFetch`/`safeSave` extensions for data operations
- Use `safeSave` extensions for consistent save error handling
- Follow CloudKit compatibility patterns for all models
- Split large views into smaller component files

## Related Documentation

- [DATA_MODELS.md](DATA_MODELS.md) — Model reference
- [ADRs/](ADRs/) — Architecture decisions
- [CloudKit Guide](CloudKit/CLOUDKIT_GUIDE.md) — CloudKit setup
