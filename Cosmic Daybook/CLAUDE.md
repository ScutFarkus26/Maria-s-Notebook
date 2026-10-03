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
# Every command-line build goes through Scripts/locked_xcodebuild.sh (arguments as for xcodebuild).
# It takes the Mac-wide build lock that Tide's Scripts/build also takes (~/Library/Caches/xcodebuild.lock),
# so builds from either project take turns — two at once on this fanless MacBook Air turned a 48 s
# clean build into 255 s (2026-09-23) — and runs the build at `nice -n 10`, leaving the performance
# cores to Danny's own Xcode builds. Turns go in arrival order through ~/.claude/bin/build-turn, which
# says how many builds are ahead while it waits (the Build Queue menu bar app shows whose); after
# 15 min (BUILD_LOCK_WAIT) it gives up with exit status 75, which means "never started", not a build
# failure. Any other compile (`swift build`/`test`) goes through `~/.claude/bin/build-turn <command>`.
# COMPILER_INDEX_STORE_ENABLE=NO skips the IDE-only index store on CLI builds.
Scripts/locked_xcodebuild.sh -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  COMPILER_INDEX_STORE_ENABLE=NO build

# Run unit tests: build the app + test bundle once, then run (and re-run) without rebuilding.
# Test runs compile nothing, so they skip the lock.
Scripts/locked_xcodebuild.sh build-for-testing -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  COMPILER_INDEX_STORE_ENABLE=NO
nice -n 10 xcodebuild test-without-building -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0"

# In an agent worktree: the same recipes plus the three prefix-mapping settings, which take the
# worktree's path out of the compilation-cache keys so every worktree shares one cache.
# Build ONCE right after creating the worktree, before editing anything (see Build-setting rules).
Scripts/locked_xcodebuild.sh -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  COMPILER_INDEX_STORE_ENABLE=NO SWIFT_ENABLE_PREFIX_MAPPING=YES SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES CLANG_ENABLE_PREFIX_MAPPING=YES build

# Install a Release build of main as /Applications/Cosmic Daybook.app: Danny's everyday copy, and the one
# the MCP bridge launches. Builds main's last commit in a throwaway worktree (never a working tree), keeps
# the archive + dSYM in Xcode's Organizer, refuses while the installed copy runs, saves the old copy to the
# Trash as a zip (an app bundle there gets registered again), and drops dead LaunchServices registrations.
# Run it after merging to main.
Scripts/install_release.sh

# Archive the Daybook Assistant (iPhone-only, portrait) for TestFlight: the checkout's last commit, with a
# timestamp build number (YYYYMMDDHHMM) passed as CURRENT_PROJECT_VERSION; the project itself keeps 1.
# Refuses uncommitted edits to tracked files. Upload from Xcode's Organizer. Run it outside the sandbox.
Scripts/archive_assistant_testflight.sh

# Re-render the Daybook Assistant's three flat appiconset PNGs (light, dark, tinted) from its .icon layer
# SVGs (Check.svg, Rule.svg). Re-run after editing either SVG so both icon sets keep the same art.
swift Scripts/render_assistant_icon.swift .

# Clean-build timing baseline (compare against Documentation/Implementation/perf-baselines/).
# Caching off, or a "clean" build of an already-built tree is a cache replay, not a compile; BUILD_NICE=0
# so the number is not a low-priority one.
BUILD_NICE=0 Scripts/locked_xcodebuild.sh -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  COMPILER_INDEX_STORE_ENABLE=NO COMPILATION_CACHE_ENABLE_CACHING=NO -showBuildTimingSummary clean build

# After `git worktree remove`, list the DerivedData folders whose worktree is gone (~2.3 GB each;
# with the shared cache a new worktree's first build no longer needs them) and move them to the Trash.
for d in ~/Library/Developer/Xcode/DerivedData/Cosmic_Daybook-*; do
  p=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$d/info.plist" 2>/dev/null); [ -e "$p" ] || echo "$d  ($p)"; done
