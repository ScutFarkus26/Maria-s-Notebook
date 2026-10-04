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
# Test runs compile nothing, so they skip the lock, and run on this checkout's own iPhone 17 from
# ~/.claude/bin/sim-lease: on the shared "iPhone 17" two sessions' runs killed each other's apps. A hook
# refuses a test run aimed at a simulator by name.
Scripts/locked_xcodebuild.sh build-for-testing -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" \
  COMPILER_INDEX_STORE_ENABLE=NO
nice -n 10 xcodebuild test-without-building -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"

# The Daybook Assistant's phones: the assistants carry an iPhone SE (3rd generation) on iOS 26 and an
# iPhone 14 Pro Max on iOS 27. Check the Assistant on the SE leased on iOS 26.5, always with `--os 26.5`:
# without it sim-lease makes a second SE on iOS 27, and Danny keeps only one.
~/.claude/bin/sim-lease --type "iPhone SE (3rd generation)" --os 26.5

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
├── Groups/           # Groups page: who is ready for the same next lesson, sequence ladder
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
├── Orders/           # Restock's needs to order: request email, stages, link titles
├── ParentReports/    # Monthly parent reports, guardians, report generator
├── Parsha/           # Weekly parsha calendar and lesson tagging
├── PerpetualCalendar/# Calendar notes
├── Procedures/       # Procedure documentation
├── ProgressDashboard/# Class progress dashboard and sequence detail
├── Projects/         # Project management & sessions
├── Resources/        # Educational resources
├── Schedules/        # Schedule management
├── Stories/          # Story library: import, analysis, covers
├── Supplies/         # Restock: staples with levels, needs, the one page
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
Documentation/        # Architecture, ADRs, plans, manuals, audits; start at Documentation/INDEX.md (plans and status)
```

Sidebar/tab grouping lives in `RootView.NavigationGroup` (`AppCore/RootView/RootView+NavigationGroup.swift`); `NavigationGroupTests` pins it, and pins every `NavigationItem` raw value (they are persisted — never rename one; alias a retired case via `NavigationItem.aliases`).

## Architecture

MVVM with services on `NSPersistentCloudKitContainer` (private and shared stores, `CoreDataStack.swift`). Data access has two layers: `Repositories/*` (per-entity writes, typed reads) and `Services/DataQueryService` (reads across entities); never hand-roll a whole-table `CDFetchRequest`. Swift 6 strict concurrency; CPU-heavy work that leaves the main actor is `@concurrent` and takes only `Sendable` arguments. Detail: `Documentation/Architecture/ARCHITECTURE.md`.

## Data Model

88 entities (schema 15): 70 private-only, 10 in the classroom share, 8 dormant tombstones. Core Data rules: `CD` prefix, no unique constraints, enums as raw `String`, foreign keys as `String`, every property optional or defaulted, `modifiedAt` for conflicts. Integrity rules and the entity table: `Documentation/Architecture/DATA_MODELS.md`.

## Sharing Model

- **Lead Guide** — full read/write on everything; the only role that sets up sharing or locks a day
- **Assistant** — the Daybook Assistant: reads the classroom share, writes attendance on any unlocked day, and marks staples, checks off the office run and adds needs (Restock)
- These roles are app conventions, not access control: CloudKit enforces only the share participant's permission, over all ten share types. "Attendance and Restock only", "only the guide locks" and "a locked day refuses edits" hold because the apps enforce them (`ClassroomPermissions`, `CDAttendanceStore`), and `recordedBy`/`recordedByName` are stamped by the writing device.
- Classroom share (10 types, schema 15): Student, AttendanceRecord, NonSchoolDay, SchoolDayOverride, AttendanceDayLock, AttendanceEmailSend, AttendanceEmailSettings (schema 12), Supply, SupplyTransaction, OrderItem (schema 15)
- **This school year only (2026-09-30):** students who are enrolled or left during this school year, and attendance from its first day on (`ClassroomShareScope`); last year leaves the share only by the Mac's Settings › Classroom › Remove Last Year from the Share (`ClassroomShareRelease`). See CloudKit.
- Everything else is the guide's own (70 types): lessons, tracks, notes, work, todos, projects, meetings, ClassroomMembership, …

## Siri (App Intents)

Rules: `Documentation/Architecture/SIRI.md`. Apple allows 10 App Shortcuts per app and the notebook is at 10 (the Assistant 9): adding one means merging another.

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
- **Plain English on screen** (plan: `Documentation/Implementation/Archive/PLAIN_ENGLISH_PLAN.md`): every message the apps show says what happened and what to do, in everyday words. Never put `error.localizedDescription`, `"\(error)"`, codes, IDs, paths or type names into UI text; log them, and put any worth keeping under `TechnicalDetailsDisclosure`. Errors go through `AppErrorMessages` (`userMessage`, `sharingMessage`, `importMessage`, `backupMessage`, `syncMessage`, `aiMessage(fallback:)`); Apple Intelligence wording lives in `AppleIntelligenceMessages`. `SaveCoordinator.save`'s `reason:` is a log label, never shown; pass `alertOnFailure: false` when the screen shows its own message.

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

Rules: `Documentation/Architecture/CloudKit/CLOUDKIT_GUIDE.md`. Never `CKContainer.default()` (use `CloudKitConfigurationService.container`); never move shared records with `container.share(_:to:)` or take one out of the share except through `ClassroomShareRelease`; schema changes are additive-only and, after a model change, need one Debug Development `-InitializeCloudKitSchema` run before the Production deploy; attendance writes go through `CDAttendanceStore`.

## Albums (teaching-album PDFs)

Rules: `Documentation/Architecture/ALBUMS.md`. The PDFs stay where they live; never copy them into the container.

## MCP Server (Claude Desktop)

Rules: `Documentation/Architecture/MCP_SERVER.md`. Every write goes through the service the in-app control uses, never straight to Core Data; every tool gets an `MCPToolAnnotations` and a line in `MCPToolRegistryTests`.

## Restock (Supplies + Orders)

Rules: `Documentation/Architecture/RESTOCK.md`. `RestockService` is the only writer; a need's stage is derived, never stored.

## Backup System

Format v37; rules: `Documentation/Architecture/BACKUP_SYSTEM.md`. A new entity or attribute needs a line in `Backup/BackupEntityTable.swift` and a format-version bump; merge restore is an upsert, never delete and reinsert.

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
