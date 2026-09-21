# CLAUDE.md - Cosmic Daybook

## Project Overview

Cosmic Daybook is a comprehensive teacher planning and classroom management app for iOS/macOS, built with SwiftUI. It helps Montessori educators manage students, lessons, work tracking, attendance, and classroom observations, and to read and search their own teaching albums.

**Tech Stack:**
- Swift 6.0 / SwiftUI
- Core Data + NSPersistentCloudKitContainer (two-store architecture)
- iOS 27.0+ / macOS 27.0+ / visionOS 27.0+
- Xcode 27.0 (27A266a) at `/Applications/Xcode.app` — the only Xcode installed, and what `xcode-select` points at, so `xcodebuild`/`xcrun` need no `DEVELOPER_DIR`

## Build & Run

```bash
# Open project
open -a "/Applications/Xcode.app" "Cosmic Daybook.xcodeproj"

# Build from command line.
# COMPILER_INDEX_STORE_ENABLE=NO skips the IDE-only index store on CLI builds.
xcodebuild -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  COMPILER_INDEX_STORE_ENABLE=NO build

# Run unit tests: build the app + test bundle once, then run (and re-run) without rebuilding.
xcodebuild build-for-testing -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  COMPILER_INDEX_STORE_ENABLE=NO
xcodebuild test-without-building -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0"

# Clean-build timing baseline (compare against Documentation/Implementation/perf-baselines/)
xcodebuild -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  COMPILER_INDEX_STORE_ENABLE=NO -showBuildTimingSummary clean build
```

**Build-setting rules** (see `Documentation/Implementation/BUILD_AND_LAUNCH_PERFORMANCE_PLAN.md`):
- The scheme's `-InitializeCloudKitSchema` launch argument stays **unchecked**. Tick it for one run after a Core Data model change, verify in CloudKit Console, then untick it — every Debug launch with it on pays a synchronous CloudKit round-trip inside `CoreDataStack.init`.
- Explicit modules (`SWIFT_ENABLE_EXPLICIT_MODULES`), incremental Debug compilation, and DWARF-only Debug info (`DEBUG_INFORMATION_FORMAT = dwarf`) are deliberate; do not override them per target or switch Debug to whole-module.
- There are no script build phases. If one is ever added (SwiftLint, codegen), it must declare input and output file lists, or Xcode re-runs it on every build and invalidates downstream products.
- Debug builds warn on functions and expressions that take over 400 ms to type-check (raised from 100 on 2026-09-21). The numbers are per batch job and wall-clock: each of the ~47 jobs lazily type-checks the declarations it references from other files (`@State`/`@FetchRequest` macro expansions, memberwise inits) and charges them to whichever body touched them first, so at 100 ms a plain `SomeView(student:)` call or a five-case `switch` was flagged — 60-odd false positives that hid real warnings. Batch-job noise peaks around 320 ms, so anything over 400 is a genuinely pathological expression: confirm it with `python3 Scripts/typecheck_timing.py <build.log>` (one whole-module job, every declaration checked once; 2026-09-21: no body over 100 ms, 12 s of body checking total). That number is wall-clock and tracks the machine's thermal state: after hours of builds the same commit read 20 s and 4 bodies over 100 ms, and three back-to-back runs went 21 → 17 → 13 s as the Mac cooled — so compare two commits only A/B/A on the same machine, never a fresh reading against a stored one. Then give it Apple's treatment — an explicit type on a complex initial value, or a nested ternary / inferred closure split up.
- Iterate on UI/data with **Run Without Building** (⌃⌘R) when the source has not changed; keep one DerivedData folder per project path.
- A `#Preview` closure is a module-level macro, so the compiler expands and type-checks its body in **every** frontend job for the module (47 batches in a clean build), not just the file's own. Every preview body therefore lives in a `private struct <File>Preview: View` in the same file and the macro body is the single call `<File>Preview()`. Hoisting all 92 previews cut clean-build type checking by 29% (2026-09-04). `@Previewable @State` becomes `@State private var` on that struct. `python3 Scripts/hoist_previews.py "Cosmic Daybook"` lists any preview that has drifted back; `--apply` rewrites it.

## Project Structure

```
Cosmic Daybook/
├── AppCore/          # App entry, initialization, root navigation
├── Models/           # NSManagedObject subclasses & extensions
├── Services/         # Cross-feature infrastructure and system integrations
├── ViewModels/       # App-wide presentation state (CommandBar)
├── Components/       # Reusable SwiftUI components
├── Utils/            # Extensions & utility functions
├── Repositories/     # Data access layer
│
├── Students/         # Student profiles & meetings
├── Lessons/          # Lesson library, attachments, exercises
├── Work/             # Work items, check-ins, practice sessions
├── Presentations/    # Presentation scheduling
├── Attendance/       # Attendance tracking
├── Planning/         # Planning & checklist tools
├── Inbox/            # Follow-up inbox
├── Today/            # Daily hub views, view model, and support
├── Todos/            # Todo screens, forms, and presentation support
├── Notes/            # Observation browsing, editing, and quick capture
│
├── Agenda/           # Calendar day/month grid views
├── Community/        # Community topics & solutions
├── GoingOut/         # Going Out planning
├── Albums/           # Teaching-album PDF library: reading, search, annotations
├── Issues/           # Issue tracking
├── Logs/             # Application logging
├── Procedures/       # Procedure documentation
├── Progression/      # Student progress tracking & analytics
├── CurriculumMap/    # Three-Year View: per-child grid, class heat map, the shared engine
├── Projects/         # Project management & sessions
├── Resources/        # Educational resources
├── Supplies/         # Supply inventory
├── Topics/           # Educational topics
├── PerpetualCalendar/# Calendar notes
│
├── Sharing/          # CloudKit sharing (classroom collaboration)
├── Backup/           # Backup & restore functionality
├── Settings/         # App configuration
└── CosmicDaybook.xcdatamodeld/ # Core Data model

Cosmic Daybook Tests/ # Feature-mirrored test target
Scripts/                 # Repository structure checks
Documentation/           # Repository-level architecture, ADRs, plans, and manuals
```