```

**Build-setting rules** (reasons and measurements: `Documentation/Architecture/BUILD_SETTINGS.md`):
- Leave the scheme's `-InitializeCloudKitSchema` unchecked except for one run after a model change.
- Change `CLOUDKIT_ENVIRONMENT` only at project level, never per target or file.
- Don't override explicit modules, incremental Debug, DWARF Debug info, compilation caching or `-driver-batch-size-limit 70`.
- Agent worktrees: build once before editing.
- Extensions live in their own files. Prototype a new entity member as a `private func` in the file that uses it, and promote it once it settles.
- A script build phase, if one is ever added, must declare input and output file lists.
- Every `#Preview` body lives in a `private struct <File>Preview` that the macro calls.


## Project Structure

```
Cosmic Daybook/
├── AppCore/          # App entry, bootstrapping, dependencies, routing, commands
│   ├── Persistence/  #   CoreDataStack, database errors, CloudKit configuration
│   ├── RootView/     #   Root navigation: sidebar, tabs, detail, sheets
│   ├── Windows/      #   Window registration and detail-window plumbing
│   ├── Theme/        #   AppTheme, AppColors, spacing
│   └── SampleClassroom/ # Sample-class seeder
├── Models/           # Cross-feature NSManagedObject subclasses (single-feature entities live in their feature)
├── Repositories/     # Data access repositories
├── Services/         # Cross-feature infrastructure and system integrations
│   ├── Sync/         #   CloudKit status, persistent history, dedup, synced preferences
│   ├── AI/  Search/  Calendar/  Photos/  System/  Migrations/  MCPServer/
│   └── Progression/  #   Lesson progression shared by Lessons, Planning, Presentations, Students, Work
├── Components/       # Reusable SwiftUI used by two or more unrelated features (Toast/, WaitingStudents/, Shared/…)
├── Utils/            # Extensions/, Formatting/, SwiftUI/, Visibility/, Files/, CoreData/, Platform/, Diagnostics/
│
├── Students/         # Student profiles, detail, meetings, progress, notes, import, reports
├── Lessons/          # Lesson library, detail, attachments, scope map, parsha lessons
│   └── Checklist/    #   Class checklist: Views/, Model/, ViewModels/
├── Work/             # Work items, check-ins, practice sessions
├── Presentations/    # Presentation scheduling, queues, sessions, record index
├── Attendance/       # Attendance: Store/, Rules/, Views/, Tile/, Email/, Reports/, Insights/, Delight/
├── Planning/         # Planning tools and AI lesson planning
├── SmallSequencePlanner/ # Small-group planning by area and sequence
├── CommandBar/       # Command bar: Views/, ViewModels/, Services/ (parsing, capture)
├── Today/            # Daily hub views, view model, and support
├── Todos/            # Todo models, screens, forms, and support
├── Notes/            # Observation browsing, editing, and quick capture
├── ObservationMode/  # Developmental traits and observation quick tags
│
├── Albums/           # Teaching-album PDFs: Library/, Search/, Detail/, LessonLinks/
├── BookClub/         # Book club packets, sessions, and meetings
├── Chat/             # AI chat features
├── ClassroomJobs/    # Classroom jobs and job assignments
├── CurriculumMap/    # Three-Year View: per-child grid, class heat map, the shared engine
├── GoingOut/         # Going Out planning
├── Logs/             # Application logging
├── Orders/           # Links to request from the office, tracked to received
├── ParentReports/    # Monthly parent reports, guardians, report generator
├── Parsha/           # Weekly parsha calendar and lesson tagging
├── PerpetualCalendar/# Calendar notes
├── Procedures/       # Procedure documentation
├── ProgressDashboard/# Class progress dashboard and sequence detail
├── Projects/         # Project management & sessions
├── Resources/        # Educational resources
├── Schedules/        # Schedule management
├── Stories/          # Story library: import, analysis, covers
├── Supplies/         # Supply inventory
├── Topics/           # Community topics, solutions, community meetings, and their models
│
├── SchoolYear/       # School-year lens: store, picker, scoping, rollover grades
├── Sharing/          # CloudKit sharing (classroom collaboration)
├── Siri/             # App Intents, Siri attendance, Spotlight indexing
├── Backup/           # Backup & restore
├── Settings/         # App configuration: Classroom/, Sync/, Intelligence/, DataManagement/, Templates/, Preferences/, Dashboard/
├── AppIcon.icon/     # App icon
├── Assets.xcassets/  # Asset catalog
└── CosmicDaybook.xcdatamodeld/ # Core Data model

Daybook Assistant/    # Assistant iPhone app: Attendance/, Onboarding/, Siri/, Reminders/, Sync/, FrontDesk/, Wallpaper/
                      # (also compiles ~90 notebook files by path; see project.pbxproj)
Cosmic Daybook Tests/ # Feature-mirrored test target
Scripts/              # Build lock, install/archive, structure and unused-code checks
Documentation/        # Architecture, ADRs, plans, manuals, organization audits
```

