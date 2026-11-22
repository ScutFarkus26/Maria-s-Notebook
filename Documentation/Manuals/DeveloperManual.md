# Cosmic Daybook — Developer Technical Reference Manual

**Version:** March 2026
**Platform:** iOS 27+ / macOS 27+
**Framework:** SwiftUI + Core Data
**Language:** Swift 6.0+

---

# Part 1: Architecture Overview

## What the App Is

Cosmic Daybook is a Montessori teacher's all-in-one classroom management app. It tracks students, lessons, presentations, student work, attendance, observations, scheduling, curriculum progression, and more. It runs natively on iOS and macOS using SwiftUI, with Core Data (NSPersistentCloudKitContainer) for persistence and optional CloudKit for iCloud sync.

## High-Level Module Map

```
CosmicDaybookApp (entry point)
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
    |       +-- Services
    |       |       +-- LifecycleService
    |       |       +-- AIClientRouter
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
            +-- PlanningViews (agenda, Groups) + ClassGridView (Checklist, Three Years, Children)
            +-- InboxView
            +-- SettingsView
            +-- ... (40+ feature views)
```

## Architecture Pattern: MVVM + Services

The app follows a layered MVVM architecture with a service layer:

```
SwiftUI View
    |  Binds to (via @Observable or @FetchRequest)
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
NSManagedObjectContext
    |  Syncs via (optional)
    v
CloudKit (iCloud)
```

**When to use each layer:**

- **View with @FetchRequest**: Simple list screens where the data maps directly to what's displayed. No transformation needed.
- **View with ViewModel**: Screens that combine multiple data sources, compute derived state, or need complex filtering/sorting. Examples: TodayView, GiveLessonViewModel.
- **Service**: Reusable business logic called from multiple ViewModels or other services. Example: LifecycleService (work state transitions).
- **Repository**: Type-safe CRUD operations for a single entity. Wraps Core Data queries with error handling and SaveCoordinator integration.

---

# Part 2: App Lifecycle

## Entry Point

**File:** `AppCore/CosmicDaybookApp.swift`

The `@main` struct `CosmicDaybookApp` conforms to `App`. Its `init()` runs synchronously before any UI renders.

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
- The Core Data stack (`NSPersistentCloudKitContainer`) is injected as an environment object
- `SaveCoordinator`, `RestoreCoordinator`, `ErrorCoordinator`, `AppRouter`, and `AppDependencies` are injected into the environment

### Async Bootstrap (`.task` modifier)

After the UI appears (showing a splash screen), the `.task` block runs:

```
AppBootstrapper.bootstrap(coreDataStack:)
    |
    +-- State: .initializingContainer
    |   +-- Set up AppCalendar with correct timezone
    |   +-- Migrate lesson files to iCloud Drive (one-time)
    |
    +-- State: .migrating
    |   +-- Run quick migrations (attendance types)
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
// AppCore/RootView/RootView+NavigationItem.swift
enum NavigationItem: String, Hashable, Identifiable, CaseIterable {
    case today, attendance
    case students, meetings, notes
    case planningAgenda, smallSequencePlanner, planningChecklist, planningCalendar, thisWeeksParsha
    case supplies, schedules
    case lessons, teachingAlbums
    case settings
    // Retired rows, kept so a saved raw value still decodes (each is an alias):
    case note, more, perpetualCalendar, orders, logs, curriculumMap, progressDashboard,
         lessonRecall, parshaCalendar, stories, procedures, bookClub, askAI,
         // Cut unused features (2026-11-21 and 22):
         parentReports, planningProjects, community, resourceLibrary, goingOut, todos
}
```

Navigation happens by setting `appRouter.selectedNavItem = .students`.

**Raw values are frozen.** They live in `@SceneStorage("RootView.selectedNavItem")`, so renaming one silently resets every device's selection. `NavigationGroupTests.rawValuesArePinned` holds every literal; a case that stops being a destination stays in the enum and is mapped by `NavigationItem.aliases` → `canonical` (`.perpetualCalendar → .planningCalendar`, `.note`/`.more`/`.askAI → .today`, `.logs → .notes`, `.curriculumMap`/`.progressDashboard`/`.lessonRecall → .planningChecklist`, `.parshaCalendar → .thisWeeksParsha`, `.orders → .supplies`; from the 2026-11 cuts `.parentReports → .students`, `.planningProjects`/`.community`/`.goingOut`/`.todos`/`.bookClub → .today`, `.resourceLibrary`/`.stories`/`.procedures → .lessons`). An alias whose replacement has views opens it on the right one: `NavigationItem.landing` gives a `ScreenLanding` (`AppCore/RootView/ScreenLanding.swift`: `.classGrid(ClassGridViewKind)`, `.parshaYearList`), which a saved scene or a router jump sets on `AppRouter.screenLanding` and the Class Grid or the Parsha screen takes once. `.lessonRecall` now lands on the Class Grid's usual view. A case that is removed outright is handled by `NavigationSelectionRestorer` (same file), the pure function that turns the saved raw value, the pre-`NavigationItem` `Tab` string, and the old Planning mode into today's destination.

### Navigation groups

