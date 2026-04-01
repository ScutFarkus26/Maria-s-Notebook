# CLAUDE.md - Maria's Notebook

## Project Overview

Maria's Notebook is a comprehensive teacher planning and classroom management app for iOS/macOS, built with SwiftUI. It helps Montessori educators manage students, lessons, work tracking, attendance, and classroom observations.

**Tech Stack:**
- Swift 6.0 / SwiftUI
- Core Data + NSPersistentCloudKitContainer (two-store architecture)
- iOS 26.0+ / macOS 26.0+
- Xcode 16+

## Build & Run

```bash
# Open project
open "Maria's Notebook.xcodeproj"

# Build from command line
xcodebuild -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" -destination "platform=iOS Simulator,name=iPhone 16"
```

## Project Structure

```
Maria's Notebook/
├── AppCore/          # App entry, initialization, root navigation
├── Models/           # NSManagedObject subclasses & extensions
├── Services/         # Business logic layer (50+ services)
├── ViewModels/       # Shared ViewModels (Today, GiveLesson, etc.)
├── Components/       # Reusable SwiftUI components
├── Utils/            # Extensions & utility functions
├── Repositories/     # Data access layer (14 repositories)
│
├── Students/         # Student profiles & meetings
├── Lessons/          # Lesson library, attachments, exercises
├── Work/             # Work items, check-ins, practice sessions
├── Presentations/    # Presentation scheduling
├── Attendance/       # Attendance tracking
├── Planning/         # Planning & checklist tools
├── Inbox/            # Follow-up inbox
│
├── Agenda/           # Calendar day/month grid views
├── Community/        # Community topics & solutions
├── GoingOut/         # Going Out planning
├── Issues/           # Issue tracking
├── Logs/             # Application logging
├── Procedures/       # Procedure documentation
├── Progression/      # Student progress tracking & analytics
├── Projects/         # Project management & sessions
├── Resources/        # Educational resources
├── Supplies/         # Supply inventory
├── Topics/           # Educational topics
├── TransitionPlanner/# Transition planning
├── PerpetualCalendar/# Calendar notes
│
├── Sharing/          # CloudKit sharing (classroom collaboration)
├── Backup/           # Backup & restore functionality
├── Settings/         # App configuration
├── Tests/            # In-app test suites
├── Docs/             # Documentation
└── MariasNotebook.xcdatamodeld/ # Core Data model (60 entities)
```

## Architecture

**MVVM with Services pattern:**
- **Views** — SwiftUI views using `@FetchRequest` for data binding
- **ViewModels** — `@Observable @MainActor` classes for complex state
- **Services** — Business logic operations (50+ services)
- **Models** — `NSManagedObject` subclasses with `CD` prefix (60 entities)

**Concurrency:** Swift 6.0 strict concurrency throughout:
- `@Observable` on all ViewModels and stateful services (zero `ObservableObject`)
- `@MainActor` on all ViewModels, services, and repositories (~496 annotations)
- `async/await` throughout, actors for off-thread work
- `Sendable` types for cross-actor data

**Persistence:**
```
NSPersistentCloudKitContainer (CoreDataStack.swift)
├── Private store (private.sqlite) — teacher-specific data (28 entity types)
└── Shared store (shared.sqlite)  — classroom-level data (35 entity types)
```

## Data Model

**60 entities** defined in `MariasNotebook.xcdatamodeld`.

**Core Models:**

| Model | Class | Purpose |
|-------|-------|---------|
| Student | `CDStudent` | Student profiles (firstName, lastName, birthday, level) |
| Lesson | `CDLesson` | Curriculum lessons with attachments & exercises |
| LessonPresentation | `CDLessonPresentation` | Presentation scheduling & history |
| LessonAssignment | `CDLessonAssignment` | Links students to lessons |
| WorkModel | `CDWorkModel` | Work items with lifecycle (active->review->complete) |
| Note | `CDNote` | Observations with tags, multi-student scoping |
| AttendanceRecord | `CDAttendanceRecord` | Daily attendance tracking |
| ClassroomMembership | `CDClassroomMembership` | Links teacher to classroom zone with role |

**Core Data Patterns:**
- Entity classes use `CD` prefix (e.g., `CDStudent`, `CDLesson`)
- No unique constraints (incompatible with CloudKit)
- Enums stored as raw `String` (e.g., `statusRaw`, `categoryRaw`)
- Foreign keys as `String` not `UUID`
- `modifiedAt` for conflict resolution
- All properties optional or have defaults
- Relationships use `NSSet` (cast to `Set<CDEntityType>` for iteration)
- Use `mutableSetValue(forKey:)` for relationship mutations

## Sharing Model

- **Lead Guide** — full read/write on all shared + private data
- **Assistant** — read all shared data, write AttendanceRecord/Note/WorkCheckIn only
- Shared data (35 types): Students, Lessons, Tracks, Procedures, Supplies, Schedules, Templates, etc.
- Private data (28 types): Notes, Work, Attendance, Todos, Projects, Meetings, etc.

## Code Conventions

- Use `@Observable @MainActor` for ViewModels (NOT `ObservableObject`)
- Use `@MainActor` for services and repositories
- Entity classes use `CD` prefix
- Prefer composition over inheritance
- Follow existing naming: `*ViewModel`, `*Service`, `*View`, `*Entity.swift`
- Keep views focused; extract complex logic to ViewModels
- Use `safeFetch`/`safeSave` extensions for data operations
- Use `async/await` and `Task.sleep(for:)` for delays (NOT `DispatchQueue`)
- Use `NSFetchRequest` + `NSPredicate` for queries (NOT `@Query` / `#Predicate`)
- Use `@FetchRequest` in views for reactive data binding

## Standards

- All code must pass SwiftLint (see `.swiftlint.yml`). A hook runs it automatically after edits.
- Follow Swift 6.0 strict concurrency rules.
- Follow Apple Core Data + CloudKit conventions.

## CloudKit Notes

- Container: `iCloud.DanielSDeBerry.MariasNoteBook`
- Two persistent stores: private (teacher data) + shared (classroom data)
- Schema changes must be additive-only after CloudKit deployment
- All models use string-based foreign keys for sync compatibility

## Backup System

- Format version: 13
- Encryption: AES-GCM-256, compression: LZFSE, signing: Ed25519
- Auto-backup on app quit with configurable retention (default: 10)
- Entity registry: `BackupEntityRegistry.swift`
