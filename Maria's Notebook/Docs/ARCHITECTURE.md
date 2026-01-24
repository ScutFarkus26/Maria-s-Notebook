# Architecture Guide

This document describes the architecture and design patterns used in Maria's Notebook.

## Overview

Maria's Notebook follows a modular architecture with clear separation of concerns:

- **SwiftUI** for the view layer
- **SwiftData** for persistence
- **MVVM** pattern for complex views
- **Service-oriented** backend for business logic

## Directory Structure

### Core Directories

| Directory | Purpose |
|-----------|---------|
| `AppCore/` | App entry point, bootstrapping, root navigation |
| `Models/` | SwiftData `@Model` definitions |
| `Services/` | Business logic, data operations, sync services |
| `Components/` | Reusable SwiftUI components |
| `ViewModels/` | View models for complex state management |
| `Utils/` | Extensions, helpers, and utilities |

### Feature Directories

| Directory | Purpose |
|-----------|---------|
| `Students/` | Student profiles, progress tracking, lessons |
| `Lessons/` | Lesson management, organization, imports |
| `Work/` | Work item lifecycle management |
| `Presentations/` | Presentation scheduling and history |
| `Planning/` | Checklists, agenda, planning tools |
| `Attendance/` | Daily attendance tracking |
| `Projects/` | Project templates, sessions, roles |
| `Inbox/` | Follow-up reminders and inbox |
| `Settings/` | App configuration and preferences |
| `Backup/` | Backup/restore functionality |

## App Lifecycle

### Startup Flow

```
App Launch
    │
    ├─► MariasNotebookApp.init()
    │       └─► Configure SwiftData container
    │       └─► Initialize CloudKit (if enabled)
    │
    ├─► AppBootstrapper.bootstrap()
    │       └─► Run data migrations
    │       └─► Backfill relationships
    │       └─► Initialize services
    │
    └─► RootView.body
            └─► Display main navigation
```

### Key Files

- `MariasToolboxApp.swift` - App entry point, container configuration
- `AppCore/AppBootstrapper.swift` - Startup migrations and initialization
- `AppCore/RootView.swift` - Root navigation container

## Navigation Architecture

### RootView Navigation

The app uses a pill-based navigation system with two layouts:

**Split View (iPad/Mac)**
- Sidebar navigation with detail content
- `NavigationSplitView` pattern

**Compact (iPhone)**
- Tab-based navigation
- `RootCompactTabs` component

### Navigation Items

```swift
enum NavigationItem {
    case today           // Dashboard
    case attendance      // Attendance tracking
    case note            // Quick note entry
    case students        // Student roster
    case lessons         // Lesson library
    case planningChecklist
    case planningAgenda
    case planningWork
    case planningProjects
    case community
    case logs
    case settings
}
```

### App Router

The `AppRouter` environment object handles programmatic navigation:

```swift
@Environment(\.appRouter) private var appRouter

// Navigate to a destination
appRouter.navigate(to: .openAttendance)
```

## Data Layer

### SwiftData Models

All persistence uses SwiftData `@Model` classes. See [DATA_MODELS.md](DATA_MODELS.md) for details.

**Key patterns:**
- UUID primary keys stored as `@Attribute(.unique)`
- Enum properties stored as raw strings for CloudKit compatibility
- Relationships marked optional for CloudKit
- Foreign keys stored as `String` (not `UUID`) for CloudKit

### Data Access Patterns

**Direct Query (Simple Views)**
```swift
@Query private var students: [Student]
```

**Filtered Query**
```swift
@Query(filter: #Predicate<WorkModel> { $0.statusRaw == "active" })
private var activeWork: [WorkModel]
```

**ViewModel Pattern (Complex Views)**
```swift
@StateObject private var viewModel = TodayViewModel()

// ViewModel fetches data efficiently
class TodayViewModel: ObservableObject {
    func reload(context: ModelContext) async { ... }
}
```

**DataLoader Pattern (Efficient Loading)**
```swift
let loader = InboxDataLoader(context: modelContext)
let data = try await loader.loadInboxItems()
```

## Service Layer

### Key Services