Sidebar/tab grouping lives in `RootView.NavigationGroup` (`AppCore/RootView/RootView+NavigationGroup.swift`); `NavigationGroupTests` pins it, and pins every `NavigationItem` raw value (they are persisted — never rename one; alias a retired case via `NavigationItem.aliases`).

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
├── Private store (private.sqlite) — the guide's own records, including the classroom records
│                                     they share out (73 private-only types + the 7 share types)
└── Shared store (shared.sqlite)  — the classroom share as accepted from someone else (7 types)
```

## Data Model

**88 entities** defined in `CosmicDaybook.xcdatamodeld` (schema 14): 73 private-only, 7 in the classroom share, 8 dormant tombstones.

**Core Models:**

| Model | Class | Purpose |
|-------|-------|---------|
| Student | `CDStudent` | Student profiles (firstName, lastName, birthday, level) |
| Lesson | `CDLesson` | Curriculum lessons with attachments & exercises |
| LessonPresentation | `CDLessonPresentation` | Presentation scheduling & history |
| LessonAssignment | `CDLessonAssignment` | Links students to lessons |
| WorkModel | `CDWorkModel` | Work items; one `WorkStatus` per row (Working / Needs Review open; Mastered / Keep Practicing / Incomplete / legacy Done closed), changed only through `WorkLogService` |
| Note | `CDNote` | Observations with tags, multi-student scoping |
| AttendanceRecord | `CDAttendanceRecord` | Daily attendance tracking; `leavesAt` (schema 13) is a planned early pickup, not a mark; `returnedAt` + `statusBeforeLeavingRaw` (schema 14) record a child who left early and came back |
| ClassroomMembership | `CDClassroomMembership` | This device's role and the pinned classroom share zone (private only) |
| AttendanceDayLock | `CDAttendanceDayLock` | A day the lead guide locked (shared); read and written through `AttendanceDayLocks` |
| AttendanceEmailSend / AttendanceEmailSettings | `CDAttendanceEmailSend` / `CDAttendanceEmailSettings` | The front-desk attendance email: who sent a day's, and the guide's settings for it (shared, schema 12); read and written through `AttendanceEmailLog` |

**Core Data Patterns:**
- Entity classes use `CD` prefix (e.g., `CDStudent`, `CDLesson`)
- No unique constraints (incompatible with CloudKit)
- Enums stored as raw `String` (e.g., `statusRaw`, `categoryRaw`)
- Foreign keys as `String` not `UUID`
- `modifiedAt` for conflict resolution
- All properties optional or have defaults
- Relationships use `NSSet` (cast to `Set<CDEntityType>` for iteration)
- Use `mutableSetValue(forKey:)` for relationship mutations

**Data-integrity rules** (each has a creation-time guard and a launch-time repair; detail in `Documentation/Architecture/DATA_MODELS.md`):
- One lesson name per sub-area (`LessonRepository.createLesson` throws on a duplicate).
- Check-ins are created only by `CDWorkCheckIn.make(for:on:purpose:in:)` and read with `resolvedWork(in:)`.
- Work is only for enrolled children (`WorkRepository.createWork`).
- An observation on a presentation is scoped to specific children (`NoteScope.forSelection`), never `.all`.
- Old-record cleanup runs only through Settings › Troubleshooting › Clean Up Old Records (`NotebookJunkCleanup`), which previews and backs up first.


## Sharing Model

- **Lead Guide** — full read/write on everything; the only role that sets up sharing or locks a day
- **Assistant** — the Daybook Assistant: reads the classroom share, writes attendance on any unlocked day
- These roles are app conventions, not access control: CloudKit enforces only the share participant's permission, over all seven share types. "Attendance only", "only the guide locks" and "a locked day refuses edits" hold because the apps enforce them (`ClassroomPermissions`, `CDAttendanceStore`), and `recordedBy`/`recordedByName` are stamped by the writing device.
- Classroom share (7 types, schema 12): Student, AttendanceRecord, NonSchoolDay, SchoolDayOverride, AttendanceDayLock, AttendanceEmailSend, AttendanceEmailSettings
- **This school year only (2026-09-30):** students who are enrolled or left during this school year, and attendance from its first day on (`ClassroomShareScope`); last year leaves the share only by the Mac's Settings › Classroom › Remove Last Year from the Share (`ClassroomShareRelease`). See CloudKit Notes.
- Everything else is the guide's own (73 types): lessons, tracks, notes, work, todos, projects, meetings, ClassroomMembership, …

## Siri (App Intents)

Attendance by voice in both apps (`Siri/AttendanceIntents.swift`, `Daybook Assistant/Siri/AssistantAttendanceIntents.swift`). Details: `Documentation/Architecture/SIRI.md`.

- Every mark goes through `SiriAttendance` → `CDAttendanceStore`, the grid's path.
- Files the Assistant compiles by path reach the app only through `SiriHost` and must build for iOS 18.
- **Apple allows 10 App Shortcuts per app, and the notebook is at 10;** adding one means merging another. Retired intents stay, with `isDiscoverable = false`, so saved shortcuts keep running.
- Names reach Siri only through `updateAppShortcutParameters()`.

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
- Unused code: `Scripts/periphery-scan.sh` indexes macOS and the iOS Simulator and runs Periphery with `.periphery.yml`,
  which lists its false positives here. Confirm a hit by deleting it and building both platforms plus a Release
  build: no Debug build compiles `#if !DEBUG` or the non-Foundation-Models `#else`, so neither the index nor a
  Debug build sees code used only there. Periphery can also miss dead code (2026-09-25 it kept two unreachable
  view clusters alive). The script builds without the shared compilation cache on purpose: its prefix mapping
  records index paths as `/^src/…`, which Periphery can't match, and from 2026-09-27 to 2026-09-30 that made
  every scan print `[]`. Treat an empty report with suspicion.
