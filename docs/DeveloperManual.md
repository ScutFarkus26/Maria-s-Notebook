# Maria's Notebook — Developer Technical Reference Manual

**Version:** March 2026
**Platform:** iOS 17+ / macOS 14+
**Framework:** SwiftUI + SwiftData
**Language:** Swift 5.9+

---

# Part 1: Architecture Overview

## What the App Is

Maria's Notebook is a Montessori teacher's all-in-one classroom management app. It tracks students, lessons, presentations, student work, attendance, observations, scheduling, curriculum progression, and more. It runs natively on iOS and macOS using SwiftUI, with SwiftData for persistence and optional CloudKit for iCloud sync.

## High-Level Module Map

```
MariasNotebookApp (entry point)
    |
    v
AppBootstrapper (startup state machine)
    |
    v
RootView (main shell)
    |
    +-- AppRouter (navigation coordinator)
    +-- AppDependencies (dependency injection)
    |       |
    |       +-- RepositoryContainer
    |       |       +-- StudentRepository
    |       |       +-- LessonRepository
    |       |       +-- PresentationRepository
    |       |       +-- NoteRepository
    |       |       +-- ... (10+ repositories)
    |       |
    |       +-- Services
    |       |       +-- LifecycleService
    |       |       +-- FollowUpInboxEngine
    |       |       +-- ChatService + AnthropicAPIClient
    |       |       +-- ReminderSyncService
    |       |       +-- CloudKitSyncStatusService
    |       |       +-- BackupService
    |       |       +-- ToastService
    |       |       +-- ... (70+ services)
    |       |
    |       +-- Coordinators
    |               +-- SaveCoordinator
    |               +-- RestoreCoordinator
    |
    +-- Feature Views
            +-- TodayView (daily dashboard)
            +-- StudentsListView / StudentDetailView
            +-- LessonsListView / LessonDetailView
            +-- WorkListView / WorkDetailView
            +-- AttendanceView
            +-- PlanningViews (agenda, checklist, projects)
            +-- InboxView
            +-- SettingsView
            +-- ... (40+ feature views)
```

## Architecture Pattern: MVVM + Services

The app follows a layered MVVM architecture with a service layer:

```
SwiftUI View
    |  Binds to (via @Observable or @Query)
    v
ViewModel (@Observable, @MainActor)
    |  Calls methods on
    v
Service (business logic, @MainActor)
    |  Uses for data access
    v
Repository (type-safe CRUD, uses SaveCoordinator)
    |  Reads/writes via
    v
SwiftData ModelContext
    |  Syncs via (optional)
    v
CloudKit (iCloud)
```

**When to use each layer:**

- **View with @Query**: Simple list screens where the data maps directly to what's displayed. No transformation needed.
- **View with ViewModel**: Screens that combine multiple data sources, compute derived state, or need complex filtering/sorting. Examples: TodayView, GiveLessonViewModel.
- **Service**: Reusable business logic called from multiple ViewModels or other services. Examples: LifecycleService (work state transitions), FollowUpInboxEngine (inbox categorization).
- **Repository**: Type-safe CRUD operations for a single model. Wraps SwiftData queries with error handling and SaveCoordinator integration.

---

# Part 2: App Lifecycle

## Entry Point

**File:** `AppCore/MariasNotebookApp.swift`

The `@main` struct `MariasNotebookApp` conforms to `App`. Its `init()` runs synchronously before any UI renders.

### Synchronous Init (`AppBootstrapping.performInitialSetup()`)

This runs first and handles:

1. Registers default UserDefaults (CloudKit sync enabled by default)
2. Disables CloudKit during XCTest runs
3. Starts performance monitoring (stutter detection for frames >100ms)
4. Configures SQLite environment variables for Debug builds
5. Initializes `SaveCoordinator.shared` and `RestoreCoordinator.shared`

### App Body

The body provides:

- A `WindowGroup` with the main content
- On macOS, additional `Window` groups for detail views (Work, Student, Lesson windows opened via `openWindow`)
- The `ModelContainer` is injected as an environment object
- `SaveCoordinator`, `RestoreCoordinator`, `ErrorCoordinator`, `AppRouter`, and `AppDependencies` are injected into the environment

### Async Bootstrap (`.task` modifier)

After the UI appears (showing a splash screen), the `.task` block runs:

```
AppBootstrapper.bootstrap(modelContainer:)
    |
    +-- State: .initializingContainer
    |   +-- Set up AppCalendar with correct timezone
    |   +-- Migrate lesson files to iCloud Drive (one-time)
    |
    +-- State: .migrating
    |   +-- Run quick migrations (attendance types, GroupTrack defaults)
    |   +-- Initialize ReminderSyncService (macOS only)
    |   +-- Register for CloudKit remote notifications
    |
    +-- State: .ready (UI unblocks here)
    |
    +-- Background Task (off main thread):
        +-- Data normalization
        +-- Relationship backfills
        +-- Deduplication (CloudKit conflict cleanup)
        +-- Integrity repairs (probabilistic, ~10% of launches)
```

### First Launch vs. Subsequent Launch

| Step | First Launch | Subsequent Launch |
|------|-------------|-------------------|
| `performInitialSetup()` | Registers all defaults | No-op (defaults exist) |
| Onboarding check | Shows `OnboardingView` | Skips to `RootView` |
| Lesson file migration | Migrates local files to iCloud | Skips (flag set) |
| Quick migrations | Runs all | Skips completed ones (flags) |
| Heavy migrations | Runs all | Runs only if needed |
| CloudKit setup | First sync pulls remote data | Incremental sync |

### Bootstrap State Machine

```swift
enum BootstrapState {
    case idle
    case initializingContainer
    case migrating
    case ready
}
```

The splash screen checks `bootstrapper.state != .ready` to decide whether to show the loading UI.

---

# Part 3: Navigation System

## AppRouter

**File:** `AppCore/AppRouter.swift`

`AppRouter` is an `@Observable @MainActor` singleton that coordinates all navigation. Views access it via `@Environment(\.appRouter)`.

### Sheet Destinations

```swift
enum NavigationDestination: Identifiable {
    case newLesson(defaultSubject, defaultGroup)
    case importLessons
    case importStudents
    case newStudent
    case createBackup
    case restoreBackup
    case newWork
    case openAttendance
    case openStudentDetail(UUID)
    case quickActions
}
```

A view presents sheets by setting `appRouter.navigationDestination`.

### Root Navigation Items

