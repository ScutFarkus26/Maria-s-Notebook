# CLAUDE.md - Maria's Notebook

## Project Overview

Maria's Notebook is a comprehensive teacher planning and classroom management app for iOS/macOS, built with SwiftUI and SwiftData. It helps educators manage students, lessons, work tracking, attendance, and classroom observations.

**Tech Stack:**
- Swift 5.9+ / SwiftUI
- SwiftData (with optional CloudKit sync)
- iOS 17.0+ / macOS 14.0+
- Xcode 15.0+

## Build & Run

```bash
# Open project
open "Maria's Notebook.xcodeproj"

# Build from command line
xcodebuild -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" -destination "platform=iOS Simulator,name=iPhone 15"

# Run tests
xcodebuild test -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" -destination "platform=iOS Simulator,name=iPhone 15"
```

## Project Structure

```
Maria's Notebook/
├── AppCore/          # App entry, initialization, root navigation
├── Models/           # SwiftData @Model definitions (17 models)
├── Services/         # Business logic layer (21+ services)
├── Components/       # Reusable SwiftUI components
├── Students/         # Student management module
├── Lessons/          # Lesson library module
├── Work/             # Work item tracking module
├── Presentations/    # Presentation scheduling
├── Planning/         # Planning & checklist tools
├── Attendance/       # Attendance tracking
├── Inbox/            # Follow-up inbox
├── Settings/         # App configuration
├── Backup/           # Backup & restore functionality
├── Utils/            # Extensions & utility functions
└── Tests/            # Unit & integration tests
```

## Architecture

**MVVM with Services pattern:**
- **Views** - SwiftUI views using `@Query`, `@Environment`
- **ViewModels** - Complex state management (16 ViewModels)
- **Services** - Business logic operations
- **Models** - SwiftData entities

**Data Access Patterns:**
```swift
// Direct query for simple views
@Query private var students: [Student]

// Filtered query
@Query(filter: #Predicate<WorkModel> { $0.statusRaw == "active" })

// ViewModel for complex state
@StateObject private var viewModel = TodayViewModel()
```

## Data Model

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Student   │────▶│LessonAssign.│◀────│   Lesson    │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       │                   ▼                   │
       │            ┌─────────────┐            │
       │            │    Note     │◀───────────┘
       │            └─────────────┘
       │                   ▲
       ▼                   │
┌─────────────┐     ┌─────────────┐
│ WorkModel   │────▶│  WorkStep   │
└─────────────┘     └─────────────┘
       │
       ├────▶ WorkParticipantEntity
       ├────▶ WorkCheckIn
       └────▶ WorkCompletionRecord

┌─────────────┐     ┌─────────────┐
│   Project   │────▶│ProjectSession│────▶ Note
└─────────────┘     └─────────────┘

┌─────────────┐          ┌─────────────────┐
│Presentation │────▶Note │AttendanceRecord │────▶ Note
└─────────────┘          └─────────────────┘
```

| Model | Purpose |
|-------|---------|
| `Student` | Student profiles (firstName, lastName, birthday, level) |
| `Lesson` | Curriculum lessons (name, subject, group, writeUp) |
| `LessonAssignment` | Links students to lessons with scheduling |
| `WorkModel` | Work items with lifecycle (active→review→complete) |
| `Note` | Observations with category and optional images |
| `Reminder` | EventKit-synced reminders |
| `AttendanceRecord` | Daily attendance tracking |

**CloudKit Compatibility Patterns:**
- UUID primary keys with default values (no `@Attribute(.unique)` — incompatible with CloudKit)
- Enums stored as raw `String` (e.g., `statusRaw`, `categoryRaw`)
- Foreign keys as `String` not `UUID`
- `modifiedAt` for conflict resolution
- Manual deduplication via `deduplicateAllModels` for CloudKit merge conflicts

## Key Services

| Service | Purpose |
|---------|---------|
| `DataMigrations` | Orchestrates all schema migrations |
| `LifecycleService` | Work lifecycle state management |
| `ReminderSyncService` | EventKit integration |
| `CalendarSyncService` | Calendar event display |
| `FollowUpInboxEngine` | Inbox and follow-up tasks |
| `BackupService` | Backup/restore operations |
| `WorkCompletionService` | Work completion logic |

## Testing

Tests are in `Tests/` directory:
- Unit tests for services and utilities
- Integration tests for features
- Mock classes in `Tests/Mocks/`

Run specific test:
```bash
xcodebuild test -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" -only-testing:"Maria's NotebookTests/WorkModelTests"
```

## Common Patterns

### Adding a New Model
1. Create `@Model` class in `Models/`
2. Use `String` for foreign keys (CloudKit compatibility)
3. Use `statusRaw`/`categoryRaw` pattern for enums
4. Add `modifiedAt` timestamp
5. Register in `ModelContainer` in `MariasNotebookApp.swift`

### Creating a New Feature Module
1. Create directory under root (e.g., `NewFeature/`)
2. Add Model, ViewModel, Views
3. Add Service if complex business logic needed
4. Add route to `AppRouter` for navigation

### SwiftData Queries
```swift
// Safe fetch with error handling
let results = modelContext.safeFetch(descriptor)

// Safe save
modelContext.safeSave()
```

## Important Files

- `AppCore/MariasNotebookApp.swift` - App entry point
- `AppCore/AppBootstrapper.swift` - Startup migrations
- `AppCore/RootView.swift` - Root navigation
- `Services/DataMigrations.swift` - Migration orchestration
- `Utils/ModelContext+SafeFetch.swift` - Safe data operations

## Code Conventions

- Use `@MainActor` for ViewModels
- Prefer composition over inheritance
- Use `private(set)` for ViewModel published properties
- Follow existing naming: `*ViewModel`, `*Service`, `*View`
- Keep views focused; extract complex logic to ViewModels
- Use `safeFetch`/`safeSave` extensions for data operations

## CloudKit Notes

- CloudKit sync is **disabled by default**
- Enable in Settings → CloudKit Status
- Container: `iCloud.DanielSDeBerry.MariasNoteBook`
- All models use string-based foreign keys for sync compatibility
