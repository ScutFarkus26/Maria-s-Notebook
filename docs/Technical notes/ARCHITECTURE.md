# Architecture Guide

## Overview

Cosmic Daybook follows a modular MVVM architecture with services:

- **SwiftUI** for the view layer
- **Core Data** for persistence (77 NSManagedObject subclasses)
- **MVVM** pattern for complex views (40+ ViewModels)
- **Service-oriented** backend (70+ services)
- **Repository pattern** for data access (13 repositories)

## App Lifecycle

```
App Launch
    ├─► CosmicDaybookApp.init()
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
- `AppCore/CosmicDaybookApp.swift` — App entry point, container config
- `AppCore/AppBootstrapper.swift` — Startup migrations
- `AppCore/RootView/RootView.swift` — Root navigation container
- `AppCore/AppRouter.swift` — Programmatic navigation

## Navigation

Two layouts over one table:
- **macOS / visionOS** — `NavigationSplitView` with `RootSidebar`; each group's collapsed state persists (`UserDefaultsKeys.sidebarGroupExpanded`)
- **iOS** — `RootAdaptiveTabs`, a `TabView(.sidebarAdaptable)`: a tab bar on iPhone (Today, Students, Attendance, Lessons & Work, More) and a grouped sidebar on iPad

```swift
// AppCore/RootView/RootView+NavigationGroup.swift — the single source for every sidebar and the More list
enum NavigationGroupID { case today, children, lessonsAndWork, planning, records, library, system }
struct NavigationGroup { let id: ID; let title: String; let items: [NavigationItem]; let isExpandedByDefault: Bool }

// AppCore/RootView/RootView+NavigationItem.swift — raw values are persisted and frozen (NavigationGroupTests)
enum NavigationItem: String, Hashable, Identifiable, CaseIterable {
    case today, todos, students, attendance, meetings, parentReports, progressDashboard,
         planningAgenda, lessons, planningChecklist, curriculumMap, planningCalendar, smallSequencePlanner,
         logs, notes, teachingAlbums, stories, bookClub, procedures, resourceLibrary, supplies, goingOut,
         community, schedules, thisWeeksParsha, parshaCalendar, lessonRecall, planningProjects, askAI, settings
    case note, more, perpetualCalendar   // aliases — `canonical` maps them to a live destination
}
```

**Links to one item (2026-11-22):** `cosmicdaybook://student/<id>`, `lesson/<id>` and `follow-up/<id>` (ids as Claude's tools return them; registered under `CFBundleURLTypes` in both Info.plists) open that item in the main window, so a Tide to-do's link can point at it (`AppCore/NotebookLink.swift`). A link only opens, never changes data. Parsing is strict (this scheme, a known kind, one UUID path part, no user, port, query or fragment); an id not in this notebook opens nothing and is logged. The main window takes it beside Handoff (`onOpenURL` in the Handoff modifier); one that arrives before the screen is up waits in `WindowHandoff`. A follow-up opens where it shows: a goal, or a flagged note about one child, on that child's page; a todo or a wider note on Today. The Keyboard Shortcuts, detail and Quick Note scenes don't claim links. A Mac Debug build registers the scheme with LaunchServices, so unregister it after building (`lsregister -u <app>`), or a link would open the Debug copy on the live notebook.

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
- Enums stored as raw strings (`statusRaw` pattern — see [ADR-001](<Decision records/ADR-001-swiftdata-enum-pattern.md>))
- Foreign keys as `String`, not `UUID`
- Optional relationship arrays
- No unique constraints (incompatible with CloudKit)

See [DATA_MODELS.md](DATA_MODELS.md) for full model reference.

### Repository Pattern

Repositories for complex data access; `@FetchRequest` for simple cases. See [ADR-003](<Decision records/ADR-003-repository-pattern.md>).

### Dependency Injection

Centralized via `AppDependencies` with lazy initialization. See [ADR-004](<Decision records/ADR-004-dependency-injection.md>).

## Service Layer

| Service | Location | Purpose |
|---------|----------|---------|
| `DataMigrations` | Services/ | Schema migrations |
| `LifecycleService` | Work/Services/ | Work lifecycle state transitions |
| `BackupService` | Backup/ | Database backup/restore |
| `ChatService` | Chat/Services/ | AI chat functionality |
| `LessonPlanningService` | Planning/AIPlanning/LessonPlanning/ | AI-assisted lesson planning |
| `CloudKitSyncStatusService` | Services/ | CloudKit sync monitoring |
| `SyncedPreferencesStore` | Services/ | iCloud KVS preference sync |

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

- `ToastOverlay` — Toast notifications
- `SearchField` — Debounced search input