```swift
enum NavigationItem: String, CaseIterable {
    case today
    case students, lessons, attendance
    case planningAgenda, planningWork, planningProjects, planningChecklist
    case supplies, procedures, todos, notes
    case community, schedules, issues, resources
    case askAI, logs, settings
    // ... 45+ items
}
```

Navigation happens by setting `appRouter.selectedNavItem = .students`.

### Special Routing

- **Plan Lesson Request:** `appRouter.planLessonRequest = PlanLessonRequest(studentID: id, date: date)` — triggers the lesson planning flow with pre-filled context.
- **Restore Signals:** `appDataWillBeReplaced` / `appDataDidRestore` — used to show a blocking overlay during backup restoration.
- **Inbox Refresh:** `planningInboxRefreshTrigger` — a UUID that changes to signal the inbox to reload.

## RootView

**File:** `AppCore/RootView.swift` (split across multiple files)

### Layout Structure

```
RootView
+-- Warning Banners (restore in progress, sync issues)
+-- Divider
+-- Main Content Area
|   +-- Sidebar (RootSidebar) — navigation items grouped by section
|   +-- Detail (RootDetailContent) — routes NavigationItem to the right view
+-- Overlays
    +-- QuickNoteGlassButton (floating action button)
    +-- TipView (TipKit feature hints)
    +-- Sheet presentations (new lesson, new student, etc.)
```

### Platform Differences

| Feature | iOS | macOS |
|---------|-----|-------|
| Layout | Adaptive tab bar | NavigationSplitView |
| Detail windows | Sheets | Separate windows via `openWindow` |
| Sidebar | Bottom tabs | Left sidebar |

### State Persistence

- `@SceneStorage("selectedNavItem")` — persists the selected tab across app launches
- `@AppStorage` — user preferences (test student visibility, agenda ordering)

## Quick Action System

### QuickNoteGlassButton

**File:** `AppCore/RootView/QuickNoteGlassButton.swift`

A floating action button with glass morphism styling. It supports three gestures:

| Gesture | Action |
|---------|--------|
| Double tap | Opens the Command Bar |
| Long press (400ms) | Expands the Pie Menu |
| Drag | Repositions the button (saved in UserDefaults) |

### Pie Menu

**File:** `AppCore/RootView/PieMenu.swift`

Five actions arranged in a circle (radius: 95pt):

| Action | Color | What it does |
|--------|-------|-------------|
| New Presentation | Blue | Creates a draft presentation |
| New Work Item | Orange | Opens work creation |
| Record Practice | Pink | Opens practice recording |
| New Todo | Green | Creates a todo |
| New Note | Purple | Opens note creation |

### Command Bar

**Files:** `Services/CommandBar/CommandBarTypes.swift`, `Services/CommandBar/LocalCommandParser.swift`, `Components/CommandBar/CommandBarSheet.swift`, `ViewModels/CommandBarViewModel.swift`

The command bar accepts natural language input and parses it into structured actions.

**Intent Detection Keywords:**

| Intent | Trigger Words |
|--------|--------------|
| Record Presentation | "gave", "presented", "showed", "demonstrated" |
| Assign Work | "assign", "assigned", "work" |
| Record Practice | "practice", "practiced", "practicing" |
| Add Note | "note", "observe", "noticed", "saw" |
| Add Todo | "todo", "remind", "task" |

**Parsing Pipeline:**

```
User input: "gave Sophia long division"
    |
    v
1. Detect intent via keyword → recordPresentation
2. Extract student names via StudentTagger → [Sophia]
3. Fuzzy-match lesson name → "Long Division" (lessonID)
4. Extract remaining text → (none)
5. Compute confidence → 0.8
    |
    v
Output: ParsedCommand {
    intent: .recordPresentation,
    studentIDs: [sophia_uuid],
    lessonID: long_division_uuid,
    confidence: 0.8
}
```

**Confidence Scoring:**
- Base: intent keyword confidence
- +0.2 if students matched
- +0.2 if lesson matched
- +0.1 bonus for short input (12 words or fewer)
- Capped at 1.0

The parser runs on an actor (`LocalCommandParser`) to keep the main thread free.

---

# Part 4: Dependency Injection

## AppDependencies

**File:** `AppCore/AppDependencies.swift`

An `@Observable @MainActor` class that serves as the central dependency container. Views access it via:

```swift
@Environment(\.dependencies) private var dependencies
```

### Lazy Initialization Pattern

Services are created on first access, not at startup:

```swift
private var _toastService: ToastService?
var toastService: ToastService {
    if _toastService == nil {
        _toastService = ToastService()
    }
    return _toastService!
}
```

This reduces launch time since most services aren't needed immediately.

### Service Groups

The container is split across extension files for organization:

| File | Services |
|------|----------|
| `AppDependencies.swift` | Core: repositories, toast, router, memory monitor, sync, command bar |
| `AppDependencies+AIServices.swift` | AnthropicAPIClient, ChatService, StudentAnalysisService, ReportGeneratorService |
| `AppDependencies+BackupServices.swift` | BackupService, EnhancedBackupService, RestoreCoordinator, CloudBackupService |

### Key Services Available

```swift
dependencies.repositories          // RepositoryContainer
dependencies.toastService          // Toast notifications
dependencies.appRouter             // Navigation
dependencies.reminderSync          // EventKit sync (macOS)
dependencies.calendarSync          // Calendar display
dependencies.groupTrackService     // Track management
dependencies.trackProgressResolver // Progress calculation
dependencies.memoryPressureMonitor // Cache management
dependencies.commandBarService     // Command bar
dependencies.dataQueryService      // Complex queries
```

---

# Part 5: Data Layer

## CloudKit Compatibility Rules

Every model in the app must follow these rules for CloudKit sync compatibility:

### Rule 1: String UUIDs, Not UUID Type

```swift
// CORRECT
@Attribute var studentID: String = ""

// WRONG - CloudKit can't handle UUID type reliably
@Attribute var studentID: UUID = UUID()
```

All foreign key references use `String` to store UUID values. Convert with `UUID(uuidString: studentID)` when needed.

### Rule 2: Raw String Enums

```swift
// CORRECT
@Attribute var statusRaw: String = WorkStatus.active.rawValue
var status: WorkStatus {
    get { WorkStatus(rawValue: statusRaw) ?? .active }
    set { statusRaw = newValue.rawValue }
}

// WRONG - CloudKit can't handle enums directly
@Attribute var status: WorkStatus = .active
```

The pattern is: store a `*Raw: String` property, provide a computed property for type-safe access.

### Rule 3: No @Attribute(.unique)

CloudKit creates duplicate records during merge conflicts. The `@Attribute(.unique)` constraint would crash. Instead, the app uses a deduplication service that runs periodically to clean up duplicates.