`RootView.NavigationGroup` (`AppCore/RootView/RootView+NavigationGroup.swift`) is the single table that decides where every destination sits. The macOS sidebar (`RootSidebar`), the iPad sidebar and the iPhone tab bar plus its More list (`RootAdaptiveTabs`) all iterate it; nothing lists items by hand. Six groups, 15 rows, in order: Today (Today, Attendance), Children (Students, Meetings, Notes), Plan (Lessons & Work, Groups, Class Grid, Calendar, This Week's Parsha; its raw value is still `planning`, so an old collapsed state carries over), Classroom (Restock, Schedules; collapsed by default), Library (Lessons, Albums), System (Settings). No row hides any more (`NavigationRowVisibility.rowEntities` is empty; the mechanism stays for a future hideable row). `NavigationGroup.primaryTabs` is the iPhone bar — Today, Students, Attendance, Lessons & Work — and `secondaryGroups` is what "More" shows. `NavigationGroupTests` pins that every destination is in exactly one group, that the TabView lists each once, the group order, and every alias with the view it lands on.

The macOS sidebar persists each group's collapsed state under `UserDefaultsKeys.sidebarGroupExpanded(groupID)` and auto-expands the group holding a selection that arrives from outside the sidebar (a Go-menu shortcut, an album deep link, a restored selection), so nothing lands invisibly inside a collapsed Classroom.

### Special Routing

- **Plan Lesson Request:** `appRouter.planLessonRequest = PlanLessonRequest(studentID: id, date: date)` — triggers the lesson planning flow with pre-filled context.
- **Restore Signals:** `appDataWillBeReplaced` / `appDataDidRestore` — used to show a blocking overlay during backup restoration.
- **Inbox Refresh:** `planningInboxRefreshTrigger` — a UUID that changes to signal the inbox to reload.

## RootView

**File:** `AppCore/RootView/RootView.swift` (split across multiple files)

### Layout Structure

```
RootView
+-- Warning Banners (restore in progress, sync issues)
+-- Divider
+-- Main Content Area
|   +-- Sidebar (RootSidebar on macOS/visionOS, RootAdaptiveTabs on iOS) — rows from RootView.NavigationGroup
|   +-- Detail (RootDetailContent) — routes NavigationItem.canonical to the right view
+-- Overlays
    +-- QuickNoteGlassButton (floating action button)
    +-- TipView (TipKit feature hints)
    +-- Sheet presentations (new lesson, new student, etc.)
```

### Platform Differences

| Feature | iOS | macOS |
|---------|-----|-------|
| Layout | `TabView(.sidebarAdaptable)` — tab bar on iPhone, sidebar on iPad | NavigationSplitView |
| Detail windows | Sheets | Separate windows via `openWindow` |
| Sidebar | iPhone: Today, Students, Attendance, Lessons & Work, More; iPad: grouped sidebar | Grouped sidebar with persisted collapse state |

### State Persistence

- `@SceneStorage("selectedNavItem")` — persists the selected tab across app launches
- `@AppStorage` — user preferences (test student visibility, agenda ordering)

## Quick Action System

### QuickNoteGlassButton

**File:** `AppCore/RootView/QuickNoteGlassButton.swift`

A floating quick-capture button. Shown unless the guide turns it off (Settings ▸ General, or View ▸ Show Quick Capture Button on the Mac; `UserDefaultsKeys.quickCaptureButtonVisible`).

| Gesture | Action |
|---------|--------|
| Tap | Opens the Command Bar (quick capture) |
| Long press (400ms), slide, release | Expands the Pie Menu and runs the segment released on |
| Right-click (macOS) | Lists the five create actions |
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

**Files:** `CommandBar/Services/CommandBarTypes.swift`, `CommandBar/Services/LocalCommandParser.swift`, `CommandBar/Views/CommandBarSheet.swift`, `CommandBar/ViewModels/CommandBarViewModel.swift`

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
| `AppDependencies+AIServices.swift` | AIClientRouter, StudentAnalysisService, ReportGeneratorService, MonthlyReportDraftService, MeetingInsightsService |
| `AppDependencies+BackupServices.swift` | BackupService, EnhancedBackupService, RestoreCoordinator, CloudBackupService |

### Key Services Available

```swift
dependencies.toastService          // Toast notifications
dependencies.appRouter             // Navigation
dependencies.reminderSync          // EventKit sync (macOS)
dependencies.calendarSync          // Calendar display
dependencies.memoryPressureMonitor // Cache management
dependencies.commandBarService     // Command bar
dependencies.dataQueryService      // Complex queries
```

---

# Part 5: Data Layer

## CloudKit Compatibility Rules

Every entity in the app must follow these rules for CloudKit sync compatibility:

### Rule 1: String UUIDs, Not UUID Type

```swift
// CORRECT — String attribute in Core Data model
@NSManaged public var studentID: String

// WRONG - CloudKit can't handle UUID type reliably
@NSManaged public var studentID: UUID
```

All foreign key references use `String` to store UUID values. Convert with `UUID(uuidString: studentID)` when needed.

### Rule 2: Raw String Enums

```swift
// CORRECT
@NSManaged public var statusRaw: String
var status: WorkStatus {
    get { WorkStatus(rawValue: statusRaw) ?? .active }
    set { statusRaw = newValue.rawValue }
}

// WRONG - CloudKit can't handle enums directly
// (no enum attribute type in Core Data model editor)
```

The pattern is: store a `*Raw: String` property, provide a computed property for type-safe access.

### Rule 3: No Unique Constraints

CloudKit creates duplicate records during merge conflicts. Unique constraints would crash. Instead, the app uses a deduplication service that runs periodically to clean up duplicates.

### Rule 4: External Storage for Large Data

In the Core Data model editor, enable "Allows External Storage" for Binary Data attributes.

```swift
@NSManaged public var pagesFileBookmark: Data?
```

Data larger than ~100KB should use external storage to avoid bloating the SQLite database.

### Rule 5: String Foreign Keys, Not Core Data Relationships

```swift
// CORRECT - resilient to sync ordering
@NSManaged public var studentID: String

// RISKY - can orphan if student syncs after work item
// @NSManaged public var student: CDStudent?  (relationship)
```

Relationships are resolved at query time, not enforced at the schema level. This prevents orphaning when CloudKit syncs records in unpredictable order.

### Rule 6: modifiedAt for Conflict Resolution

Every entity includes:

```swift
@NSManaged public var modifiedAt: Date
```

This timestamp is used for last-writer-wins conflict resolution during CloudKit sync.

## Core Entities (60 Core Data entities)

### CDStudent

**File:** `Students/Models/StudentEntity.swift`

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

**Inverse Relationships:** `documents: [CDDocument]?`

### CDLesson

**File:** `Lessons/LessonEntity.swift`

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

### CDLessonAssignment (Presentation)

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

### CDWorkModel

**File:** `Work/Models/WorkModelEntity.swift`

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `UUID` | Primary identifier |
| `title` | `String` | Work item name |
| `statusRaw` | `String` | `active`, `review`, `complete` |
| `kindRaw` | `String` | `practice`, `followUp`, `research`, `report` |
| `studentID` | `String` | Primary student UUID (indexed) |
| `lessonID` | `String` | Related lesson UUID |
| `presentationID` | `String?` | Originating presentation |
| `dueAt` | `Date?` | Due date (indexed) |
| `assignedAt` | `Date` | When assigned |
| `completedAt` | `Date?` | When completed |
| `lastTouchedAt` | `Date` | Last interaction |
| `completionOutcomeRaw` | `String?` | Mastered, needs review, etc. |
| `scheduledNote` | `String?` | Scheduling notes |
| `sourceContextTypeRaw` | `String?` | Origin type (e.g., project session) |
| `sourceContextID` | `String?` | Origin ID |

**Relationships:**
- `participants: [CDWorkParticipant]` — individual student progress in group work
- `checkIns: [CDWorkCheckIn]` — progress check-in records
- `steps: [CDWorkStep]` — step-by-step breakdown
- `unifiedNotes: [CDNote]` — attached observations

**Compound Indexes:** `[studentID, statusRaw], [statusRaw, dueAt], [presentationID], [completedAt]`

**Work Lifecycle:**

```
active ──> review ──> complete
  |                     |
  |  (teacher reviews)  +-- completionOutcome recorded
  |                     +-- completedAt set
  +──> complete
       (skip review)
```

### CDNote

**File:** `Models/NoteEntity.swift`

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

Multi-student notes use a junction table (`CDNoteStudentLink`) to enable efficient per-student queries.

**Indexes:** `[createdAt], [searchIndexStudentID], [scopeIsAll]`

### Model Relationship Map

```
CDStudent ←── studentID ──── CDLessonAssignment ───── lessonID ──→ CDLesson
   |                              |                                   |
   |                         presentationID                           |
   |                              |                                   |
   +←── studentID ──── CDWorkModel ───── lessonID ───────────────────+
   |                       |
   |                  participants → CDWorkParticipant
   |                  checkIns    → CDWorkCheckIn
   |                  steps       → CDWorkStep
   |                  notes       → CDNote
   |
   +←── scope ──────── CDNote
   |
   +←── studentID ──── CDPracticeSession ── lessonID ──→ CDLesson
   |
   +←── studentID ──── CDAttendanceRecord
   |
   +←── studentID ──── CDStudentMeeting
```

### Other Entities (Quick Reference)

| Entity | Purpose |
|--------|---------|
| `CDPracticeSession` | Records practice with quality, duration, method |
| `CDAttendanceRecord` | Daily present/tardy/absent per student |
| `CDTodoItem` | Teacher tasks with subtasks, due dates, tags |
| `CDTodoSubtask` | Checklist items within a todo |
| `CDReminder` | EventKit-synced reminders |
| `CDSchedule` / `CDScheduleSlot` | Weekly schedule templates |
| `CDCalendarEvent` | Calendar integration events |
| `CDNonSchoolDay` / `CDSchoolDayOverride` | Calendar exceptions |
| `CDStudentMeeting` | One-on-one meetings with outcomes |
| `CDMeetingTemplate` | Meeting structures (built-in only; custom ones are kept but not shown) |
| `CDProject` / `CDProjectSession` | Project-based learning (kept, no screen) |
| `CDLessonSequenceSettings` | A sequence's progression rules |
| `CDSupply` / `CDSupplyTransaction` | Classroom inventory |
| `CDCommunityTopic` / `CDProposedSolution` | Community discussions (kept, no screen) |
| `CDDocument` | Learning resources (kept, no screen) |
| `CDIssue` / `CDIssueAction` | Issue tracking (kept, no screen) |
| `CDProcedure` | Standard procedures (kept, no screen) |
| `CDLessonAttachment` | Files attached to lessons |
| `CDLessonPresentation` | Per-student mastery tracking |
| `CDAlbumGroupOrder` / `CDAlbumGroupUIState` | UI state persistence |
| `CDTodayAgendaOrder` | Custom agenda ordering |
| `CDDevelopmentSnapshot` | Progress snapshots |

Entities of the cut features (Parent Reports' communications, Projects, Book Club, Community topics, Issues, Resources, Stories, Procedures, Going Out, custom meeting templates, and recall checks) are all still in the model, in backups and in sync; only their screens, services and Claude tools went (plan `docs/Plans/Plan - Cut unused features and close the lesson loop.md`). Entity files that lived in a removed folder moved to `Models/` (guardians to `Students/Guardians/`). Reads that protect kept data stay: launch repairs, dedups, `StudentDeletion`'s cleanup, note link fields, and the recall reads behind Class Grid rings, the curriculum map, readiness and mastery evidence. The last build with every feature is the git tag `retired/2026-11-cuts`.
| `CDPlanningRecommendation` | AI recommendations |
| `CDWorkCompletionRecord` | Historical completion tracking |

---

# Part 6: Repository Pattern

Repositories are small structs a view or service constructs directly with the
context it already holds (for example `StudentRepository(context:saveCoordinator:)`).
There is no central container; a repository exists only where a feature calls it.

## Repository Protocol

Repositories conform to `SavingRepository`:

```swift
protocol SavingRepository {
    associatedtype Entity: NSManagedObject
    var context: NSManagedObjectContext { get }
    var saveCoordinator: SaveCoordinator? { get }
}
```

### Typical Repository Methods

Using `StudentRepository` as an example:

```swift
struct StudentRepository: SavingRepository {
    // Fetch
    func fetchStudent(id: UUID) -> CDStudent?
    func fetchStudents(predicate:, sortBy:) -> [CDStudent]

    // Create
    func createStudent(firstName:, lastName:, ...) -> CDStudent

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
func fetchRootStories() -> [CDLesson]
func fetchChildStories(parentID: String) -> [CDLesson]
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
- **`final class` for stateful services** — e.g., `TideSyncService` with its run state
- **Protocol-based design** — enables testing (e.g., `MCPClientProtocol` for API client)
- **Registered in `AppDependencies`** — lazy-initialized on first access

## Key Services Deep Dive

### LifecycleService

**File:** `Work/Services/LifecycleService.swift`

Manages work item state transitions and data integrity.

**Key Methods:**

| Method | Purpose |
|--------|---------|
| `safeFetch(_:using:)` | Returns empty array on error instead of throwing |
| `upsertLessonPresentation(...)` | Idempotent create-or-update |
| `cleanOrphanedStudentIDs()` | Removes references to deleted students |

**Performance:** Uses predicates and fetch limits to minimize in-memory work. Never loads all records when only one is needed.

### AIClientRouter

**File:** `Services/AI/AIClientRouter.swift`

Conforms to `MCPClientProtocol` and sends every request to Apple Intelligence:
the on-device model first, then Private Cloud Compute when Settings → AI allows
it. See `docs/Technical notes/AI.md`.

It serves the generate calls: Parsha suggestions, meeting and student insights, note summaries. There is no chat; Ask AI was removed in the Simplify the app plan (Phase 1).

### ReminderSyncService (macOS)

**Purpose:** Two-way sync between the app's `CDReminder` entity and macOS Reminders (EventKit).

- Creates/updates/deletes reminders in both directions
- Respects EventKit permissions
- Handles conflict resolution via timestamps
- Only available on macOS (conditional compilation)

### CloudKitSyncStatusService

**File:** `Services/Sync/CloudKitSyncStatusService.swift`

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

**Files:** `Today/Views/`, `Today/ViewModels/TodayViewModel.swift`, `Today/Support/`

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
| `stillPracticingLines` | Presentation id → "Still practicing: Maya S (Bead Addition)" for each lesson not yet given with a child whose practice is still open (`TodayViewModel+StillPracticing.swift`, set in `reload`; read by `LessonListRow.stillPracticing`) |

### Supporting Components

- **TodayCacheManager** — lookup dictionaries (`studentsByID`, `lessonsByID`, `workByID`) to avoid per-row database queries
- **TodayDataFetcher** — batches related database queries
- **TodayScheduleBuilder** — constructs the schedule from work data
- **TodayAttendanceLoader** — fetches and summarizes attendance
- **SchoolCalendarService** — the app-wide school-day cache (`AppCore/`), kept per persistent store coordinator so Sample Class and My Class never answer for each other

There is no day pad card: `TodayViewDayPadSection`, `DayPadEditor`, `TodaySection.dayPad` and the Today button and menu item went on 2026-11-22. The day note is still the `CDDayPad` record, edited in the Calendar; its fetch moved to `PerpetualCalendar/TodayDataFetcher+DayPad.swift`, and `todayDayPadExpanded` stays on the backed-up preferences list. The Parent Reports section and `TodaySection.parentReports` are gone too.

The lesson-loop additions to Today live in `Today/Views/TodayView+QuickNote.swift` (`markGivenWithQuickNote`, `openLessonQuickNote(for:)`): the Next card's **Given — Quick Note** button, the same item in every unpresented row's context menu, and **Quick Note…** on a presented row. `ActiveSheet` gains `.lessonQuickNote(presentationID:)`. "Mark Presented Now" also records `LessonQuickNoteTarget.lastGivenID`.

### Reload Strategy

- Debounced reloads when date or level filter changes
- Clears recent notes cache on date change to prevent unbounded memory growth

## Students Module

**Directory:** `Students/`

The feature is organized by subdomain: `Roster/`, `Detail/`, `Models/`, `Files/`, `Import/`,
`Notes/`, `Presentations/`, `Progress/`, `Selection/`, `Printing/`, `Meetings/`, `Insights/`,
`Guardians/`, `YearPlan/`, and `LessonDetail/`. (The `Recall/` screens and the per-child report went on 2026-11-21; old recall checks are still read.)

### Student Roster

- `StudentsView` filters and sorts the workspace's live roster (`RosterStore.all`) in memory (`StudentsViewModel.filteredStudents`, pure and static); it never fetches the Student table itself. Each body pass builds one `RosterSnapshot` (visible enrolled children, the shown rows, former students, the scope chips with counts) and every pane reads it.
- Every row shows the same signals in every sort (`RosterSignals.swift`: `StudentSignals`, `RosterSignalRules`, `RosterSignalText`): presence today, school days since the last lesson (due at 7, Today's rule), last observed (stale at 14 days), birthday within 6 days. The sort only adds a labeled age or date.
- `StudentsViewModel` caches today's attendance and the lesson/observation facts (`StudentsViewModel+Caches.swift`) and rebuilds each only when its own inputs change: two `ManagedObjectChangeFlag`s (attendance; the table-cache entities) plus day turnover, checked by `refreshIfNeeded` after a debounced save or import that touches `signalInputEntities`. Count tokens are gone: they missed edits that left a count unchanged.
- iPhone/iPad: level sections, scope chips (All, Here, Due, levels with children), swipe actions Observe / Lesson. iPad and Mac show `ClassGlanceView` when no child is selected. Mac: scope bar + `StudentsTableView` (selection bound, column customization with Age/Birthday hidden by default) beside the record.

### Student Detail View

Tabbed interface:

| Tab | Content |
|-----|---------|
| Presentations | Lesson history with mastery state per lesson |
| Notes | Observation timeline with filters |
| Files | Attached documents |
| History | Complete record across all models |
| Meetings | One-on-one meeting records |
| Current Learning | Where the child stands in each sequence she is in the middle of, read from her presentations |

### AI Analysis

`StudentAnalysisService` sends student data to Apple Intelligence (through `AIClientRouter`) for analysis — progress trends, patterns, recommendations.

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

**Directory:** `Work/`

The largest module. Manages the complete lifecycle of student work items.

The feature is organized into `Agenda/`, `CheckIns/`, `Completion/`, `Detail/`, `Models/`,
`Practice/`, `SampleWork/`, `Steps/`, `Support/`, `Services/`, and `WorkCard/`.

### Work Creation Sources

| Source | How work is created |
|--------|-------------------|
| Presentation | Automatically when a lesson is presented with follow-up work |
| Manual | Teacher creates directly |
| Inbox | From follow-up recommendations |
| Project | From project session assignments (existing work only; the Projects screens were taken out) |

### Work Check-Ins

`CDWorkCheckIn` records periodic progress notes. Check-in style can be:

- **Individual** — per-student in group work
- **Group** — single check-in for all participants
- **Flexible** — either style

### Multi-Student Work

`CDWorkParticipant` tracks individual student progress within a group work item. Each participant can have their own completion state.

### Practice Sessions

`CDPracticeSession` records practice with:
- Quality metric (rating)
- Duration
- Method (independent, partnered, etc.)
- Partnership tracking for group practice

### PDF Rendering

`WorkPDFRenderer` generates printable PDFs of work items — useful for physical classroom records.

## Presentations Module

**Directory:** `Presentations/`

The feature is organized into `Assignments/`, `Planning/`, `Overview/`, `Workflow/`, and
`Services/`.

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

`CDLessonPresentation` tracks per-student mastery:

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
| Class Grid (`ClassGrid/`) | Checklist (class-wide subject tracking), Three Years and Children, over one engine (`ClassGridEngine`) |
| Open Work | All active work items |
| Classroom Jobs | Job rotation management |

## Notes Module

**Across:** `Models/NoteEntity.swift`, `Notes/Observations/`, `Notes/Editor/`, `Notes/QuickCapture/`

Universal observation system. Notes can be:

- Scoped to all students, one student, or multiple students
- Categorized (academic, behavioral, social, emotional, health, attendance, general)
- Tagged with custom tags (format: `"TagName|Color"`)
- Pinned, flagged for follow-up, or marked for inclusion in reports
- Tagged **to fill in** when saved as a lesson quick note (see Lesson Quick Notes below)
- Attached to work items via the `unifiedNotes` relationship

### Lesson Quick Notes

A quick note is an ordinary `CDNote` saved at the lesson, tagged `to fill in`. No schema change: the tag is a normal note tag.

- `Notes/QuickNote.swift`, `enum QuickNote`: `tagName` (`"to fill in"`), `tag` (the stored `"to fill in|Orange"` form), `save(text:presentation:students:context:now:) -> CDNote?` (trims; nil for empty text or a failed save, in which case the inserted note is deleted again; scope is the given students, else the presentation's children; `createdAt` is the lesson's `presentedAt`, else now; sets `lessonID` and `lessonAssignment`), `insert(...)` (the same without saving, for a caller that saves its own batch), `isWaiting(_:)`, `isTag(_:)`, `removingTag(from:)`, `waiting(from:before:in:)`.
- `update_observation` drops the tag when it replaces a note's body (`QuickNote.removingTag(from:)`).
- `Notes/LessonQuickNote.swift`: `LessonQuickNote` (`markGiven` marks the lesson presented and remembers it, `save(text:presentationID:context:)` goes through `QuickNote.save`, `target(lastGivenID:now:calendar:context:)` picks the menu command's lesson: the one just given today, else the first planned today and not given, else the one given today that changed last; `windowID = "quick-note"`; `givenTitle = "Given — Quick Note"`) and the `@Observable` singleton `LessonQuickNoteTarget` (`presentationID`, `openCount` bumps only when the lesson changes, `lastGivenID`).
- `Notes/LessonQuickNoteForm.swift`: the shared form, and `LessonQuickNoteSheet` for iPad and iPhone.
- `Notes/LessonQuickNoteWindow.swift` (macOS): a `Window("Quick Note", id: "quick-note")` with `.windowResizability(.contentSize)` and `.windowLevel(.floating)`, inside `DetailWindowGate` (internal, in `AppCore/Windows/DetailWindowScene.swift`), registered in `CosmicDaybookApp.swift`. `LessonQuickNoteCommands` adds File ▸ **Quick Note on the Lesson** (⌃⌘J; also in `KeyboardShortcutsHelpView`). `UtilityWindow` and a panel were ruled out (plan Apple guidance): the first hides when the app is inactive, and panels shouldn't take typing.

### Practice Timing and Warnings

`Work/Support/PracticeCheckInTiming.swift` (`enum PracticeCheckInTiming`) decides when practice comes back:

- `checkInDays(lessonID:givenOn:studentIDs:sequences:in:now:)` gives each child a day: **the school day before her next planned lesson in the same sequence, else 3 school days after the lesson**; never before the next school day after the lesson, and never before today.
- `scheduleCheckIns(forWorkFrom:on:in:)` gives each child's open work from that presentation one check-in on her day (it moves the earliest existing one earlier, or makes one).
- `followPlannedLessons(_:sequences:in:now:)` is the move-earlier rule: when a later lesson is planned or moved earlier, the earliest open check-in on each piece of a child's earlier work in that sequence moves to the school day before it, unless one already falls by then. It only ever moves a check-in earlier (a move to a later day doesn't call it), never before the first school day from today or the next school day after the work was set (`assignedAt`), never moves a due-date check (`WorkCheckInService.isDueDateCheck`), and leaves done check-ins alone. `PresentationDetailActions` calls it only when the day, lesson or children change, and `reschedule_presentation` only for a new day. It is called from `PresentationDetailActions` (roster and date edits), `WeekDayColumnDropDelegate` (week board drops), `ReadyToPresentSection+Actions.scheduleSelectionToday`, `PresentationSessionCommit.planNextLesson`, `YearPlanPromotionService` (auto-schedule), and, in chat, `schedule_presentation`, `reschedule_presentation` and `update_presentation_roster`.
- `WorkRepository.createWork` titles untitled follow-up work "Practice: <lesson>" or "Follow up: <lesson>"; chat reads print the lesson name when a title is empty.

Warnings come from `WorkToShowFirst` (`Presentations/Planning/`). When two lessons tie on `orderInSequence`, it falls back to sub-area order (sortIndex, then name), so sequences left at order 0 still warn. `WorkToShowFirst+Lines.swift` has `practicingLine` and `stillPracticingLine`. Pickers: `StudentPickerRow` gains `checkFirstReason`, `practicing` and `isCheckFirst`; **`isReady` now means ready with nothing to check first** (placement `.ready` holds both). `Query` gains `checkFirst` and `practicing`. `ReadyGroups.readiness(for:among:lessons:in:)` returns the ready children and the check-first reasons (`readyStudentIDs` wraps it), and `StudentPickerModel.practicing(for:among:lessons:in:)` feeds the **Practicing …** badge in `SchedulePresentationSheet` rows. Chat prints the same warning as a line (see `docs/Technical notes/MCP_SERVER.md`).

### Ways into Groups

`AppRouter.navigateToGroups(area:sequence:)` sets `pendingSequenceLadder`; `GroupsView` takes it once with `consumePendingSequenceLadder()` and opens that sequence's ladder (`.navigationDestination(item:)`). `ChecklistGroupsButton` (in `Lessons/Checklist/Views/ChecklistLensControls.swift`) sits beside the Class Grid lens on the Mac, iPad and iPhone (one sequence is a button, several are a menu), and Lessons & Work has **Groups** on Presentations ▸ Upcoming (through the per-window `quickCapture.go`). ⌘7 opens Groups (`NotebookCommands`, `KeyboardShortcutsHelpView`).

## To-do Module

**Across:** `Todos/Models/TodoItemEntity.swift`, `Todos/Views/`, `Todos/Support/`, `Todos/Services/`

There is no To-dos screen (taken out 2026-11-22; ⌘7 is Groups now). What stays: `EditTodoForm` (with a confirmed **Delete To-do**, via its `onDelete:` closure; the only delete path in the app), `NewTodoForm`, `TodoCompletionService`, `TodoRepeatRule`, Tide sharing, Today's to-do section, meetings' For Me to Do, and the Claude to-do tools. `TodoListFilter` is a caseless enum (`isOnToday`, `isDueOrPlanned`, `isDue`); The `todoTagOrder` and `todoHideCompleted` keys stay on the backed-up preferences list.

Teacher task management with:

- **Subtasks** (`CDTodoSubtask`) — checklist within a todo
- **Tags** — categorization
- **Due dates** — with overdue tracking

## Settings Module

**Directory:** `Settings/`

| Section | What it configures |
|---------|-------------------|
| School Calendar | Non-school days, overrides, schedule templates |
| Age Levels | Lower/upper elementary configuration |
| Reminders | EventKit sync (macOS) |
| Calendar | Calendar display settings |
| AI | Private Cloud Compute opt-in; lesson-planning prompt, temperature and timeout |
| CloudKit | Sync enable/disable, status, deduplication |
| Data | Statistics, export, import, test student filtering |

Settings has five categories (`SettingsCategory`: school year, classroom, look and feel, sync and backup, intelligence). A saved "templates" selection maps to `.schoolYear` through `SettingsCategory.aliases`. Meetings read only the built-in template (`BuiltInTemplateSeeder.meetingTemplate(from:)`: the active built-in, else any built-in).

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

## AI Services

**Directory:** `Services/AI/` (router and clients), with each feature's service beside its screen. Every call goes through `AIClientRouter` (see above); there is no chat feature.

AI services:
- `StudentAnalysisService` — progress analysis per student
- `LessonPlanningService` — AI-assisted lesson planning
- `MeetingInsightsService` — meeting insights

---

# Part 9: Utilities & Extensions

## Safe Fetch Pattern

**File:** `Utils/CoreData/NSManagedObjectContext+SafeFetch.swift`

The most important utility in the app. Every database query should use these:

```swift
// Returns empty array on error (never throws)
context.safeFetch(request) -> [T]

// Returns nil on error or not found
context.safeFetchFirst(request) -> T?

// Throws but deduplicates automatically (CloudKit fix)
context.fetchUnique(request) -> [T]
```

`fetchUnique` uses the `.uniqueByID` collection extension to handle CloudKit-created duplicates.

## Collection Extensions

**File:** `Utils/Extensions/Collection+Extensions.swift`

```swift
// Create lookup dictionary from identifiable array
[CDStudent].dictionaryByID() -> [UUID: CDStudent]

// More readable emptiness check
array.isNotEmpty -> Bool

// Split array by predicate
array.partitioned(by: predicate) -> (matching: [T], rest: [T])
```

## Date Utilities

**Files:** `Utils/Formatting/Date+Normalization.swift`, `Utils/Formatting/DateCalculations.swift`, `Utils/Formatting/DateFormatters.swift`

- `AppCalendar.startOfDay(date)` — normalized date used everywhere for date comparisons
- `AppCalendar.shared` — immutable Gregorian calendar on `TimeZone.autoupdatingCurrent`; the canon behind `\.calendar` and every non-view date computation
- Date formatters shared as static instances to avoid re-creation

## String Utilities

**Files:** `Utils/Formatting/String+Extensions.swift`, `Utils/Formatting/String+FuzzyMatch.swift`, `Utils/StringNormalization.swift`

- `.trimmed()` — removes leading/trailing whitespace
- Fuzzy matching for lesson name search in the command bar
- String normalization for consistent sorting

## Other Utilities

| File | Purpose |
|------|---------|
| `Array+SafeAccess.swift` | Bounds-checked array access |
| `NSManagedObjectContext+SafeSave.swift` | Safe save with error handling |
| `PredicateHelpers.swift` | Common NSPredicate builders |
| `ValidationHelpers.swift` | Input validation |
| `CSVUtils.swift` | CSV parsing and generation |
| `AgeUtils.swift` | Age calculation from birthday |
| `MarkdownExporter.swift` | Export data as Markdown |
| `Double+Formatting.swift` | Number formatting |
| `View+ConditionalModifiers.swift` | Platform-specific view modifiers |
| `View+PlatformStyles.swift` | iOS vs macOS styling |
| `SyncedPreferencesStore.swift` | iCloud-synced preferences |
| `Logger+Extensions.swift` | Structured logging categories |
| `PerformanceLogger.swift` | Stutter detection (>100ms frames) |

---

# Part 10: How-To Reference

## Adding a New Entity

1. **Add the entity in the Core Data model editor** (`CosmicDaybook.xcdatamodeld`) with attributes.

2. **Create the NSManagedObject subclass** in the appropriate feature directory or `Models/`:

```swift
public class CDMyNewEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var statusRaw: String
    @NSManaged public var studentID: String
    @NSManaged public var modifiedAt: Date

    // Computed enum access
    var status: MyStatus {
        get { MyStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    // Core Data creation pattern
    static func create(in context: NSManagedObjectContext) -> CDMyNewEntity {
        let entity = CDMyNewEntity(context: context)
        entity.id = UUID()
        entity.name = ""
        entity.statusRaw = "active"
        entity.studentID = ""
        entity.modifiedAt = Date()
        return entity
    }
}
```

2. **Follow CloudKit rules**: string UUIDs, raw enums, no unique constraints, `modifiedAt` timestamp.

3. **Add indexes** for frequently queried fields in the model editor.

4. **Register in the Core Data model** — add the entity to `CosmicDaybook.xcdatamodeld`.

5. **Add a lightweight migration** if modifying an existing entity's schema.

## Creating a Repository

1. **Create the repository file** in `Repositories/`:

```swift
@MainActor struct MyNewRepository: SavingRepository {
    typealias Entity = CDMyNewEntity
    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    func fetchAll() -> [CDMyNewEntity] {
        let request: NSFetchRequest<CDMyNewEntity> = CDMyNewEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDMyNewEntity.name, ascending: true)]
        return context.safeFetch(request)
    }

    func fetch(id: UUID) -> CDMyNewEntity? {
        let request: NSFetchRequest<CDMyNewEntity> = CDMyNewEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetchFirst(request)
    }

    func save(reason: String? = nil) -> Bool {
        if let coordinator = saveCoordinator {
            return coordinator.save(context, reason: reason)
        }
        return (try? context.save()) != nil
    }
}
```

2. **Construct it where it is used**, passing the caller's context and save coordinator.

## Adding a Service

1. **Create the service file** in `Services/`:

```swift
@MainActor struct MyNewService {
    let context: NSManagedObjectContext

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
        _myNewService = MyNewService(context: viewContext)
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
    private let context: NSManagedObjectContext

    // Outputs
    private(set) var items: [CDMyEntity] = []

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func reload() {
        let request: NSFetchRequest<CDMyEntity> = CDMyEntity.fetchRequest()
        items = context.safeFetch(request)
    }
}
```

2. **Create the View**:

```swift
struct MyScreenView: View {
    @Environment(\.managedObjectContext) private var context
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

3. **For simple lists**, skip the ViewModel and use `@FetchRequest`:

```swift
struct SimpleListView: View {
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDMyEntity.name, ascending: true)])
    private var items: FetchedResults<CDMyEntity>

    var body: some View {
        List(items) { item in ... }
    }
}
```

4. **Register the navigation route:** add the case to `RootView+NavigationItem` (the display name, icon and accessibility hint switches are exhaustive), place it in exactly one group in `RootView+NavigationGroup`, route it in `RootDetailContent`, and pin its raw value in `NavigationGroupTests.rawValuesArePinned`. Never rename an existing raw value.

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
- [ ] No unique constraints in the Core Data model
- [ ] `modifiedAt: Date` field present
- [ ] Foreign keys are `String`, not Core Data relationships
- [ ] Large data uses "Allows External Storage" in the model editor
- [ ] Arrays use JSON encoding (e.g., `CloudKitStringArrayStorage`)
- [ ] Deduplication handled gracefully (use `fetchUnique` or `uniqueByID`)

---

# Part 11: Configuration & Debugging

## CloudKit Configuration

- **Container:** `iCloud.DanielSDeBerry.MariasNoteBook`
- **Default:** Enabled (can be toggled in Settings)
- **Auto-disabled:** During XCTest runs
- **Sync strategy:** Automatic with `modifiedAt` last-writer-wins
- **Deduplication:** Periodic cleanup via `deduplicateAllEntities()`
- **Health monitoring:** `CloudKitSyncStatusService` provides real-time status

## EventKit Permissions (macOS)

- Reminder sync requires user permission
- `ReminderSyncService` handles permission requests
- Calendar access separate from reminder access
- Conditional compilation: only available on macOS

## API Keys

The app's AI is Apple Intelligence only and needs no API key. (Claude and
OpenAI keys were removed on 2026-09-26.)

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
| Console.app | Filter by `CosmicDaybook` subsystem |

## Build Configuration

| Requirement | Value |
|-------------|-------|
| Xcode | 16.0+ |
| Swift | 6.0+ |
| iOS | 26.0+ |
| macOS | 26.0+ |
| Frameworks | SwiftUI, Core Data (NSPersistentCloudKitContainer), CloudKit (optional), EventKit (macOS) |

## Code Standards

- **SwiftLint** enforced (0 violations)
- **`@MainActor`** on all ViewModels and UI-touching services
- **`private(set)`** for ViewModel published properties
- **Composition over inheritance** throughout
- **Safe operations** via extensions (`safeFetch`, `safeSave`)

---

# Appendix A: File Directory Map

```
Cosmic Daybook/
+-- AppCore/
|   +-- CosmicDaybookApp.swift          App entry point
|   +-- AppBootstrapper.swift            Startup state machine
|   +-- AppBootstrapping.swift           Synchronous init
|   +-- AppDependencies.swift            DI container
|   +-- AppRouter.swift                  Navigation coordinator
|   +-- RootView.swift                   Main shell
|   +-- RootView+NavigationItem.swift    NavigationItem, aliases, selection restore
|   +-- RootView+NavigationGroup.swift   The sidebar / tab grouping table
|   +-- RootView/
|       +-- PieMenu.swift                Floating action menu
|       +-- QuickNoteGlassButton.swift   Floating button
|       +-- RootSidebar.swift            macOS / visionOS sidebar
|       +-- RootAdaptiveTabs.swift       iPhone tab bar / iPad sidebar
|       +-- RootDetailContent.swift      Content routing
|
+-- Models/
|   +-- NoteEntity.swift                 Universal observation (CDNote)
|   +-- Presentation.swift               Lesson scheduling (CDLessonAssignment)
|   +-- SupplyEntity.swift               Classroom inventory (CDSupply)
|   +-- (other shared entity files)
|
+-- Students/
|   +-- Models/StudentEntity.swift       Student entity (CDStudent)
|   +-- Roster/                           Student roster, signals, class at a glance
|   +-- Detail/                           Student detail tabs and state
|   +-- Files/                            Student documents
|   +-- Import/                           CSV import workflow
|   +-- Notes/                            Student observation timeline
|   +-- Presentations/                    Student presentation workflow
|   +-- Progress/                         Curriculum progress and sequence standings
|   +-- Selection/                        Student picker UI
|   +-- Meetings/                        One-on-one meetings
|   |   +-- Services/                     Meeting insight generation
|   +-- Insights/Services/               Student analysis
|   +-- Guardians/                       Guardian entity, list and edit sheet (shown on the child's Overview)
|   +-- YearPlan/Services/               Year-plan promotion
|
+-- Lessons/
|   +-- LessonEntity.swift              Lesson entity (CDLesson)
|   +-- Library/LessonsRootView.swift   Library view
|   +-- Detail/LessonDetailView.swift   Detail view
|   +-- ViewModels/GiveLessonViewModel.swift  Lesson picker state
|   +-- Checklist/                       Checklist view's cells, selection, view model (Views/, Model/, ViewModels/)
|
+-- Work/
|   +-- Models/WorkModelEntity.swift     Work entity (CDWorkModel)
|   +-- Agenda/                           Work calendar and planning
|   +-- CheckIns/                         Progress check-ins
|   +-- Completion/                       Completion records and rules
|   +-- Detail/                           Work detail screen and state
|   +-- Practice/                         Practice sessions
|   +-- SampleWork/                       Sample-work capture
|   +-- Steps/                            Work-step editing
|   +-- Support/                          Scheduling, filtering, and data access
|   +-- Services/                         Lifecycle and PDF rendering
|   +-- WorkCard/                         Shared work card presentations
|
+-- Presentations/                       Scheduling and recording
|   +-- Assignments/                      Assignment detail and history
|   +-- Planning/                         Scheduling and blocking
|   +-- Overview/                         Presentation queues and filters
|   +-- Workflow/                         Presentation and follow-up workflow
|   +-- Services/                         Presentation splitting
+-- Attendance/                          Daily tracking
+-- ClassGrid/                           The Class Grid: Checklist, Three Years, Children
|   +-- Engine/                           ClassGridEngine (one ladder, one mark)
|   +-- ThreeYears/, Children/             The other two views
+-- CurriculumMap/                       Per-child Three-Year View on the student page, and its loader/store/types
+-- Groups/                              Groups page: cards, sequence ladder
+-- Logs/                                Attendance and Meetings log views (Attendance's List, Meetings' History)
+-- Planning/                            Scheduling and curriculum
|   +-- AIPlanning/LessonPlanning/        AI planning service and state
|   +-- Services/                         Next-lesson planning
+-- Today/                               Daily hub
|   +-- Views/                            Today screen and sections
|   +-- ViewModels/TodayViewModel.swift   Today hub state
|   +-- Support/                          Builders, loaders, caches, navigation
+-- Todos/                               Todo management
|   +-- Views/                            The to-do forms (new, edit with Delete) and the schedule picker
|   +-- Support/                          Today filters and scheduling
|   +-- Services/                         Completion and repeat rules
+-- Notes/                               Observation and note capture
|   +-- Observations/                     Browsing, filtering, and AI summaries
|   +-- Editor/                           Note editors and tag selection
|   +-- QuickCapture/                     Quick-note sheet and parsing
|   +-- QuickNote.swift, LessonQuickNote*.swift  The lesson quick note: tag, helper, form, Mac window
|   +-- Views/                            Scoped note presentation
+-- Parsha/Services/                     Parsha metadata and suggestions
+-- Supplies/                            Inventory management
|   +-- Services/                         Supply operations
+-- Settings/                            App configuration
+-- Backup/                              Backup and restore
|
+-- CommandBar/                         Command bar: Views/, ViewModels/, Services/ (parsing)
|
+-- Services/
|   +-- Sync/CloudKitSyncStatusService.swift  Sync monitoring
|   +-- Tide/                             To-do sharing with Tide (client, sync engine and service)
|   +-- AI/, Search/, Calendar/, Photos/, System/, Migrations/, MCPServer/, Progression/
|   +-- (cross-feature infrastructure and system integrations)
|
+-- Repositories/
|   +-- StudentRepository.swift
|   +-- LessonRepository.swift
|   +-- (one struct per entity family)
|
+-- Components/                          Reusable UI primitives shared by unrelated features
+-- Utils/                               Extensions, formatting, SwiftUI, files, Core Data, platform, diagnostics
```

---

# Appendix B: Glossary

| Term | Meaning |
|------|---------|
| **Presentation** | The act of presenting a Montessori lesson to a student. Represented by `CDLessonAssignment`. |
| **Follow-up** | Work or re-presentation needed after an initial presentation. |
| **Check-in** | A progress note on an active work item (`CDWorkCheckIn`). |
| **Sequence standing** | Where a child is in one sequence of lessons: which she has had, which she has mastered and which she is up to, worked out from her presentations (`SequenceStanding`). |
| **Great Lesson** | One of the five Montessori "cosmic education" stories that frame the curriculum. |
| **Album** | A Montessori teacher's collection of lesson plans, organized by subject. |
| **Three-period lesson** | A Montessori teaching technique: introduction, recognition, recall. |
| **Scope (Note)** | Who a note applies to: all students, one student, or a specific group. |
| **Raw enum** | A string-stored enum value for CloudKit compatibility (e.g., `statusRaw`). |
| **Safe fetch** | A query wrapper that returns empty results instead of throwing on error. |
| **Pie Menu** | The circular action menu that appears on long-press of the floating button. |
| **Command Bar** | Natural language input for quick actions (presentations, work, notes, todos). |