- Follow Swift 6.0 strict concurrency rules — no shortcuts, no `@unchecked Sendable` unless absolutely necessary and documented.
- Follow Apple Core Data + CloudKit conventions.
- Use platform-appropriate APIs for the deployment target. Do not use availability checks (`if #available`) for APIs that are baseline at iOS 27.0+.

## CloudKit Notes

The full notes (history, recovery, the beta-SDK warnings and console noise to ignore) are in `Documentation/Architecture/CloudKit/CLOUDKIT_GUIDE.md`, under "Working notes from CLAUDE.md". The rules every change must keep:

- **Environments:** `CLOUDKIT_ENVIRONMENT` (project-level, `Production`) picks the environment for both apps; change it only in the project. A new key describing one store's sync state goes through `CloudKitEnvironment.scoped`.
- **Container:** reach it through `CloudKitConfigurationService.container`, never `CKContainer.default()` (the Daybook Assistant has its own bundle ID but shares the container).
- Two stores, private and shared; schema changes are additive-only after deployment; foreign keys are strings.
- **The classroom share** holds only `CoreDataStack.sharedEntityNames`. It is created once, by Settings → Classroom → Set Up Classroom Sharing; `classroomShare(among:in:)` returns the pinned share, never `.first`. **Never move already-shared records with `container.share(_:to:)`** (on 2026-09-27 that killed export for the session), and **never take a record out of the share** except through `ClassroomShareRelease`.
- New share-type records join the share through `SharedStoreOrphanGuard` (notebook) and `AssistantShareAttacher` (Assistant); nothing attaches during a first download (`FirstDownloadGate`). Don't add sweeps that attach records that merely *look* unshared.
- **Attendance writes go through `CDAttendanceStore`** (marks, notes, pickups, Back in Class, permissions); day locks through `AttendanceDayLocks`; the front-desk email log through `AttendanceEmailLog`.
- **A screen built from a one-off fetch must listen for imports:** `onPresentationDataChange(WhenVisible)`, adding the entity to `PersistentHistoryProcessor.presentationEntityNames` if it isn't there.
- **Persistent history:** purge only what predates both the last export's start and 180 days; only the primary on-disk stack creates a `PersistentHistoryProcessor`; positions are per store, so never save a coordinator token or another store's token as a store's position.
- **Schema:** after a model change, one Debug Development run with `-InitializeCloudKitSchema`, verify in CloudKit Console, deploy to Production before release.
- **iCloud Drive files** (managed PDF folders, backups, note photos) go through `UbiquitousFile`: on iOS another device's file is a placeholder until downloaded, and writes are coordinated. Never orphan-clean the iCloud photo folder.
- **Account status:** `CKContainer.accountStatus` / `.CKAccountChanged` for sync health, never `ubiquityIdentityToken` (that is iCloud Drive).
- **Save observers:** typed `.didSave` messages, not `.didSaveObjectIDs(Async)` (they double-fire on the 27.0 SDK). Files the Daybook Assistant compiles stay on classic notifications (iOS 18 target).