### Rule 4: External Storage for Large Data

```swift
@Attribute(.externalStorage) var pagesFileBookmark: Data?
```

Data larger than ~100KB should use external storage to avoid bloating the SQLite database.

### Rule 5: String Foreign Keys, Not @Relationship

```swift
// CORRECT - resilient to sync ordering
@Attribute var studentID: String = ""

// RISKY - can orphan if student syncs after work item
@Relationship var student: Student?
```

Relationships are resolved at query time, not enforced at the schema level. This prevents orphaning when CloudKit syncs records in unpredictable order.

### Rule 6: modifiedAt for Conflict Resolution

Every model includes:

```swift
@Attribute var modifiedAt: Date = Date()
```

This timestamp is used for last-writer-wins conflict resolution during CloudKit sync.

## Core Models

### Student

**File:** `Students/StudentModel.swift`

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `UUID` | Primary identifier |
| `firstName`, `lastName` | `String` | Name fields |
| `nickname` | `String` | Optional display name |
| `birthday` | `Date` | Birth date |
| `levelRaw` | `String` | `.lower` or `.upper` elementary |
| `enrollmentStatusRaw` | `String` | `.enrolled` or `.withdrawn` |
| `nextLessons` | `[String]` | Ordered list of upcoming lesson UUIDs |
| `dateStarted`, `dateWithdrawn` | `Date?` | Enrollment dates |
| `manualOrder` | `Int` | Custom sort position |
| `modifiedAt` | `Date` | CloudKit conflict resolution |

**Indexes:** `[levelRaw, manualOrder, modifiedAt, enrollmentStatusRaw]`

**Inverse Relationships:** `documents: [Document]?`

### Lesson

**File:** `Lessons/LessonModel.swift`

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `UUID` | Primary identifier |
| `name` | `String` | Lesson title |
| `subject`, `group` | `String` | Curriculum organization |
| `orderInGroup`, `sortIndex` | `Int` | Display ordering |
| `subheading` | `String` | Brief description |
| `writeUp` | `String` | Full presentation script |
| `materials` | `String` | Required materials |
| `purpose` | `String` | Educational purpose |
| `ageRange` | `String` | Target age range |
| `teacherNotes` | `String` | Personal notes |
| `suggestedFollowUpWork` | `String` | Follow-up activity ideas |
| `prerequisiteLessonIDs` | `String` | Comma-separated prerequisite UUIDs |
| `relatedLessonIDs` | `String` | Comma-separated related UUIDs |
| `greatLessonRaw` | `String?` | Cosmic education connection |
| `lessonFormatRaw` | `String` | `"standard"` or `"story"` |
| `parentStoryID` | `String?` | Parent story UUID for branching |
| `sourceRaw` | `String` | `"album"` or `"personal"` |
| `defaultWorkKindRaw` | `String?` | Preferred work type when assigned |
| `pagesFileBookmark` | `Data?` | External file reference (external storage) |
| `primaryAttachmentID` | `String?` | Primary attachment |

**Indexes:** `[subject, sortIndex], [name]`

### LessonAssignment (Presentation)

**File:** `Models/Presentation.swift`

This is the central scheduling and recording model. It represents the act of presenting a lesson to students.

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `UUID` | Primary identifier |
| `stateRaw` | `String` | State machine: `draft`, `scheduled`, `presented` |
| `scheduledFor` | `Date?` | When to present (nil for drafts) |
| `scheduledForDay` | `Date` | Start-of-day (denormalized for efficient date queries) |
| `presentedAt` | `Date?` | When actually presented (immutable record) |
| `lessonID` | `String` | Lesson UUID (indexed) |
| `lessonTitleSnapshot` | `String?` | Frozen lesson title at presentation time |
| `lessonSubheadingSnapshot` | `String?` | Frozen lesson subheading |
| `_studentIDsData` | `Data` | JSON-encoded student UUID array |
| `needsPractice` | `Bool` | Flag: student should practice |
| `needsAnotherPresentation` | `Bool` | Flag: re-present later |
| `followUpWork` | `String` | Follow-up work description |
| `notes` | `String` | Presentation notes |
| `manuallyUnblocked` | `Bool` | Override prerequisite checking |
| `trackID`, `trackStepID` | `String?` | Curriculum track context |

**State Machine:**

```
draft ──> scheduled ──> presented
  |                        |
  |   (immutable after     |
  |    this point)         |
  +──> presented           |
       (skip scheduling)   |
```

Once a presentation reaches `presented`, the `lessonTitleSnapshot` and `lessonSubheadingSnapshot` are frozen — even if the lesson is later edited, the historical record is preserved.

**Indexes:** `[stateRaw], [scheduledForDay], [presentedAt], [lessonID]`

### WorkModel

**File:** `Work/WorkModel.swift`

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `UUID` | Primary identifier |
| `title` | `String` | Work item name |
| `statusRaw` | `String` | `active`, `review`, `complete` |
| `kindRaw` | `String` | `practice`, `followUp`, `research`, `report` |
| `studentID` | `String` | Primary student UUID (indexed) |
| `lessonID` | `String` | Related lesson UUID |
| `presentationID` | `String?` | Originating presentation |
| `trackID`, `trackStepID` | `String?` | Track context |
| `dueAt` | `Date?` | Due date (indexed) |
| `assignedAt` | `Date` | When assigned |
| `completedAt` | `Date?` | When completed |
| `lastTouchedAt` | `Date` | Last interaction |
| `completionOutcomeRaw` | `String?` | Mastered, needs review, etc. |
| `scheduledNote` | `String?` | Scheduling notes |
| `sourceContextTypeRaw` | `String?` | Origin type (e.g., project session) |
| `sourceContextID` | `String?` | Origin ID |

**Relationships:**
- `participants: [WorkParticipantEntity]` — individual student progress in group work
- `checkIns: [WorkCheckIn]` — progress check-in records
- `steps: [WorkStep]` — step-by-step breakdown
- `unifiedNotes: [Note]` — attached observations

**Compound Indexes:** `[studentID, statusRaw], [statusRaw, dueAt], [presentationID], [completedAt]`

**Work Lifecycle:**

```
active ──> review ──> complete
  |                     |
  |  (teacher reviews)  +-- completionOutcome recorded
  |                     +-- completedAt set
  +──> complete         +-- track progress updated
       (skip review)
```

### Note

