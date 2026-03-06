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
```

## Project Structure

```
Maria's Notebook/
├── AppCore/          # App entry, initialization, root navigation
├── Models/           # SwiftData @Model definitions (51 models across project)
├── Services/         # Business logic layer (70+ services)
├── ViewModels/       # Shared ViewModels (Today, GiveLesson, etc.)
├── Components/       # Reusable SwiftUI components
├── Utils/            # Extensions & utility functions
│
│── Students/         # Student profiles & meetings
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
├── Backup/           # Backup & restore functionality
├── Settings/         # App configuration
├── Docs/             # Documentation
└── Repositories/     # Repository management
```

## Architecture

**MVVM with Services pattern:**
- **Views** - SwiftUI views using `@Query`, `@Environment`
- **ViewModels** - Complex state management (24 ViewModels)
- **Services** - Business logic operations (70+ services)
- **Models** - SwiftData entities (51 @Model classes)

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

**Note** is the central hub — nearly all feature models have an inverse relationship to Note for observations/reflections.

**Core Models:**

| Model | Location | Purpose |
|-------|----------|---------|
| `Student` | Students/ | Student profiles (firstName, lastName, birthday, level) |
| `Lesson` | Lessons/ | Curriculum lessons with attachments & exercises |
| `LessonAssignment` | Models/Presentation.swift | Links students to lessons with scheduling |
| `WorkModel` | Work/ | Work items with lifecycle (active→review→complete) |
| `Note` | Models/ | Observations with category, tags, multi-student scoping |
| `NoteStudentLink` | Models/ | Junction table for multi-student note scoping |
| `Reminder` | Models/ | EventKit-synced reminders |
| `AttendanceRecord` | Attendance/ | Daily attendance tracking |

**Work Models:** WorkStep, WorkCheckIn, WorkParticipantEntity, WorkCompletionRecord, PracticeSession (all in Work/)

**Project Models:** Project, ProjectSession, ProjectAssignmentTemplate, ProjectRole, ProjectTemplateWeek, ProjectWeekRoleAssignment (in Projects/)

**Community Models:** CommunityTopic, ProposedSolution, CommunityAttachment (in Models/CommunityModels.swift)

**Curriculum Models:** Track, TrackStep, GroupTrack, StudentTrackEnrollment, LessonPresentation, LessonAttachment, SampleWork, SampleWorkStep

**Planning/Scheduling:** Schedule, ScheduleSlot, TodoItem, TodoSubtask, TodoTemplate, CalendarEvent, TodayAgendaOrder, NonSchoolDay, SchoolDayOverride, Procedure

**Other:** StudentMeeting, Issue, IssueAction, Document, DevelopmentSnapshot, MeetingTemplate, NoteTemplate, PlanningRecommendation, Supply, SupplyTransaction, AlbumGroupOrder, AlbumGroupUIState

**CloudKit Compatibility Patterns:**
- UUID primary keys with default values (no `@Attribute(.unique)` — incompatible with CloudKit)
- Enums stored as raw `String` (e.g., `statusRaw`, `categoryRaw`)
- Foreign keys as `String` not `UUID`
- `modifiedAt` for conflict resolution
- Manual deduplication via `deduplicateAllModels` for CloudKit merge conflicts

## Key Services

| Service | Location | Purpose |
|---------|----------|---------|
| `DataMigrations` | Services/ | Orchestrates all schema migrations |
| `LifecycleService` | Services/ | Work lifecycle state management |
| `ReminderSyncService` | Services/ | EventKit integration |
| `CalendarSyncService` | Services/ | Calendar event display |
| `FollowUpInboxEngine` | Services/ | Inbox and follow-up tasks |
| `BackupService` | Backup/ | Backup/restore operations |
| `WorkCompletionService` | Work/ | Work completion logic |
| `ChatService` | Services/Chat/ | AI chat functionality |
| `AnthropicAPIClient` | Services/ | Anthropic API integration |
| `LessonPlanningService` | Services/LessonPlanning/ | AI-assisted lesson planning |
| `CloudKitSyncStatusService` | Services/ | CloudKit sync monitoring |
| `GroupTrackService` | Services/ | Track/group management |
| `TodoSmartParserService` | Services/ | Smart todo parsing |

**Services subdirectories:** AI/, Chat/, LessonPlanning/, Migrations/

## Common Patterns

### Adding a New Model
1. Create `@Model` class in `Models/` (or feature directory)
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

- `AppCore/MariasNotebookApp.swift` - App entry point & ModelContainer
- `AppCore/AppBootstrapper.swift` - Startup migrations
- `AppCore/RootView.swift` - Root navigation
- `AppCore/AppRouter.swift` - Navigation routing
- `Services/DataMigrations.swift` - Migration orchestration
- `Utils/ModelContext+SafeFetch.swift` - Safe data operations

## Code Conventions

- Use `@MainActor` for ViewModels
- Prefer composition over inheritance
- Use `private(set)` for ViewModel published properties
- Follow existing naming: `*ViewModel`, `*Service`, `*View`
- Keep views focused; extract complex logic to ViewModels
- Use `safeFetch`/`safeSave` extensions for data operations

## Standards

- All code must pass SwiftLint (see `.swiftlint.yml`). A hook runs it automatically after edits.
- Follow latest Swift 5.9+ and Apple CloudKit conventions.

## CloudKit Notes

- CloudKit sync is **disabled by default**
- Enable in Settings → CloudKit Status
- Container: `iCloud.DanielSDeBerry.MariasNoteBook`
- All models use string-based foreign keys for sync compatibility