## Albums (teaching-album PDFs)

Details (indexes, costs, annotations, identity repair, lesson links): `Documentation/Architecture/ALBUMS.md`.

- The PDFs stay where they live (security-scoped bookmarks); never copy them into the container.
- `AlbumLibrary.shared` is app-lifetime and deliberately not in `AppDependencies`.
- **Album identity is the PDF filename**; `AlbumIdentityRepair` remaps it after a rename.
- Indexes load lazily (`bootstrapIfNeeded`, `ensureIndexed`), never at launch, and one embedding model is used per process.
- Annotations go through `AlbumUserDataStore`; the reading position is debounced on purpose.
- Lesson ↔ album links are never written without review in `LessonAlbumMatchSheet`.

## MCP Server (Claude Desktop)

A macOS-only server in `Services/MCPServer/` on `127.0.0.1:43117` (token preamble), bridged to Claude Desktop by `Scripts/mcp/cosmic-daybook-mcp`, toggled in Settings → AI Features → Claude Desktop. The design, the tool table and the detailed working notes are in `Documentation/Architecture/MCP_SERVER.md`. When adding or changing a tool:

- **Every write goes through the service the in-app control uses**, never straight to Core Data.
- Give every tool an `MCPToolAnnotations`, and add non-read-only and destructive names to the literal sets in `MCPToolRegistryTests` (which also pins the tool count).
- A confirm-gated preview or "nothing changed" return calls `MCPCallOutcome.markNothingWritten()`. A write that can refuse after applying part of its input runs inside `rollingBackOnFailure(context)`. Check every save result.
- Batches resolve every name before writing and land in one save; history reads take `since` / `until` through `DayWindow`.
- Nothing deletes outright except the two confirm-gated tools (`remove_student_from_work`, `discard_presentation`); `record_parent_communication` files a letter but never sends it.
- Deleting, un-marking or taking a child off a presentation calls `PresentationRecordCleanup` first; departures go through `StudentDeparturePlans`.
- **Check the Swift entity class, not the model:** `representedClassName` often differs (`Schedule` → `CDSchedule`, `CommunityTopic` → `CDCommunityTopicEntity`, `Track` → `CDTrackEntity`). Grep `class CD<Name>` before writing a fetch.
- App-level services reach tools through `MCPAppServices`.
- Keep the MCP and on-device `NotebookTools` semantics aligned. Split reads from writes (`+Work` / `+WorkWrites`) to stay under 400 lines. Inside an `inputSchema` literal a concatenated string needs `.string("…" + "…")`; a tool's `description:` is a plain `String`.