**File:** `Models/Note.swift`

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `UUID` | Primary identifier |
| `body` | `String` | Note content |
| `createdAt` | `Date` | When created (indexed) |
| `updatedAt` | `Date` | Last modified |
| `isPinned` | `Bool` | Pin to top of lists |
| `includeInReport` | `Bool` | Include in progress reports |
| `needsFollowUp` | `Bool` | Flag for action needed |
| `imagePath` | `String?` | Attached image path |
| `categoryRaw` | `String` | Legacy category (migration) |
| `tags` | `[String]` | Modern tags, format: `"Name\|Color"` |
| `reportedBy` | `String?` | Reporter type (e.g., "guide") |
| `reporterName` | `String?` | Reporter name |
| `scopeIsAll` | `Bool` | Indexed: true if scope is `.all` |
| `searchIndexStudentID` | `String?` | First student ID for search |

**Scope System:**

Notes use a flexible scoping system stored as JSON:

```swift
enum NoteScope: Codable {
    case all              // Applies to all students
    case student(UUID)    // Single student
    case students([UUID]) // Multiple students
}
```

Multi-student notes use a junction table (`NoteStudentLink`) to enable efficient per-student queries.

**Indexes:** `[createdAt], [searchIndexStudentID], [scopeIsAll]`

### Model Relationship Map

```
Student ←── studentID ──── LessonAssignment ───── lessonID ──→ Lesson
   |                            |                                |
   |                       presentationID                        |
   |                            |                                |
   +←── studentID ──── WorkModel ───── lessonID ────────────────+
   |                       |
   |                  participants → WorkParticipantEntity
   |                  checkIns    → WorkCheckIn
   |                  steps       → WorkStep
   |                  notes       → Note
   |
   +←── scope ──────── Note
   |
   +←── studentID ──── PracticeSession ── lessonID ──→ Lesson
   |
   +←── studentID ──── AttendanceRecord
   |
   +←── studentID ──── StudentMeeting
   |
   +←── enrollment ─── StudentTrackEnrollment ── trackID ──→ Track
                                                               |
                                                          steps → TrackStep
```

### Other Models (Quick Reference)

| Model | Purpose |
|-------|---------|
| `PracticeSession` | Records practice with quality, duration, method |
| `AttendanceRecord` | Daily present/tardy/absent per student |
| `TodoItem` | Teacher tasks with subtasks, due dates, tags |
| `TodoSubtask` | Checklist items within a todo |
| `Reminder` | EventKit-synced reminders |
| `Schedule` / `ScheduleSlot` | Weekly schedule templates |
| `CalendarEvent` | Calendar integration events |
| `NonSchoolDay` / `SchoolDayOverride` | Calendar exceptions |
| `StudentMeeting` | One-on-one meetings with outcomes |
| `MeetingTemplate` | Reusable meeting structures |
| `Project` / `ProjectSession` | Project-based learning |
| `Track` / `TrackStep` | Curriculum progression paths |
| `GroupTrack` | Group variations of tracks |
| `StudentTrackEnrollment` | Student enrollment in tracks |
| `Supply` / `SupplyTransaction` | Classroom inventory |
| `CommunityTopic` / `ProposedSolution` | Community discussions |
| `Document` | Learning resources |
| `Issue` / `IssueAction` | Issue tracking |
| `Procedure` | Standard procedures |
| `NoteTemplate` | Reusable observation templates |
| `LessonAttachment` | Files attached to lessons |
| `LessonPresentation` | Per-student mastery tracking |
| `AlbumGroupOrder` / `AlbumGroupUIState` | UI state persistence |
| `TodayAgendaOrder` | Custom agenda ordering |
| `DevelopmentSnapshot` | Progress snapshots |
| `PlanningRecommendation` | AI recommendations |
| `WorkCompletionRecord` | Historical completion tracking |

---

# Part 6: Repository Pattern

## RepositoryContainer

**File:** `Repositories/RepositoryContainer.swift`

A factory struct that creates type-safe repositories:

```swift
@MainActor struct RepositoryContainer {
    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    var students: StudentRepository { ... }
    var lessons: LessonRepository { ... }
    var presentations: PresentationRepository { ... }
    var notes: NoteRepository { ... }
    var noteTemplates: NoteTemplateRepository { ... }
    var attendance: AttendanceRepository { ... }
    var documents: DocumentRepository { ... }
    var meetings: MeetingRepository { ... }
    var reminders: ReminderRepository { ... }
    var projects: ProjectRepository { ... }
}
```

Each repository property creates a new instance with the shared context and save coordinator.

## Repository Protocol

Repositories conform to `SavingRepository`:

```swift
protocol SavingRepository {
    associatedtype Model: PersistentModel
    var context: ModelContext { get }
    var saveCoordinator: SaveCoordinator? { get }
}
```

### Typical Repository Methods

Using `StudentRepository` as an example:

```swift
struct StudentRepository: SavingRepository {
    // Fetch
    func fetchStudent(id: UUID) -> Student?
    func fetchStudents(predicate:, sortBy:) -> [Student]

    // Create
    func createStudent(firstName:, lastName:, ...) -> Student

    // Update
    func updateStudent(id:, firstName:, ...) -> Bool

    // Delete
    func deleteStudent(id:) -> Bool

    // Save (delegates to coordinator)
    func save(reason: String?) -> Bool
}
```

### LessonRepository Special Methods

```swift
// Story format support
func fetchRootStories() -> [Lesson]
func fetchChildStories(parentID: String) -> [Lesson]
```

## SaveCoordinator

**File:** `Backup/SaveCoordinator.swift`

Centralizes all save operations with batching and error handling.

### Key Behaviors

| Feature | Detail |
|---------|--------|
| Debounce | 500ms — coalesces multiple saves |
| Error capture | Stores last error message for UI display |
| Toast integration | Notifies user of save failures |
| Reason tracking | Optional reason string for debugging |
| Suppress alerts | Can silence alerts during migrations |

### Usage

```swift
// Direct save
saveCoordinator.save(context, reason: "Updated work progress")

// Scheduled save (debounced)
saveCoordinator.scheduleSave(context, reason: "Auto-save after edit")
```

### Error Handling Flow

```
1. Check context.hasChanges
2. Attempt context.save()
3. On failure:
   a. Extract NSError with underlying errors
   b. Append reason string if provided
   c. Store in lastErrorMessage
   d. Set showAlert = true (unless suppressed)
   e. Post toast notification
```

---

# Part 7: Service Layer

## Service Patterns

Services in this app follow these conventions:

- **`@MainActor`** — ensures thread safety for UI-related operations
- **`struct` for stateless services** — e.g., `LifecycleService` with static methods
- **`final class` for stateful services** — e.g., `ChatService` with session state
- **Protocol-based design** — enables testing (e.g., `MCPClientProtocol` for API client)
- **Registered in `AppDependencies`** — lazy-initialized on first access

## Key Services Deep Dive

### LifecycleService

**File:** `Services/LifecycleService.swift`

Manages work item state transitions and data integrity.

**Key Methods:**

| Method | Purpose |
|--------|---------|
| `safeFetch(_:using:)` | Returns empty array on error instead of throwing |
| `fetchWorkModel(presentationID:)` | Single fetch with `fetchLimit = 1` |
| `fetchAllWorkModels(presentationID:)` | Batch fetch by presentation |
| `upsertLessonPresentation(...)` | Idempotent create-or-update |
| `cleanOrphanedStudentIDs()` | Removes references to deleted students |

**Performance:** Uses predicates and fetch limits to minimize in-memory work. Never loads all records when only one is needed.

### FollowUpInboxEngine

**File:** `Services/FollowUpInboxEngine.swift`

Categorizes pending work and follow-ups into an actionable inbox.

**Inbox Buckets:**

| Bucket | Rule |
|--------|------|
| Overdue | Lesson follow-ups >7 days old; work items >5 days; reviews >3 days |
| Due Today | Items due today |
| Inbox | Items needing action but not yet overdue |
| Upcoming | Scheduled for the future |

**ComputeContext** — pre-built lookup tables for efficient categorization:

```swift
struct ComputeContext {
    let lessonsByID: [UUID: Lesson]
    let studentsByID: [UUID: Student]
    let openWorkModels: [WorkModel]
    let checkInsByWorkID: [UUID: [WorkCheckIn]]
    let nonSchoolDaysSet: Set<Date>
}
```

The engine respects non-school days when calculating "days since" for staleness.

**Sort Key:** `(bucket priority, age descending, child name, title)`

### ChatService + AnthropicAPIClient

**Files:** `Services/Chat/ChatService.swift`, `Services/AnthropicAPIClient.swift`

#### AnthropicAPIClient

Conforms to `MCPClientProtocol`. Provides two main methods:

```swift
func generateText(prompt:, systemMessage:, temperature:, maxTokens:, model:, timeout:) async throws -> String
func generateStructuredJSON(prompt:, systemMessage:, temperature:, maxTokens:, model:, timeout:) async throws -> String
```

- API key loaded from UserDefaults or keychain
- URL: `https://api.anthropic.com/v1/messages`
- Auto-cleans JSON responses (removes markdown code fences)

#### ChatService

Orchestrates AI chat sessions with classroom context.

**Session Flow:**

```
1. startSession() — build classroom snapshot (student names, lesson stats)
2. User sends message
3. Refresh snapshot if stale
4. Build question-specific context (Tier 2 enrichment)
5. Assemble system message with classroom context
6. Trim message history to token budget (max 10 messages)
7. Call API (temperature: 0.7, max tokens: 2048)
8. Stream response chunks to UI via onDelta callback
```

### ReminderSyncService (macOS)

**Purpose:** Two-way sync between the app's `Reminder` model and macOS Reminders (EventKit).

- Creates/updates/deletes reminders in both directions
- Respects EventKit permissions
- Handles conflict resolution via timestamps
- Only available on macOS (conditional compilation)

### CloudKitSyncStatusService

**File:** `Services/CloudKitSyncStatusService.swift`

Monitors iCloud sync health and exposes observable state.

**Observable Properties:**

```swift
var isSyncing: Bool
var lastSuccessfulSync: Date?
var lastSyncError: String?
var syncHealth: SyncHealth
var isNetworkAvailable: Bool
var isICloudAvailable: Bool
var pendingLocalChanges: Int
```

**Startup Behavior:**
- 15-second grace period — prevents false "offline" reports
- Observer setup delayed 2 seconds for CloudKit stabilization
- Persists last sync date in UserDefaults

**Sub-Services:**
- `NetworkMonitoring` — network reachability
- `SyncRetryLogic` — retry management
- `CloudKitHealthCheck` — health assessment

### EnhancedBackupService

**File:** `Backup/EnhancedBackupService.swift`

Full database backup and restore with multiple strategies.

**Export Modes:**

| Mode | Description |
|------|-------------|
| Standard | Original format (backward compatible) |
| Streaming | Recommended — better memory usage for large databases |
| Incremental | Only changed data since last backup |

**Features:**
- Optional password encryption
- Progress callbacks for UI
- Size estimation before export
- Automatic post-export verification
- Cloud sync conflict detection

**Export Flow:**

```
exportBackup(context, to: url, password:, mode:, progress:)
    |
    +-- Estimate backup size
    +-- Export data (streaming/incremental/standard)
    +-- Verify integrity if enabled
    +-- Return EnhancedBackupOperationSummary
```

### ToastService

**Purpose:** App-wide toast notifications with auto-dismiss.

```swift
toastService.show("Work completed", style: .success)
toastService.show("Save failed", style: .error)
```

Toasts auto-dismiss after a configurable delay and support stacking.

---

# Part 8: Feature Modules

## Today Hub

**Files:** `AppCore/TodayView/`, `ViewModels/TodayViewModel.swift`

The daily dashboard. Shows everything relevant to the selected date.

### TodayViewModel Outputs

| Property | What it shows |
|----------|--------------|
| `todaysLessons` | Presentations scheduled for selected date |
| `overdueSchedule` | Work items past their due date |
| `todaysSchedule` | Work items due today |
| `staleFollowUps` | Follow-ups that haven't been addressed |
| `agendaItems` | Unified, user-orderable agenda |
| `completedWork` | Finished work items |
| `todaysReminders` | Reminders due today |
| `overdueReminders` | Past-due reminders |
| `anytimeReminders` | Reminders with no due date |
| `todaysCalendarEvents` | Calendar events |
| `scheduledMeetings` / `completedMeetings` | Meetings |
| `attendanceSummary` | Attendance stats |
| `recentNotes` | Recent observations |

### Supporting Components

- **TodayCacheManager** — lookup dictionaries (`studentsByID`, `lessonsByID`, `workByID`) to avoid per-row database queries
- **TodayDataFetcher** — batches related database queries
- **TodayScheduleBuilder** — constructs the schedule from work data
- **TodayAttendanceLoader** — fetches and summarizes attendance
- **TodayNavigationService** — previous/next school day navigation (respects non-school days)
- **SchoolDayCache** — reusable cache for school day calculations

### Reload Strategy

- Debounced reloads when date or level filter changes
- Clears recent notes cache on date change to prevent unbounded memory growth