Sidebar/tab grouping lives in `RootView.NavigationGroup` (`AppCore/RootView+NavigationGroup.swift`); `NavigationGroupTests` pins it, and pins every `NavigationItem` raw value (they are persisted — never rename one; alias a retired case via `NavigationItem.aliases`).

## Architecture

**MVVM with Services pattern:**
- **Views** — SwiftUI views using `@FetchRequest` for data binding
- **ViewModels** — `@Observable @MainActor` classes for complex state
- **Services** — Business logic operations (50+ services)
- **Models** — `NSManagedObject` subclasses with `CD` prefix (76 entities)

**Data access has two layers, not three.** `Repositories/*` own per-entity writes and typed reads (`fetch(id:)`, `StudentRepository.fetchStudents(ids:)`, `LessonRepository.fetchLessons(byArea:)`); `Services/DataQueryService` owns the read helpers that span entities or apply roster policy (`fetchAllStudents(excludeTest:excludeWithdrawn:sortBy:)`, `fetchAllLessons(sortBy:)`, presented assignments, open work). View models and services call one of those instead of hand-rolling a whole-table `CDFetchRequest`, and keep a caller-specific sort or filter at the call site rather than adding a variant to the layer. A read that is really per-student is scoped there (`SequenceTrackService+ScopedReads`, predicates on the student's ids), never widened to the table.

**Concurrency:** Swift 6.0 strict concurrency throughout:
- `@Observable` on all ViewModels and stateful services (zero `ObservableObject`)
- `@MainActor` on all ViewModels, services, and repositories (~496 annotations)
- `async/await` throughout, actors for off-thread work
- `SWIFT_APPROACHABLE_CONCURRENCY` is on, so a `nonisolated async` function runs on its *caller's* actor. CPU-heavy work that must leave the main actor (decoding, tokenizing, digesting) is marked `@concurrent` — see `SearchIndexService.refreshContents` — and takes only `Sendable` arguments (a background `NSManagedObjectContext`, `Data`, value types), never a container or managed object
- `Sendable` types for cross-actor data

**Persistence:**
```
NSPersistentCloudKitContainer (CoreDataStack.swift)
├── Private store (private.sqlite) — teacher-specific data (28 entity types)
└── Shared store (shared.sqlite)  — classroom-level data (35 entity types)
```

## Data Model

**82 entities** defined in `CosmicDaybook.xcdatamodeld`.

**Core Models:**

| Model | Class | Purpose |
|-------|-------|---------|
| Student | `CDStudent` | Student profiles (firstName, lastName, birthday, level) |
| Lesson | `CDLesson` | Curriculum lessons with attachments & exercises |
| LessonPresentation | `CDLessonPresentation` | Presentation scheduling & history |
| LessonAssignment | `CDLessonAssignment` | Links students to lessons |
| WorkModel | `CDWorkModel` | Work items; one `WorkStatus` per row (Working / Needs Review open; Mastered / Keep Practicing / Incomplete / legacy Done closed), changed only through `WorkLogService` |
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

**Data-integrity rules (2026-09-10)** — each one closed a defect found by reading the live store over MCP, and each has a launch-time repair plus a creation-time guard:
- **One lesson name per sub-area.** `LessonRepository.createLesson` throws `CreationError.duplicateName` for a folded-name match in the same area + sequence (parsha lessons exempt via `parshaKey`); `DataCleanupService.mergeSameNameLessons` (in `deduplicateAllModels`, so both the launch and post-import passes) folds any pair that got in anyway onto the older record — CloudKit creation date, then `orderInSequence` — repointing presentations, marks, year-plan entries, work, notes, recall checks, track steps and the id-list fields, and collapsing a child's doubled plan entries and marks. Same name in *different* sub-areas is left alone on purpose.
- **A check-in always knows its work.** `CDWorkCheckIn.make(for:on:purpose:in:)` is the only creation path and writes the `workID` string and `work` relationship together; readers use `resolvedWork(in:)`. `CDWorkModel.prepareForDeletion` sweeps string-only check-ins so a bare `context.delete(work)` cascades too; `DataCleanupService.repairWorkCheckInLinks` relinks at launch and deletes true orphans from the second run on a device (`UserDefaultsKeys.checkInLinkRepairHasRun`).
- **Work is for enrolled children.** `WorkRepository.createWork` throws `AssignmentError.studentNotEnrolled` when the student's record is on file and not enrolled; `assign_work` refuses before creating anything; MCP readers print a former student as "Name (withdrawn)".
- **An observation on a presentation is about specific children.** The link (`CDNote.lessonAssignment`) is per presentation; the student dimension is the note's scope (mirrored into `NoteStudentLink`). `NoteScope.forSelection` gives an empty picker selection the presentation's roster, never `.all`; `DataCleanupService.repairPresentationNoteScopes` narrows old whole-class presentation notes; `PresentationObservationCoverageService` judges coverage per child.

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

## Auto-Research

At the start of each conversation, before writing or modifying any code, search the web for Apple's current documentation on the frameworks relevant to the task (Swift, SwiftUI, Core Data, CloudKit, Combine, Foundation, etc.). Focus on:
- **API currency:** Identify any APIs this project uses that Apple has deprecated or replaced. When a newer API exists, use it — but respect the project's deployment target (iOS 27.0+ / macOS 27.0+).
- **Correct signatures and types:** Verify method signatures, parameter types, return types, and property wrappers against current docs. Do not guess or rely on training data — confirm from the source.
- **Apple-recommended patterns:** Follow Apple's documented patterns for concurrency (`async/await`, `@Sendable`, actors), data flow (`@Observable`, `@Environment`, `@FetchRequest`), and lifecycle (`@main`, scene phases, background tasks).
- **Warning elimination:** Treat every compiler warning as a bug. If Apple's docs show a warning-free way to accomplish something, use that approach. Pay special attention to: strict concurrency warnings, deprecated API usage, implicit `self` captures, unused variables/results, and `Sendable` conformance.

## Standards

- **Zero warnings policy:** All code must compile with zero warnings. Before proposing a change, consider whether it could introduce deprecation warnings, concurrency warnings, or type-safety warnings — and avoid them proactively.
- All code must pass SwiftLint (see `.swiftlint.yml`). A hook runs it automatically after edits.
- Follow Swift 6.0 strict concurrency rules — no shortcuts, no `@unchecked Sendable` unless absolutely necessary and documented.
- Follow Apple Core Data + CloudKit conventions.
- Use platform-appropriate APIs for the deployment target. Do not use availability checks (`if #available`) for APIs that are baseline at iOS 27.0+.

## CloudKit Notes

- Container: `iCloud.DanielSDeBerry.MariasNoteBook` — a literal in `CloudKitConfigurationService.getContainerID()`, deliberately NOT derived from the bundle ID: the assistant companion app has its own bundle ID but shares this container.
- Two persistent stores: private (teacher data) + shared (classroom data)
- Schema changes must be additive-only after CloudKit deployment
- All models use string-based foreign keys for sync compatibility
- **Attendance is moving to the shared store in two steps** so the assistant companion app can write it. Step 1 (landed): `AttendanceRecord.recordedBy`/`modifiedAt` attribution stamped by `CDAttendanceStore` (the chokepoint that also enforces `ClassroomPermissions.canWrite`); records created lazily on first mark, never in bulk on screen-open; `Note.attendanceRecordID` string FK kept in lockstep with the `attendanceRecord` relationship and backfilled by `AttendanceNoteLinkBackfill`; both dedup passes share `AttendanceDeduplication.wins` (marked > latest `modifiedAt` > lowest id). Step 2 (pending — only after every device of Danny's has run step 1 once): delete the `AttendanceRecord.notes` ↔ `Note.attendanceRecord` relationship (it would illegally cross store configurations), move `"AttendanceRecord"` from `privateEntityNames` to `sharedEntityNames`, bump `currentSchemaVersion` to 3. Do not fold step 2 into a step-1 build.
- **Shared-store zone repair:** `SharedStoreZoneRepair` (Services/SharedStoreZoneRepair.swift) detects records in the shared store that aren't assigned to a CKShare zone — these poison `NSCloudKitMirroringDelegate` with `NSCocoaErrorDomain 134060`. It runs at the end of post-launch migrations, after each post-import dedup pass, and when `ClassroomSharingService.isSharing` transitions `false → true`. Lead guides also see a banner + "Repair Sync Errors" button in Settings → Classroom Sharing. Every automatic run is gated on persistent history (`SharedStoreZoneRepair+HistoryGate.swift`): a pass that leaves nothing to attach records its starting history token as a clean watermark, and the next run reads history since that token first — no shared-entity insert means no entity table is read at all, and a scoped insert scans only those entities. Detection fetches object IDs on a background context, never the view context. Only the manual button forces a full scan; Reset Local Cache clears the watermark.
- **Persistent history purge policy:** never purge history the mirroring delegate may still need — that resets sync and can resurrect deletions. `PersistentHistoryProcessor.purgeOldHistory` only deletes transactions that predate BOTH the last successful `.export` event's start date (recorded by `CloudKitSyncStatusService`) and a 180-day retention window, at most every 60 days. Do not add token- or short-date-based purging.
- **Only the primary on-disk `CoreDataStack` creates a `PersistentHistoryProcessor`.** Sample Class / in-memory stacks must not — history tokens are per-store and all processors share one UserDefaults key.
- **CloudKit schema:** after a model change, run a DEBUG build once with the `-InitializeCloudKitSchema` launch argument to mirror the model into the development schema, verify in CloudKit Console, then deploy to production before release.
- **Account availability:** use `CKContainer.accountStatus` / `.CKAccountChanged` for CloudKit sync health, never `ubiquityIdentityToken` (that reports iCloud *Drive*, which users can disable while CloudKit keeps working). The ubiquity token remains correct for the iCloud Drive file-storage features.

### Known beta-SDK build warnings (Xcode 27 beta 1)

- `@Generable` macro expansions reference the deprecated `GenerationError.decodingFailure` internally. The warning comes from Apple's macro-generated code, not project source, and cannot be fixed here — re-check on each new Xcode 27 seed and drop this note once Apple fixes the macro.
- `SpeechRecognitionService.installRecognitionTap` suppresses the `installTap` deprecation via Swift 6.4's `@diagnose` attribute: the refined replacement (`installAudioTap`) delivers `AVReadOnlyAudioPCMBuffer`, which `SFSpeechAudioBufferRecognitionRequest.append` cannot accept in beta 1. Re-check each seed and migrate when Speech catches up.

### Console log noise to ignore

These come from Apple's frameworks, not this app — they are not actionable in source:

- `updateTaskRequest called for an already running/updated task com.apple.coredata.cloudkit.activity.export.*` (subsystem `com.apple.BackgroundSystemTasks`, category `BGSTFramework`) — `NSPersistentCloudKitContainer` internals managing background export tasks.
- `updateTaskRequest failed for com.apple.coredata.cloudkit.activity.export.*` and `Error updating background task request: BGSystemTaskSchedulerErrorDomain Code=3` — same source; benign when sync is otherwise working.
- `It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out.` (subsystem `com.apple.AppKit`, category `WarnOnce`) — AppKit/SwiftUI hosting internals on macOS 27 beta; no project code calls `layoutSubtreeIfNeeded`. Logged once per run.
- `XPC connection was interrupted` (subsystem `com.apple.reminderkit`) — ReminderKit's connection to its daemon being recycled; EventKit re-establishes it automatically.

**Filter in Console.app:** exclude subsystem `com.apple.BackgroundSystemTasks`.
**Noisy Xcode debug runs:** set `OS_ACTIVITY_MODE=disable` in the scheme's environment variables.

## Albums (teaching-album PDFs)

- `Albums/` holds the whole feature: the guide points at one or more folders of album PDFs and the app indexes every page. **The PDFs stay where they live** — the app keeps security-scoped bookmarks (`UserDefaultsKeys.albumsFolderBookmarks`) and never copies them into the container, unlike Stories/Resources. That's what `com.apple.security.files.bookmarks.app-scope` in the entitlements is for.
- Two indexes, both cached in Application Support and rebuilt when a PDF's modification date changes: full page text (`AlbumSearchIndex/`) and on-device embeddings (`AlbumSemanticIndex/`, NaturalLanguage). `AlbumLibrary.shared` is app-lifetime and deliberately **not** in `AppDependencies` — the album shelf is the guide's own and must not swap with the active classroom.
- Loading is lazy: `AlbumsRootView` calls `bootstrapIfNeeded()` on first appearance, and the AI tools call `ensureIndexed()`. Opening every PDF at launch is too heavy for `performStartupBootstrap()`.
- Annotations (bookmarks, page notes, highlights, Pencil ink, recents, reading position) are six private-store entities written through `AlbumUserDataStore`, which saves after every mutation so marks survive a kill. The **reading position and recent visit are the exception** — `AlbumDetailView` debounces them ~1.5s and flushes on disappear, because writing them on every `currentPage` change fired two Core Data saves (and two CloudKit pushes) per page turn.
- **Album identity is the PDF filename**, which is what every annotation row, citation, `@SceneStorage` value, album-window value, and MCP tool argument carries. Renaming a PDF would orphan all of it, so `AlbumIdentityRepair` fingerprints each album by page count + outline titles + first-page text, keeps a fingerprint → filename map in `UserDefaultsKeys.albumsFingerprints`, and remaps every `albumID` foreign key when an album reappears under a new name and the old name is gone from disk. Driven from `AlbumsRootView` because it needs a managed object context.
- **Lesson ↔ album links:** `CDLesson` carries `albumID` / `albumPageIndex` / `albumLessonTitle` / `albumLinkConfidence` (see `CDLesson.albumLink`, which vends an `AlbumLink`). `LessonAlbumMatcher` scores every unlinked lesson against every album outline entry (70% folded-title Dice coefficient, 30% semantic index, small subject/area bonus); nothing is written without review in `LessonAlbumMatchSheet`, because album outlines repeat lesson titles across levels. `albumLessonTitle` is the re-resolution anchor: `reresolvePages` re-points page numbers by title when a revised PDF shifts pagination. Entry points: the lesson detail's Album row (`LessonAlbumLinkSection`), the album reader's Notebook Lesson button (`LinkedNotebookLessonsPanel`), and Library Options ▸ Match Lessons to Albums. Cross-surface navigation goes through `AppRouter.navigateToAlbumPage` / `navigateToLesson`.
- Ported from the standalone Albums app (`~/Developer/Albums`), which is left in place. `Scripts/export_albums_user_data.sh` + Library Options → Import Albums App Data… carries its data over.

## MCP Server (Claude Desktop)

- macOS-only: the app embeds an MCP server (`Services/MCPServer/`) on loopback TCP `127.0.0.1:43117` with an `AUTH <token>` preamble (token at `~/.cosmic-daybook/mcp.token` via a scoped entitlement exception). Unix sockets don't work here: the sandbox can't bind them outside the container, and container paths trip macOS container-protection TCC for external clients. `Scripts/mcp/cosmic-daybook-mcp` bridges to Claude Desktop's stdio transport via `nc`. See `Documentation/Architecture/MCP_SERVER.md`.
- Toggle: Settings → AI Features → Claude Desktop (`UserDefaultsKeys.aiMCPServerEnabled`, default off). Lifecycle: `MCPServerService.shared`, started from `performStartupBootstrap()`.
- **86 tools covering the whole notebook, reads and writes** (2026-09-18; `MCPToolRegistryTests` pins the count) — the deliberate goal is that anything the guide can see or change in the app is reachable over MCP. `Documentation/Architecture/MCP_SERVER.md` has the full table; the domain files are `MCPNotebookTools+{Reads,Writes,ObservationBatch,FollowUps,Lessons,CurriculumSupport,CurriculumReads,CurriculumWrites,CurriculumOrdering,Presentations,PresentationSchema,PresentationHistory,PresentationEdits,Mastery,MasteryCandidates,Meetings,MeetingReads,MeetingScheduling,Schedule,ScheduleWrites,Work,WorkWrites,WorkRemoval,Practice,Attendance,Todos,Families,Communications,Classroom,Jobs,Supplies,Projects,Issues,Reference,Library,Planning,YearPlanWrites,YearPlanClearing,AlbumMarks,SyncStatus,CurriculumMap,PendingStudents,ReadyForNext,AppServices,WriteJournal,PresentationResolution,RepeatGuard,SchoolCalendar}.swift`.
- **Annotations (2026-09-10):** every `MCPToolDefinition` carries an `MCPToolAnnotations` (`.readOnly` / `.write` / `.idempotentWrite` / `.destructive`, no default) that `tools/list` emits as the spec's `annotations` object; `MCPToolRegistryTests.annotationsClassifyEveryTool` pins the non-read-only and destructive sets as literals — add a new tool's name there. Catalogue bytes are paid on every connection: batch tools strip descriptions from their array-item copy via `JSONValue.withoutDescriptions`, and descriptions state behaviour (dedup, refusals, confirm) rather than which in-app control they mirror — that belongs in `MCP_SERVER.md`.
- **Write journal (2026-09-10):** `MCPRequestHandler`'s `onWrite` hook records every successful non-read-only call (by annotation) into the `MCPWriteJournal` actor — `<Application Support>/MCP/writes.jsonl`, capped at 2 MB — and `recent_mcp_writes` reads it back with the `[kind id=…]` citations parsed from each receipt. Provenance deliberately lives here and not on entity fields: `CDNote.reportedBy` / `reporterName` mean guide-versus-assistant and the export's speaker, so stamping them would mislabel the guide's own dictated notes.
- **Batch forms and duplicate guards (2026-09-10):** `record_presentation` takes a `presentations` array, `create_observation` a `notes` array, `mark_attendance` a `students` array or `mark_all_present`. Every batch resolves every name before writing anything and lands in one save. `create_observation` and `add_follow_up` report an identical record from the same day (same trimmed body/title, same students) instead of filing it again; `force: true` overrides. The history reads (`student_observations`, `student_meetings`, `practice_sessions`, `recall_checks`, `presentations_missing_observations`) take a `since` / `until` window through the shared `DayWindow` helper in `MCPNotebookTools.swift`; an unset end stays unbounded so old arguments return exactly what they did. **The regive guard (2026-09-11):** `schedule_presentation` and `record_presentation` refuse a lesson a named child already has on record — read through `PresentationRecordIndex`, days strictly before the one asked for plus undated marks — unless the call carries `purpose` (`second_pass`, which also flags her latest presented assignment `needsAnotherPresentation`, or `review`); either purpose writes its line as the first line of the new record's `notes`, which `student_presentation_history` reads back as "(2nd time; second pass)", and the capture review's own "re-present" decision now writes the same pair. Same-day re-files and plan completions are exempt, and `schedule_presentation` also refuses days `SchoolCalendarService` says school is out, exactly as `schedule_meeting` does. The shared pieces live in `MCPNotebookTools+RepeatGuard.swift`. **WatchList (2026-09-11):** `Students/Watching/` derives one per-child "Watching" list — never persisted, no model change — from flagged notes, open todos whose title begins with "Watch" and name a child, and active focus items (`WatchListBuilder` is the pure rule, `WatchListFetcher` the reader, `WatchListActions.clear` the one way to unflag / complete / resolve a row); it is drawn on the student overview and, for rows raised in the selected week, on Today, and `list_open_follow_ups` with `watching_only` prints exactly it while `resolve_follow_up` can now clear a note's flag.
- Read tools mirror `Services/AI/NotebookTools.swift` conventions (`[kind id=<uuid>]` citations, diacritic-insensitive student resolution). `find_lessons` names a lesson from the curriculum (exact name > partial name > area/sequence) and refuses to guess between candidates.
- **Three-Year View (2026-09-09):** `student_curriculum_map` / `class_curriculum_map` read the same `CurriculumMapEngine` cells the two screens draw (`CurriculumMap/`). The ladder — presented → chosen → repeated → mastered, ringed by the latest recall check — is pinned by `CurriculumMapEngineTests`; change it there, not in a tool. `Lesson.isKeyLesson` (schema 6, backup v25) plus the first lesson of every sub-area and the Great Lesson stories are the default rows; `create_lesson`/`update_lesson` take `is_key_lesson`. `students_pending` (2026-09-10) is the plan-side counterpart of `class_curriculum_map`: one lesson in, every enrolled child still due for it out, with target date, pace, and the scheduled presentation she is already on — the group-forming query that used to take a `year_plan` call per child. `students_ready` (2026-09-11) is the record-side queue: every child confirmed at capture or marked mastered on a lesson N whose next lesson N+1 in the same sub-area is untouched — neither given to her nor on a plan for her — built by `ReadyForNextEngine` over `PresentationRecordIndex` and `BlockingAlgorithmEngine.buildNextLessonCache`, gated by the Small Sequence Planner's practice rule, and closing each by-lesson group with the literal `schedule_presentation` call. It proposes and never writes.
- **Curriculum editing (2026-09-09):** `list_lessons_by_area` (uncapped; since 2026-09-11 each sub-area is banded under `Section:` headings via `LessonSectionGrouping`, the only MCP read of `CDLesson.section`), `create_lesson`, `update_lesson`, `reorder_lessons`. Ordering has two columns and they mean different things: `orderInSequence` is the truth within a sub-area (the `sequence` string); `sortIndex` is a derived area-wide index the area view sorts on, rebuilt by walking the sub-areas in `FilterOrderStore`'s saved (UserDefaults, device-local) order. Every tool write renumbers the first and rebuilds the second exactly as `LessonsRootViewReordering` does after a drag — helpers in `+CurriculumSupport`. Areas are never created by a tool; sub-areas are. `create_lesson` is idempotent on folded name within a sub-area and makes AddLessonView's best-effort `getOrCreateTrack` call afterwards (which can retire stale track *steps*, never lessons).
- **Every write goes through the same service the in-app control uses**, never straight to Core Data: `create_observation` → the `LogObservationIntent` save path; `record_presentation` → the command bar's `saveCaptureProposal` (`LifecycleService.recordPresentation` + `PresentationOutcomePersistenceService.persistObservations` + `CaptureFollowUpPersistence.persist`, the per-child decisions — practice, follow-up work, re-present, ready, keep observing — lifted out of `CommandBarViewModel` so both paths share them), so it completes a matching planned presentation instead of duplicating it, treats the same lesson/students/day as an edit, and dates its notes to the presentation rather than the moment of writing; `update_student` / `update_observation` → `StudentRepository` / `NoteRepository`; `create_meeting_entry` → `MeetingFormPane.saveAndContinue`'s shape (meeting + goals as `FocusItemService` items), then `MeetingScheduler.completeBooking` so the day's booking leaves `scheduled_meetings` the way the Today agenda clears a started meeting; `schedule_meeting` → `MeetingScheduler.bookMeeting`, the meetings tab's date-picker path (one individual booking per student — another day moves it), refusing days `SchoolCalendarService` says school is out; `add_follow_up` → `NewTodoForm.createTodo`; `assign_work` → `WorkRepository.createWork` + the Quick New Work sheet's participant cross-linking; `update_work` → `WorkLogService.log` (status, per child, settling the row's check-ins) / `WorkCompletionService` (`completed_by`); **`mark_attendance` → `CDAttendanceStore`**, the chokepoint that enforces `ClassroomPermissions`, stamps attribution, and assigns the record to the right store — never write `CDAttendanceRecord` directly; `schedule_presentation` → `PresentationFactory.makeDraft` + `schedule(onDay:)`, reusing an existing unpresented plan for the same lesson and exact student set; `skip_year_plan_entries` and `clear_year_plan` → `StudentDeparturePlans.plannedEntries` + `skip`, the same call the roster editor and the school-year rollover make when a child departs (`clear_year_plan` scopes by track / before-date and previews first); `update_presentation_roster` → the presentation detail's Save shape (`studentIDs` in place + `modifiedAt`); `discard_presentation` → the planning list's context-menu delete, confirm-gated (no `confirm` = report only; `confirm: true` deletes in that call, no preview call required), and it returns a promoted year-plan entry to `planned` — the one thing the in-app delete does not do.
- **Departure is a cascade, and it has two halves.** Withdrawing or transferring a child takes her off lessons planned but not yet given (`CDLessonAssignment`, which would otherwise generate work naming her) *and* marks her still-`planned` `CDYearPlanEntry` rows `skipped` (they would otherwise go on accruing "behind pace" forever). Both live in `StudentDeparturePlans` and are driven from the only two places enrollment status is written: `StudentDetailView.commitEdit` (which offers the change in one alert) and `RolloverService.apply`. Entries are **skipped, never deleted**, so a girl who re-enrols finds her plan intact. Promoted entries are left alone — they belong to a real assignment on the calendar, and that assignment is the truth. `SequenceAutoPopulateService` filters departed children out before creating entries, or the cascade would simply re-grow what it just retired.
- **Two deliberate boundaries** in an otherwise total surface: nothing deletes a record outright — the two exceptions are `remove_student_from_work`, which is two-step (a call without `confirm: true` only reports the plan) and goes through `WorkDeletionService`, so removing an owner promotes a remaining participant rather than deleting a shared row, and `discard_presentation`, gated on the same `confirm` flag (a first call with `confirm: true` deletes at once) and refused for anything already given — and `record_parent_communication` files a letter but never sends it — delivery to families stays in the app where the guide reviews it. Guardian emails, parent communications and meeting notes *are* exposed; that was an explicit decision, not an oversight.
- Where the model has columns the app never adopted, tools follow the app: `CDSupply.minimumThreshold` / `unit` / `isOnOrder` exist in the `.xcdatamodel` but no Swift property declares them and nothing writes them, so `list_supplies` offers a caller-supplied `below` instead of a reorder threshold. **Check the Swift entity class, not the model** — `TransitionPlan`, `PrepChecklist`, `Initiative` and `WorkCycleSession` have no Swift class and no app code at all, so there is nothing to expose; `DevelopmentSnapshot` has a class but nothing writes it.
- **Model `representedClassName` often differs from the Swift class**: `Schedule` → `CDSchedule`, `ScheduleSlot` → `CDScheduleSlot`, `CommunityTopic` → `CDCommunityTopicEntity`, `Track` → `CDTrackEntity`, `StudentTrackEnrollment` → `CDStudentTrackEnrollmentEntity`. Grep for `class CD<Name>` before writing a fetch.
- **App-level services reach MCP through `MCPAppServices`**, a one-slot locator `performStartupBootstrap` fills with `AppDependencies` just before the server starts; `makeTools(context:dependencies:)` passes a provider to the tools that need it. `create_backup` → `AutoBackupManager.performManualBackup` (the `.manual` trigger: never change-gated, ignores the auto-backup switch, always writes a file); `draft_parent_report` → `MonthlyReportDraftService.generateDraft` + `upsertReport`, refusing reviewed or sent reports and keeping an existing draft's text unless `overwrite`. Under tests the provider returns nil (the tools say the app is still starting) or a container on the in-memory stack. `sync_status` needs none of this because `CloudKitSyncStatusService` is a singleton.
- **School calendar (2026-09-18):** `school_calendar` / `set_school_days` / `update_school_calendar`. Days are written through `SchoolCalendarService.setSchoolDay`, the explicit, idempotent form of the Settings grid's `toggleNonSchoolDay` (weekday out → `NonSchoolDay` with `reason`; weekend in → `SchoolDayOverride`, any `NonSchoolDay` on it removed because it would win under `SchoolDayChecker`), so every school-day cache drops the same way; the year settings (start month/day, counter epoch) go through `AppDependencies.schoolYearStore`, the object the Settings pickers bind to, and so need the `MCPAppServices` provider.
- **Two gotchas when adding a tool.** Inside an `inputSchema` dictionary literal a concatenated string needs an explicit `.string("…" + "…")`, but the tool-level `description:` is a plain Swift `String` and must not be wrapped. And keep each file under SwiftLint's 400-line limit by splitting reads from writes (`+Work` / `+WorkWrites`), not by growing one file.
- Keep the MCP and on-device (`NotebookTools`) toolsets' semantics aligned when changing either.
- Teaching-album tools: `search_albums` and `get_album_page` (MCP) mirror `SearchTeachingAlbumsTool` (chat). Both go through `Albums/AlbumCorpusLookup.swift`, so wording and citations stay identical. Album pages have no UUID, so they cite `[albumPage album="<file>" page=<n>]` instead of `[kind id=<uuid>]` and don't feed the evidence collector.

## Backup System

- **Current write format: v25 (encrypted Apple Archive)**. Files are genuine Apple Encrypted Archives — first 4 bytes are `AEA1`, AES-CTR + HMAC via `ArchiveEncryptionContext` (profile `hkdf_sha256_aesctr_hmac__symmetric__none`), with LZFSE compression inside the AEA layer. The 256-bit symmetric key lives in the **iCloud Keychain** (`Backup/Archive/BackupEncryptionKeyStore.swift`, `kSecAttrSynchronizable` + `kSecAttrAccessibleAfterFirstUnlock`) so a backup written on one device restores on any device on the same Apple ID. Files are written `0600`. Contents: a `manifest.json` first entry (format version + entity counts + origin-store routing), `preferences.json`, then one NDJSON entry per Core Data entity type, prefixed `private/` or `shared/` to indicate origin store.
- **Read support: v17–v25** (`BackupReader.supportedFormatVersions`). v19+ is the encrypted container; v17/v18 are plain LZFSE Apple Archives (magic `pbz*`) and still read so older backups and checkpoints restore. `BackupArchive.isBackupArchive(at:)` accepts both magics; `isEncryptedArchive(at:)` distinguishes them. **Legacy v5–v16 JSON-envelope `.mtbbackup` files cannot be read by the app at all** — that decoder was removed; use the external recovery process referenced in `Documentation/Architecture/BACKUP_SYSTEM.md`. The repo's own `Backups/*.mtbbackup` through 2026-04-01 are all this unreadable legacy format.
- Top-level entry point: `Backup/Archive/BackupCoordinator.swift`. UI calls `coordinator.exportBackup`, `coordinator.previewImport`, `coordinator.importBackup`.
- **Threading:** payload collection runs on the main actor (Core Data view-context queue); NDJSON encode, encryption, archive write, read-back verification, and decode all run off the main actor (`BackupWriter.encodeAndWrite`, `BackupImporter.decodeArchive` are `nonisolated async`).
- **Integrity:** export writes to a hidden temp file in the destination dir, re-reads it (`BackupReader.verifyStructure` — streams the whole archive, checks the manifest decodes and per-entity NDJSON row counts match), then atomically renames into place. An encode failure for any entity type aborts the whole export (`BackupWriter.WriterError`) rather than silently dropping data; a malformed entry on read surfaces as a warning in `BackupOperationSummary`.
- Auto-backup on macOS quit (`applicationShouldTerminate` → `.terminateLater`), on iOS scene-phase `.background` + a `BGProcessingTask` (`AppCore/BackupBackgroundTaskManager.swift`, id `DanielSDeBerry.MariasNoteBook.backup`), plus a configurable in-app interval loop; retention default 10. All automatic triggers are **change-gated** via persistent history (`Backup/Core/BackupChangeTracker.swift`) — an untouched dataset skips the backup. Honors the user's chosen destination folder.
- Restore goes through `BackupTransactionManager.executeWithRollback` (safety checkpoint + auto-rollback on failure). Checkpoints are written in the current format via `BackupWriter`.
- Restore upsert/relationship lookups use `BackupEntityIndex` (one fetch per entity type, built lazily so child types see parents inserted earlier in the same restore) — not a fetch-request-per-record. Preview uses `EntityIDIndexCache` (one id-set fetch per type).
- **Merge mode is an upsert, not insert-only:** every importer resolves the pre-restore record for the DTO's ID via `ExistingLookup` and populates it in place (backup wins for any ID it holds); records absent from the backup are left alone. Replace mode clears the store first, so the same code path inserts everything. Never delete-and-reinsert an existing row — that nullifies relationships from records the backup doesn't know about and emits CloudKit tombstones.
- **Preferences entry (v23+):** `Backup/Core/BackupPreferencesService.swift` lists every user-chosen setting that is backed up (school year, recall spacing, AI model choices, view state, per-date attendance locks via `preferenceKeyPrefixes`, album folder bookmarks + fingerprint map). Device-only plumbing (CloudKit tokens, window positions, the MCP toggle, migration flags, API keys) is deliberately excluded. List/map values ride in `PreferenceValueDTO.plist`. Album keys use a merge policy on restore (bookmarks union, fingerprints local-wins) so a merge never drops a folder the device already registered.
- **Album annotations after restore:** bookmarks/notes/highlights/ink key on the album PDF filename. If no album folder bookmark resolves on the restoring device, `importPayload` adds a warning telling the guide to add the folder; once they do, `AlbumIdentityRepair` uses the restored fingerprint map to reattach annotations even when the PDFs came back under new filenames.
- The post-restore CloudKit export wait subscribes to `NSPersistentCloudKitContainer.eventChangedNotification` **before** `viewContext.save()` so a fast export isn't missed (`BackupService+Restoration.swift`).
- `replace` mode uses context-level deletes (NOT `NSBatchDeleteRequest`) so CloudKit mirroring sees proper delete tombstones.
- **Entity coverage is test-enforced:** `BackupCoverageTests` asserts `BackupEntityRegistry.allTypes` ≡ `BackupWriter.serializedEntityNames` ≡ `BackupImporter.handledEntityNames`, and that every model entity is either backed up or in an explicit, documented exclusion list (the 8 removed-feature tombstones). Adding an entity without backup coverage is a red test, not a future format version.
- Entity registry: `Backup/Core/BackupEntityRegistry.swift`. Per-entity DTO transformers in `Backup/Export/BackupDTOTransformers*.swift`. Per-entity importers in `Backup/Import/BackupEntityImporter+*.swift` (well-factored static methods).
- **Adding an entity also means `BackupPayloadDeduplicator.deduplicate`** (`Backup/BackupServiceHelpers.swift`): it rebuilds the payload field by field, so an array it doesn't copy is silently `nil` by the time the importer runs and the records vanish on restore. The coverage tests don't catch this; `BackupFieldCoverageTests` does.
- Binary attributes are excluded from backups by design because they're regenerable (thumbnails, covers, file bookmarks). The **one exception is the album annotations** (format v21): highlight rectangles travel as plain numbers and Pencil ink travels as its PencilKit data, because neither can be recreated after a restore.