Feature-owned composed views stay with their feature. For example, note editing lives in
`Notes/Editor/` and observation browsing lives in `Notes/Observations/`.

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

**Debouncing** — 400ms delay for expensive operations. The task is a plain stored property the views don't track, and the closure holds the model weakly, so no `deinit` (and no `nonisolated(unsafe)`) is needed: once the model is gone the task wakes, finds nothing, and ends. Sleep first, then check for cancellation and take `self`, so a closed screen isn't kept alive for the wait:
```swift
@ObservationIgnored private var searchTask: Task<Void, Never>?

private func scheduleSearch() {
    searchTask?.cancel()
    searchTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled, let self else { return }
        self.performSearch()
    }
}
```

**Batch property updates** — Set all `@Observable` properties together to trigger one SwiftUI re-render.

**Two rules about what tells a view (2026-11-23, from the [State layer review](<../Reviews/State layer review 2026-11-22.md>)):**
- *Equal values don't notify.* The `@Observable` setter stores a value equal to the old one and tells no one (`!=` for Equatable values, `!==` for class references, element by element for arrays). Apple documents none of this; it was read in the Xcode 27.2 SDK and is pinned by tests. An array of Core Data objects compares by identity, so re-assigning the same students after one was renamed sends nothing. A store that must redraw its readers after an edit writes its backing value inside `withMutation(keyPath:)`, which always notifies (`RosterStore.refresh()`, pinned by `RosterStoreEditNotifiesTests`). The other side of the rule: a cache a view fills while it draws must be `@ObservationIgnored`, with a tracked counter beside it if a reset has to redraw (`ClassSubjectChecklistViewModel`'s lessons-per-sequence cache).
- *A value kept in UserDefaults gets one shared stamp.* Observation can't see UserDefaults, and a computed property on a model tells only that one instance's readers. A default that several screens show goes through one shared `@Observable` object that keeps no copy, registers each read with `access(keyPath:)` and wraps each write in `withMutation(keyPath:)` (`Backup/LastBackupStamp.swift`). Anything that writes the default behind its back has to tell it afterwards, as a restore does with `keep(atLeast:)`. The settings import (`SettingsExportService.importSettings`) still writes its keys straight to UserDefaults and tells no one, so a screen open during an import shows the new value on its next redraw.

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
- [ADRs/](<Decision records>) — Architecture decisions
- [CloudKit Guide](CloudKit/CLOUDKIT_GUIDE.md) — CloudKit setup

## Layers, concurrency and persistence (moved from CLAUDE.md, 2026-10-04)

Moved verbatim from `Cosmic Daybook/CLAUDE.md` on 2026-10-04 so that file keeps only a pointer and the few rules a session needs before touching this area. These are still rules: follow them.

**MVVM with Services pattern:**
- **Views** — SwiftUI views using `@FetchRequest` for data binding
- **ViewModels** — `@Observable @MainActor` classes for complex state
- **Services** — Business logic operations (50+ services)
- **Models** — `NSManagedObject` subclasses with `CD` prefix (76 entities)

**Data access has two layers, not three.** `Repositories/*` own per-entity writes and typed reads (`fetch(id:)`, `StudentRepository.fetchStudents(ids:)`, `LessonRepository.fetchLessons(byArea:)`); `Services/DataQueryService` owns the read helpers that span entities or apply roster policy (`fetchAllStudents(excludeTest:excludeWithdrawn:sortBy:)`, `fetchAllLessons(sortBy:)`, presented assignments, open work). View models and services call one of those instead of hand-rolling a whole-table `CDFetchRequest`, and keep a caller-specific sort or filter at the call site rather than adding a variant to the layer. A read that is really per-student is scoped there (`SequenceStandingLoader`, predicates on the student's ids), never widened to the table.

**Concurrency:** Swift 6.0 strict concurrency throughout:
- `@Observable` on all ViewModels and stateful services (zero `ObservableObject`)
- `@MainActor` on all ViewModels, services, and repositories (~496 annotations)
- `async/await` throughout, actors for off-thread work
- `SWIFT_APPROACHABLE_CONCURRENCY` is on, so a `nonisolated async` function runs on its *caller's* actor. CPU-heavy work that must leave the main actor (decoding, tokenizing, digesting) is marked `@concurrent` — see `SearchIndexService.refreshContents` — and takes only `Sendable` arguments (a background `NSManagedObjectContext`, `Data`, value types), never a container or managed object
- `Sendable` types for cross-actor data

**Persistence:**
```
NSPersistentCloudKitContainer (CoreDataStack.swift)
├── Private store (private.sqlite) — the guide's own records, including the classroom records
│                                     they share out (70 private-only types + the 10 share types)
└── Shared store (shared.sqlite)  — the classroom share as accepted from someone else (10 types)
```