## Students Module

**Directory:** `Students/`

### Student Roster

- List view with filtering by level and enrollment status
- Sorting by name, manual order, or level
- Search by name (fuzzy matching)

### Student Detail View

Tabbed interface:

| Tab | Content |
|-----|---------|
| Presentations | Lesson history with mastery state per lesson |
| Notes | Observation timeline with filters |
| Files | Attached documents |
| History | Complete record across all models |
| Meetings | One-on-one meeting records |
| Tracks | Curriculum progression progress |

### AI Analysis

`StudentAnalysisService` sends student data to Claude for analysis — progress trends, patterns, recommendations.

## Lessons Module

**Directory:** `Lessons/`

### Lesson Library

Organized by subject and group. Each lesson detail view shows:

- Presentation script (writeUp)
- Materials, purpose, age range
- Teacher notes
- Prerequisite and related lessons (linked)
- Attachments and sample work
- Per-student progress (who's been presented, who's practicing, who's proficient)

### Lesson Formats

| Format | Description |
|--------|-------------|
| Standard | Traditional Montessori lesson |
| Story | Parent-child branching — a main story with chapter offshoots |

Story lessons use `parentStoryID` to create a tree structure. `fetchRootStories()` gets top-level stories; `fetchChildStories(parentID:)` gets branches.

### Import/Export

CSV import and export for bulk lesson management. `LessonFileStorage` handles file attachments with iCloud Drive integration.

## Work Module

**Directory:** `Work/` (74 files)

The largest module. Manages the complete lifecycle of student work items.

### Work Creation Sources

| Source | How work is created |
|--------|-------------------|
| Presentation | Automatically when a lesson is presented with follow-up work |
| Manual | Teacher creates directly |
| Inbox | From follow-up recommendations |
| Project | From project session assignments |
| Track | From track step completion |

### Work Check-Ins

`WorkCheckIn` records periodic progress notes. Check-in style can be:

- **Individual** — per-student in group work
- **Group** — single check-in for all participants
- **Flexible** — either style

### Multi-Student Work

`WorkParticipantEntity` tracks individual student progress within a group work item. Each participant can have their own completion state.

### Practice Sessions

`PracticeSession` records practice with:
- Quality metric (rating)
- Duration
- Method (independent, partnered, etc.)
- Partnership tracking for group practice

### PDF Rendering

`WorkPDFRenderer` generates printable PDFs of work items — useful for physical classroom records.

## Presentations Module

**Directory:** `Presentations/`

### Scheduling Calendar

Visual calendar for planning when to present lessons. The blocking algorithm prevents over-scheduling by checking:

- How many presentations are already scheduled for a day
- Whether prerequisite lessons have been completed

### State Machine

```
draft → scheduled (set scheduledFor date)
scheduled → presented (set presentedAt, freeze snapshots)
draft → presented (skip scheduling, direct recording)
```

### Mastery Tracking

`LessonPresentation` tracks per-student mastery:

```
presented → practicing → readyForAssessment → proficient
```

`masteredAt` records when proficiency was achieved.

## Attendance Module

**Directory:** `Attendance/`

- **Daily grid** — mark present/tardy/absent per student
- **Monthly view** — calendar heatmap of attendance
- **Tardy reports** — analytics on tardiness patterns
- **Email** — send attendance summaries to families

## Planning Module

**Directory:** `Planning/`

Multiple planning views:

| View | Purpose |
|------|---------|
| Agenda | Drag-and-drop lesson scheduler |
| Checklist | Class-wide subject tracking |
| Open Work | All active work items |
| Projects | Project-based learning management |
| Progression | Long-term curriculum mapping |
| Curriculum Balance | Subject coverage analysis |
| Classroom Jobs | Job rotation management |

## Inbox Module

**Directory:** `Inbox/`

Powered by `FollowUpInboxEngine`. Shows items needing attention in smart buckets:

```
Overdue → Due Today → Inbox → Upcoming
```

Quick actions: reschedule, mark complete, open detail, assign work.

## Notes Module

**Across:** `Models/Note.swift`, `Components/ObservationsView.swift`, `Components/NotesSection.swift`

Universal observation system. Notes can be:

- Scoped to all students, one student, or multiple students
- Categorized (academic, behavioral, social, emotional, health, attendance, general)
- Tagged with custom tags (format: `"TagName|Color"`)
- Pinned, flagged for follow-up, or marked for inclusion in reports
- Attached to work items via the `unifiedNotes` relationship

## Todos Module

**Across:** `Models/TodoItem.swift`, various views

Teacher task management with:

- **Smart parsing** (`TodoSmartParserService`) — natural language input
- **Subtasks** (`TodoSubtask`) — checklist within a todo
- **Tags** — categorization
- **Due dates** — with overdue tracking
- **Notifications** (`TodoNotificationService`) — local notifications
- **Export** (`TodoExportService`) — export to files

## Settings Module

**Directory:** `Settings/`

| Section | What it configures |
|---------|-------------------|
| School Calendar | Non-school days, overrides, schedule templates |
| Age Levels | Lower/upper elementary configuration |
| Reminders | EventKit sync (macOS) |
| Calendar | Calendar display settings |
| AI/Chat | API key, model selection, temperature |
| CloudKit | Sync enable/disable, status, deduplication |
| Data | Statistics, export, import, test student filtering |
| Templates | Meeting and note templates |

## Backup & Restore

**Directory:** `Backup/`

| Service | Role |
|---------|------|
| `BackupService` | Basic backup creation/restoration |
| `EnhancedBackupService` | Streaming, incremental, encryption |
| `BackupTransactionManager` | Atomic operations |
| `SelectiveRestoreService` | Restore specific data subsets |
| `CloudBackupService` | iCloud backup management |
| `BackupSharingService` | Share backups between devices/users |
| `SelectiveExportService` | Export specific model types |
| `BackupValidationService` | Verify backup integrity |
| `ChecksumVerificationService` | Hash verification |

## AI Chat

**Directory:** `Services/Chat/`

Chat with Claude about classroom data. The system:

1. Builds a classroom snapshot (student names, lesson counts, recent activity)
2. Enriches each question with relevant context (Tier 2)
3. Maintains conversation history (trimmed to token budget)
4. Streams responses in real-time

Additional AI services:
- `StudentAnalysisService` — progress analysis per student
- `LessonPlanningService` — AI-assisted lesson planning
- `ReportGeneratorService` — generate progress reports
- `DatabaseAnalysisService` — database statistics and insights

---

# Part 9: Utilities & Extensions

## Safe Fetch Pattern

**File:** `Utils/ModelContext+SafeFetch.swift`

The most important utility in the app. Every database query should use these:

```swift
// Returns empty array on error (never throws)
context.safeFetch(descriptor) -> [T]

// Returns nil on error or not found
context.safeFetchFirst(descriptor) -> T?

// Throws but deduplicates automatically (CloudKit fix)
context.fetchUnique(descriptor) -> [T]
```

`fetchUnique` uses the `.uniqueByID` collection extension to handle CloudKit-created duplicates.

## Collection Extensions

**File:** `Utils/Collection+Extensions.swift`

```swift
// Create lookup dictionary from identifiable array
[Student].dictionaryByID() -> [UUID: Student]

// More readable emptiness check
array.isNotEmpty -> Bool

// Split array by predicate
array.partitioned(by: predicate) -> (matching: [T], rest: [T])
```

## Date Utilities

**Files:** `Utils/Date+Normalization.swift`, `Utils/DateCalculations.swift`, `Utils/DateFormatters.swift`

- `AppCalendar.startOfDay(date)` — normalized date used everywhere for date comparisons
- `AppCalendar.adopt(timeZoneFrom:)` — timezone consistency
- Date formatters shared as static instances to avoid re-creation

## String Utilities

**Files:** `Utils/String+Extensions.swift`, `Utils/String+FuzzyMatch.swift`, `Utils/StringNormalization.swift`

- `.trimmed()` — removes leading/trailing whitespace
- Fuzzy matching for lesson name search in the command bar
- String normalization for consistent sorting

## Other Utilities

| File | Purpose |
|------|---------|
| `Array+SafeAccess.swift` | Bounds-checked array access |
| `Dictionary+InsertIfAbsent.swift` | Conditional dictionary insertion |
| `ModelContext+SafeSave.swift` | Safe save with error handling |
| `PredicateHelpers.swift` | Common predicate builders |
| `ValidationHelpers.swift` | Input validation |
| `CSVUtils.swift` | CSV parsing and generation |
| `AgeUtils.swift` | Age calculation from birthday |
| `MarkdownExporter.swift` | Export data as Markdown |
| `Double+Formatting.swift` | Number formatting |
| `View+ConditionalModifiers.swift` | Platform-specific view modifiers |
| `View+PlatformStyles.swift` | iOS vs macOS styling |
| `KeychainStore.swift` | Secure storage for API keys |
| `SyncedPreferencesStore.swift` | iCloud-synced preferences |
| `Logger+Extensions.swift` | Structured logging categories |
| `PerformanceLogger.swift` | Stutter detection (>100ms frames) |

---

# Part 10: How-To Reference

## Adding a New Model

1. **Create the model file** in the appropriate feature directory or `Models/`:

```swift
@Model final class MyNewModel {
    @Attribute var id: UUID = UUID()
    @Attribute var name: String = ""
    @Attribute var statusRaw: String = "active"  // Raw enum
    @Attribute var studentID: String = ""          // String UUID
    @Attribute var modifiedAt: Date = Date()       // CloudKit conflict resolution

    // Computed enum access
    var status: MyStatus {
        get { MyStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }
}
```

2. **Follow CloudKit rules**: string UUIDs, raw enums, no `@Attribute(.unique)`, `modifiedAt` timestamp.

3. **Add indexes** for frequently queried fields.

4. **Register in the app schema** — add to the model list in the schema configuration.

5. **Run migrations** if modifying an existing model's schema.

## Creating a Repository

1. **Create the repository file** in `Repositories/`:

```swift
@MainActor struct MyNewRepository: SavingRepository {
    typealias Model = MyNewModel
    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    func fetchAll() -> [MyNewModel] {
        let descriptor = FetchDescriptor<MyNewModel>(
            sortBy: [SortDescriptor(\.name)]
        )
        return context.safeFetch(descriptor)
    }

    func fetch(id: UUID) -> MyNewModel? {
        var descriptor = FetchDescriptor<MyNewModel>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    func save(reason: String? = nil) -> Bool {
        if let coordinator = saveCoordinator {
            return coordinator.save(context, reason: reason)
        }
        return (try? context.save()) != nil
    }
}
```

2. **Register in `RepositoryContainer`**:

```swift
var myNew: MyNewRepository {
    MyNewRepository(context: context, saveCoordinator: saveCoordinator)
}
```

## Adding a Service

1. **Create the service file** in `Services/`:

```swift
@MainActor struct MyNewService {
    let context: ModelContext

    func doSomething(...) -> Result {
        // Business logic here
        // Use safeFetch for queries
        // Use SaveCoordinator for saves
    }
}
```

2. **Register in `AppDependencies`**:

```swift
private var _myNewService: MyNewService?
var myNewService: MyNewService {
    if _myNewService == nil {
        _myNewService = MyNewService(context: modelContext)
    }
    return _myNewService!
}
```

3. **Use in views**:

```swift
@Environment(\.dependencies) private var dependencies
// ...
let result = dependencies.myNewService.doSomething(...)
```

## Building a New Screen

1. **Create a ViewModel** (if needed):

```swift
@Observable @MainActor final class MyScreenViewModel {
    private let context: ModelContext

    // Outputs
    private(set) var items: [MyModel] = []

    init(context: ModelContext) {
        self.context = context
    }

    func reload() {
        let descriptor = FetchDescriptor<MyModel>()
        items = context.safeFetch(descriptor)
    }
}
```

2. **Create the View**:

```swift
struct MyScreenView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: MyScreenViewModel?

    var body: some View {
        List { ... }
        .task {
            if viewModel == nil {
                viewModel = MyScreenViewModel(context: context)
            }
            viewModel?.reload()
        }
    }
}
```

3. **For simple lists**, skip the ViewModel and use `@Query`:

```swift
struct SimpleListView: View {
    @Query(sort: \MyModel.name) private var items: [MyModel]

    var body: some View {
        List(items) { item in ... }
    }
}
```

4. **Register the navigation route** in `RootView+NavigationItem` and `RootDetailContent`.

## Adding a Command Bar Intent

1. **Add the intent** to `RecordIntent` in `CommandBarTypes.swift`:

```swift
case myNewIntent  // keyword triggers
```

2. **Add trigger keywords** in `LocalCommandParser.swift`:

```swift
// In the keyword families section
case "mytrigger", "myword": return .myNewIntent
```

3. **Add the action** to `CommandAction`:

```swift
case myNewAction(param: Type)
```

4. **Handle the action** in `CommandBarViewModel`.

## CloudKit Considerations Checklist

When modifying any model or adding new features:

- [ ] UUIDs stored as `String`, not `UUID`
- [ ] Enums stored as `*Raw: String` with computed property
- [ ] No `@Attribute(.unique)` constraints
- [ ] `modifiedAt: Date` field present
- [ ] Foreign keys are `String`, not `@Relationship`
- [ ] Large data uses `@Attribute(.externalStorage)`
- [ ] Arrays use JSON encoding (e.g., `CloudKitStringArrayStorage`)
- [ ] Deduplication handled gracefully (use `fetchUnique` or `uniqueByID`)

---

# Part 11: Configuration & Debugging

## CloudKit Configuration

- **Container:** `iCloud.DanielSDeBerry.MariasNoteBook`
- **Default:** Enabled (can be toggled in Settings)
- **Auto-disabled:** During XCTest runs
- **Sync strategy:** Automatic with `modifiedAt` last-writer-wins
- **Deduplication:** Periodic cleanup via `deduplicateAllModels()`
- **Health monitoring:** `CloudKitSyncStatusService` provides real-time status

## EventKit Permissions (macOS)

- Reminder sync requires user permission
- `ReminderSyncService` handles permission requests
- Calendar access separate from reminder access
- Conditional compilation: only available on macOS

## API Key Management

- Stored in UserDefaults or Keychain (`KeychainStore`)
- Configured in Settings > AI/Chat
- `APIUsageTracker` monitors quota consumption
- No API key shipped with the app — user provides their own

## Performance Monitoring

- **Stutter detection:** `PerformanceLogger` flags frames >100ms
- **SQLite logging:** Enabled in Debug builds via environment variables
- **Memory pressure:** `MemoryPressureMonitor` observes system memory and proactively clears caches
- **Migration diagnostics:** Logged to console, accessible in Settings

## Debugging Aids

| Tool | Purpose |
|------|---------|
| `Logger.app(category:)` | Structured logging with categories |
| `PerformanceLogger` | Frame timing and stutter detection |
| `SyncEventLogger` | CloudKit event logging |
| Settings > Data | Database statistics, export, integrity checks |
| Console.app | Filter by `MariasNotebook` subsystem |

## Build Configuration

| Requirement | Value |
|-------------|-------|
| Xcode | 15.0+ |
| Swift | 5.9+ |
| iOS | 17.0+ |
| macOS | 14.0+ |
| Frameworks | SwiftUI, SwiftData, CloudKit (optional), EventKit (macOS) |

## Code Standards

- **SwiftLint** enforced (0 violations)
- **`@MainActor`** on all ViewModels and UI-touching services
- **`private(set)`** for ViewModel published properties
- **Composition over inheritance** throughout
- **Safe operations** via extensions (`safeFetch`, `safeSave`)

---

# Appendix A: File Directory Map

```
Maria's Notebook/
+-- AppCore/
|   +-- MariasNotebookApp.swift          App entry point
|   +-- AppBootstrapper.swift            Startup state machine
|   +-- AppBootstrapping.swift           Synchronous init
|   +-- AppDependencies.swift            DI container
|   +-- AppRouter.swift                  Navigation coordinator
|   +-- RootView.swift                   Main shell
|   +-- RootView/
|       +-- PieMenu.swift                Floating action menu
|       +-- QuickNoteGlassButton.swift   Floating button
|       +-- RootSidebar.swift            Sidebar navigation
|       +-- RootDetailContent.swift      Content routing
|
+-- Models/
|   +-- Note.swift                       Universal observation
|   +-- Presentation.swift               Lesson scheduling
|   +-- Supply.swift                     Classroom inventory
|   +-- (other shared models)
|
+-- Students/
|   +-- StudentModel.swift               Student data model
|   +-- StudentsListView.swift           Roster view
|   +-- StudentDetailView.swift          Detail tabs
|   +-- Meetings/                        One-on-one meetings
|
+-- Lessons/
|   +-- LessonModel.swift               Lesson data model
|   +-- LessonsListView.swift           Library view
|   +-- LessonDetailView.swift          Detail view
|
+-- Work/
|   +-- WorkModel.swift                  Work data model
|   +-- (74 files for lifecycle, check-ins, practice, PDF, etc.)
|
+-- Presentations/                       Scheduling and recording
+-- Attendance/                          Daily tracking
+-- Planning/                            Scheduling and curriculum
+-- Inbox/                               Follow-up management
+-- Projects/                            Project-based learning
+-- Notes/                               Observation views
+-- Supplies/                            Inventory management
+-- Settings/                            App configuration
+-- Backup/                              Backup and restore
|
+-- Services/
|   +-- LifecycleService.swift           Work state machine
|   +-- FollowUpInboxEngine.swift        Inbox categorization
|   +-- AnthropicAPIClient.swift         Claude API
|   +-- CloudKitSyncStatusService.swift  Sync monitoring
|   +-- CommandBar/                      Natural language parsing
|   +-- Chat/                            AI chat orchestration
|   +-- (70+ service files)
|
+-- Repositories/
|   +-- RepositoryContainer.swift        Factory
|   +-- StudentRepository.swift
|   +-- LessonRepository.swift
|   +-- (10+ repositories)
|
+-- ViewModels/
|   +-- TodayViewModel.swift             Today hub state
|   +-- GiveLessonViewModel.swift        Lesson picker state
|   +-- CommandBarViewModel.swift        Command bar state
|
+-- Components/                          102+ reusable UI components
+-- Utils/                               57+ utility files
```

---

# Appendix B: Glossary

| Term | Meaning |
|------|---------|
| **Presentation** | The act of presenting a Montessori lesson to a student. Represented by `LessonAssignment`. |
| **Follow-up** | Work or re-presentation needed after an initial presentation. |
| **Check-in** | A progress note on an active work item (`WorkCheckIn`). |
| **Track** | A curriculum progression path — a sequence of steps a student moves through. |
| **Great Lesson** | One of the five Montessori "cosmic education" stories that frame the curriculum. |
| **Album** | A Montessori teacher's collection of lesson plans, organized by subject. |
| **Three-period lesson** | A Montessori teaching technique: introduction, recognition, recall. |
| **Scope (Note)** | Who a note applies to: all students, one student, or a specific group. |
| **Raw enum** | A string-stored enum value for CloudKit compatibility (e.g., `statusRaw`). |
| **Safe fetch** | A query wrapper that returns empty results instead of throwing on error. |
| **Pie Menu** | The circular action menu that appears on long-press of the floating button. |
| **Command Bar** | Natural language input for quick actions (presentations, work, notes, todos). |