| Service | Purpose |
|---------|---------|
| `LifecycleService` | Work item lifecycle state transitions |
| `DataMigrations` | Schema migrations and data backfills |
| `BackupService` | Database backup and restore |
| `SyncedPreferencesStore` | iCloud KVS preference sync |
| `PhotoStorageService` | Image file management |
| `InboxDataLoader` | Efficient inbox data loading |
| `PlanningEngine` | Planning operations and scheduling |

### Service Access

Services are typically instantiated where needed or accessed via environment:

```swift
// Direct instantiation
let backupService = BackupService()

// Environment access
@Environment(\.modelContext) private var modelContext
```

## UI Patterns

### View Composition

Views are split into smaller files for maintainability:

```
StudentDetailView.swift          # Main view
StudentDetailComponents.swift    # Subcomponents
StudentDetailViewModel.swift     # State management
StudentDetailSheetModifiers.swift # Sheet presentations
```

### Reusable Components

Common components in `Components/`:

- `UnifiedNoteEditor` - Multi-context note editing
- `ObservationsView` - Note display with selection
- `DropZone` - Drag-and-drop targets
- `ToastOverlay` - Toast notifications
- `SearchField` - Debounced search input

### Sheet Presentations

Sheets follow a consistent pattern:

```swift
@State private var isShowingSheet = false

.sheet(isPresented: $isShowingSheet) {
    SheetContentView()
        .presentationDetents([.medium, .large])
}
```

### Error Handling

Use `SaveCoordinator` for consistent save error handling:

```swift
@Environment(\.modelContext) private var modelContext

private func save() {
    SaveCoordinator.save(context: modelContext)
}

// In view body
.saveErrorAlert()
```

## CloudKit Integration

### Configuration

CloudKit is configured but disabled by default:

```swift
// Enable via UserDefaults
UserDefaults.standard.set(true, forKey: "EnableCloudKitSync")
```

### CloudKit Compatibility

All models follow CloudKit best practices:
- Optional relationship arrays
- String-based foreign keys
- Enum values stored as raw strings
- External storage for large data

See [CLOUDKIT_COMPATIBILITY_REPORT.md](CloudKit/CLOUDKIT_COMPATIBILITY_REPORT.md) for details.

## Performance Patterns

### Async Backfill Operations

Long-running operations yield periodically:

```swift
func backfillRelationshipsIfNeeded() async {
    for (index, item) in items.enumerated() {
        // Process item
        if index % 5000 == 0 {
            await Task.yield()  // Prevent UI blocking
        }
    }
}
```

### Lazy Loading

Complex views load data on-demand:

```swift
@State private var relatedData: [Item] = []

.task {
    await loadRelatedData()
}

private func loadRelatedData() async {
    // Fetch only what's needed
}
```

### ID-Only Queries for Change Detection

Use lightweight queries for change detection:

```swift
@Query private var studentIDs: [UUID]  // Change detection only

// Load full objects on-demand
private func loadStudents(ids: [UUID]) { ... }
```

### Debouncing

Search fields use debouncing:

```swift
@State private var searchText = ""
@State private var debouncedSearchText = ""

.onChange(of: searchText) { _, new in
    // Debounce 250ms before applying
}
```

## Testing

### Debug Views

The `Tests/` directory contains debug and testing views:

- `CloudKitStatusView` - CloudKit sync status
- `TrackPopulationView` - Data population tools
- Various test views for feature development

### Preview Support

Views include preview providers:

```swift
#Preview {
    StudentDetailView(student: .preview)
        .previewEnvironment()
}
```

The `.previewEnvironment()` modifier sets up an in-memory SwiftData container.

## Best Practices

### Do

- Use SwiftData queries with predicates for filtering
- Split large views into smaller components
- Use ViewModels for complex state
- Follow CloudKit compatibility patterns
- Use `SaveCoordinator` for saves

### Don't

- Load entire tables when only a subset is needed
- Use unfiltered `@Query` in frequently-accessed views
- Block the main thread with synchronous operations
- Force unwrap optionals - use safe access patterns
- Store UUIDs directly in foreign key fields (use String)

## Related Documentation

- [DATA_MODELS.md](DATA_MODELS.md) - SwiftData model documentation
- [FEATURES.md](FEATURES.md) - Feature documentation
- [Optimization/](Optimization/) - Performance optimization guides
- [CloudKit/](CloudKit/) - CloudKit configuration