## Orders

- `Orders/` is the guide's list of things to ask the office to order: a link dropped (or pasted) onto the screen becomes a `CDOrderItem` (private store, schema 7, backup v27), and `LPMetadataProvider` fills in the page title afterwards (`OrderLinkTitleFetcher`, started on the main actor, `@Sendable` completion).
- **The stage is derived, never stored:** `CDOrderItem.stage` reads received > confirmed > asked for > to request off `receivedAt` / `confirmedAt` / `requestedAt`, so no status column can disagree with the dates. Only an item asked for can be confirmed (`markConfirmed` skips the rest; `update_order_items` refuses). Every change goes through `OrderService`, which mutates and leaves saving to the caller (the screen via `SaveCoordinator`, MCP via `safeSave`). Items asked for in one message share a `requestID`, so the office's confirmation is marked per request. Quantity (1–999, `OrderService.quantityRange`) is set with `OrderQuantityControl`'s −/+ on To Request rows and in the draft sheet, read-only once asked for; the row's taps save on an 800 ms debounce, and the email always states it.
- Draft Request (`OrderRequestDraftSheet`) builds the email with `OrderRequestMessage` (pure; wording pinned by `OrderServiceTests`), sends through `MailComposerView` / `MacOSMailSender` like the attendance email, and marks the included items asked for when Mail reports it sent — or on the guide's say-so when it can't tell.
- Who requests go to lives in `OrderRequestPrefs` (`Orders.recipientName` / `recipientEmail` / `signOffName`): synced through `SyncedPreferencesStore` and carried in backups. Edited in Settings › Communication › Order Requests and from the Orders toolbar.

## Backup System

Format v36 (encrypted Apple Archive); reads v17–v36; entry point `Backup/Archive/BackupCoordinator.swift`. The design and the detailed working notes (format history, threading, streaming, restore) are in `Documentation/Architecture/BACKUP_SYSTEM.md`. Rules:

- **A new entity or attribute:** add a line to `Backup/BackupEntityTable.swift` (and a `ModelRowSpec` in `ModelRowKinds.swift` when the row is a straight copy). `BackupCoverageTests` fails until every model entity is backed up or explicitly excluded. Bump the format version and record it in BACKUP_SYSTEM.md.
- Output is pinned by `BackupGoldenOutputTests` and `BackupSparseRowTests`; re-record only for an intended format change.
- Encode, encryption, write, verification and decode run off the main actor through `@concurrent` (plain `nonisolated async` runs on the caller's actor in this project).
- **Merge restore is an upsert:** never delete and reinsert a row. Replace mode uses context-level deletes, not `NSBatchDeleteRequest`. Restore runs through `BackupTransactionManager.executeWithRollback`.
- `ClassroomMembership` is carried but never restored.
- Binary attributes are left out (regenerable), except album highlights and ink.
- `Cosmic Daybook Tests/Backup/BackupService+LegacyRestore.swift` is a frozen copy of the old restore for the equivalence tests; don't modernize it.

## Todos for Danny

Todos for this app go in Tide, in `Areas/App Development/Cosmic Daybook/TODO.md` —
never in the old single `Areas/App Development/TODO.md`, which is gone. Add
them with Tide's `add_action`, giving that file and one of its five headings:

- `Release` — getting a build onto devices or TestFlight, uploading an archive, importing data into CloudKit.
- `Check on a device` — by-hand checks of something built ("try", "click through", "after the roll-out, check…").
- `Build & fix` — code work for a later Claude session, and cleanup of bad data.
- `Review choices` — mainly deciding: confirming choices in a DECISIONS or progress doc. "Try it, and review" is a Check.
- `Someday ideas` — features not committed to.

Put a row last in its heading unless it is urgent or blocks the rows below it;
the file's first two open rows are this app's next actions. A row for another
of Danny's apps goes in that app's folder; the full rules are in
`~/Documents/My Documents/Areas/App Development/README.md`.
