# CLAUDE.md - Maria's Notebook

## Project Overview

Maria's Notebook is a comprehensive teacher planning and classroom management app for iOS/macOS, built with SwiftUI. It helps Montessori educators manage students, lessons, work tracking, attendance, and classroom observations.

**Tech Stack:**
- Swift 6.0 / SwiftUI
- Core Data + NSPersistentCloudKitContainer (migrating from SwiftData)
- iOS 17.0+ / macOS 14.0+
- Xcode 15.0+

**Rewrite in progress:** This branch (`rewrite/core-data-sharing`) is migrating from SwiftData to Core Data + NSPersistentCloudKitContainer to enable CloudKit sharing between lead guides and assistants. See `docs/REWRITE_PLAN.md` for the full plan.

## Build & Run

```bash
# Open project
open "Maria's Notebook.xcodeproj"

# Build from command line
xcodebuild -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" -destination "platform=iOS Simulator,name=iPhone 15"
```

## Project Structure

```
Maria's Notebook/
├── AppCore/          # App entry, initialization, root navigation
├── Models/           # Data model definitions (58 models across project)
├── Services/         # Business logic layer (50+ services)
├── ViewModels/       # Shared ViewModels (Today, GiveLesson, etc.)
├── Components/       # Reusable SwiftUI components
├── Utils/            # Extensions & utility functions
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
├── Chat/             # AI chat features
├── Community/        # Community topics & solutions
├── Issues/           # Issue tracking
├── Logs/             # Application logging
├── Procedures/       # Procedure documentation
├── Progression/      # Student progress tracking & analytics
├── Projects/         # Project management & sessions
├── Resources/        # Educational resources
├── Schedules/        # Schedule management
├── Supplies/         # Supply inventory
├── Topics/           # Educational topics
│
├── Sharing/          # CloudKit sharing (classroom collaboration) [NEW]
├── Backup/           # Backup & restore functionality
├── Settings/         # App configuration
├── Docs/             # Documentation
└── Repositories/     # Data access layer
```

## Architecture

**MVVM with Services pattern:**
- **Views** — SwiftUI views (migrating from `@Query` to `@FetchRequest`)
- **ViewModels** — `@Observable @MainActor` classes for complex state (~40 ViewModels)
- **Services** — Business logic operations (50+ services)
- **Models** — Migrating from SwiftData `@Model` to `NSManagedObject` subclasses (58 entities)

**Concurrency:** Swift 6.0 strict concurrency throughout:
- `@Observable` on all ViewModels and stateful services (zero `ObservableObject`)
- `@MainActor` on all ViewModels, services, and repositories
- `async/await` throughout, actors for off-thread work
- `Sendable` types for cross-actor data

**Persistence (target architecture):**
```
NSPersistentCloudKitContainer
├── Private store (private.sqlite) — teacher-specific data
└── Shared store (shared.sqlite)  — classroom-level data (via CKShare)
```

## Data Model

**58 entities** defined in `AppSchema.swift` (SwiftData) / `MariasNotebook.xcdatamodeld` (Core Data).

**Core Models:**

| Model | Location | Purpose |
|-------|----------|---------|
| `Student` | Students/ | Student profiles (firstName, lastName, birthday, level) |
| `Lesson` | Lessons/ | Curriculum lessons with attachments & exercises |
| `LessonAssignment` | Models/ | Links students to lessons with scheduling |
| `WorkModel` | Work/ | Work items with lifecycle (active→review→complete) |
| `Note` | Models/ | Observations with category, tags, multi-student scoping |
| `AttendanceRecord` | Attendance/ | Daily attendance tracking |
| `ClassroomMembership` | Sharing/ | Links teacher to classroom zone with role [NEW] |

**CloudKit Compatibility Patterns:**
- No unique constraints (incompatible with CloudKit)
- Enums stored as raw `String` (e.g., `statusRaw`, `categoryRaw`)
- Foreign keys as `String` not `UUID`
- `modifiedAt` for conflict resolution
- All properties optional or have defaults

## Sharing Model

- **Lead Guide** — full read/write on all shared + private data
- **Assistant** — read all shared data, write AttendanceRecord/Note/WorkCheckIn only
- Shared data: Students, Lessons, Tracks, Procedures, Supplies, Schedules, Templates
- Private data: Notes, Work, Attendance, Todos, Projects, Meetings

## Code Conventions

- Use `@Observable @MainActor` for ViewModels (NOT `ObservableObject`)
- Use `@MainActor` for services and repositories
- Prefer composition over inheritance
- Follow existing naming: `*ViewModel`, `*Service`, `*View`
- Keep views focused; extract complex logic to ViewModels
- Use `safeFetch`/`safeSave` extensions for data operations
- Use `async/await` and `Task.sleep(for:)` for delays (NOT `DispatchQueue`)

## Standards

- All code must pass SwiftLint (see `.swiftlint.yml`). A hook runs it automatically after edits.
- Follow Swift 6.0 strict concurrency rules.
- Follow Apple Core Data + CloudKit conventions.

## CloudKit Notes

- Container: `iCloud.DanielSDeBerry.MariasNoteBook`
- Two persistent stores: private (teacher data) + shared (classroom data)
- Schema changes must be additive-only after CloudKit deployment
- All models use string-based foreign keys for sync compatibility
