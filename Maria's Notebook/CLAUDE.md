# CLAUDE.md - Maria's Notebook

## Project Overview

Maria's Notebook is a comprehensive teacher planning and classroom management app for iOS/macOS, built with SwiftUI. It helps Montessori educators manage students, lessons, work tracking, attendance, and classroom observations.

**Tech Stack:**
- Swift 6.0 / SwiftUI
- Core Data + NSPersistentCloudKitContainer (two-store architecture)
- iOS 27.0+ / macOS 27.0+ / visionOS 27.0+ (27.0 SDKs are beta until the fall GM)
- Xcode 27.0 beta+ (currently `~/Downloads/Xcode-beta.app`; `/Applications/Xcode.app` is still 26.5)

## Build & Run

```bash
# Open project (in the 27-beta Xcode)
open -a "$HOME/Downloads/Xcode-beta.app" "Maria's Notebook.xcodeproj"

# Build from command line — needs the 27.0 SDKs, so point DEVELOPER_DIR at the beta
# (drop the prefix once Xcode 27 GM replaces /Applications/Xcode.app in the fall)
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0" build

# Run unit tests
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild test -project "Maria's Notebook.xcodeproj" -scheme "Maria's Notebook" -destination "platform=iOS Simulator,name=iPhone 17,OS=27.0"
```

## Project Structure

```
Maria's Notebook/
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
├── Issues/           # Issue tracking
├── Logs/             # Application logging
├── Procedures/       # Procedure documentation
├── Progression/      # Student progress tracking & analytics
├── Projects/         # Project management & sessions
├── Resources/        # Educational resources
├── Supplies/         # Supply inventory
├── Topics/           # Educational topics
├── PerpetualCalendar/# Calendar notes
│
├── Sharing/          # CloudKit sharing (classroom collaboration)
├── Backup/           # Backup & restore functionality
├── Settings/         # App configuration
└── MariasNotebook.xcdatamodeld/ # Core Data model

Maria's Notebook Tests/ # Feature-mirrored test target
Scripts/                 # Repository structure checks
Documentation/           # Repository-level architecture, ADRs, plans, and manuals
```

## Architecture

**MVVM with Services pattern:**
- **Views** — SwiftUI views using `@FetchRequest` for data binding
- **ViewModels** — `@Observable @MainActor` classes for complex state
- **Services** — Business logic operations (50+ services)
- **Models** — `NSManagedObject` subclasses with `CD` prefix (76 entities)

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

**76 entities** defined in `MariasNotebook.xcdatamodeld`.

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

- Container: `iCloud.DanielSDeBerry.MariasNoteBook`
- Two persistent stores: private (teacher data) + shared (classroom data)
- Schema changes must be additive-only after CloudKit deployment
- All models use string-based foreign keys for sync compatibility
- **Shared-store zone repair:** `SharedStoreZoneRepair` (Services/SharedStoreZoneRepair.swift) detects records in the shared store that aren't assigned to a CKShare zone — these poison `NSCloudKitMirroringDelegate` with `NSCocoaErrorDomain 134060`. It runs at the end of post-launch migrations, after each post-import dedup pass, and when `ClassroomSharingService.isSharing` transitions `false → true`. Lead guides also see a banner + "Repair Sync Errors" button in Settings → Classroom Sharing.

### Known beta-SDK build warnings (Xcode 27 beta 1)

- `@Generable` macro expansions reference the deprecated `GenerationError.decodingFailure` internally. The warning comes from Apple's macro-generated code, not project source, and cannot be fixed here — re-check on each new Xcode 27 seed and drop this note once Apple fixes the macro.
- `SpeechRecognitionService.installRecognitionTap` suppresses the `installTap` deprecation via Swift 6.4's `@diagnose` attribute: the refined replacement (`installAudioTap`) delivers `AVReadOnlyAudioPCMBuffer`, which `SFSpeechAudioBufferRecognitionRequest.append` cannot accept in beta 1. Re-check each seed and migrate when Speech catches up.

### Console log noise to ignore

These come from Apple's frameworks, not this app — they are not actionable in source:

- `updateTaskRequest called for an already running/updated task com.apple.coredata.cloudkit.activity.export.*` (subsystem `com.apple.BackgroundSystemTasks`, category `BGSTFramework`) — `NSPersistentCloudKitContainer` internals managing background export tasks.
- `updateTaskRequest failed for com.apple.coredata.cloudkit.activity.export.*` and `Error updating background task request: BGSystemTaskSchedulerErrorDomain Code=3` — same source; benign when sync is otherwise working.

**Filter in Console.app:** exclude subsystem `com.apple.BackgroundSystemTasks`.
**Noisy Xcode debug runs:** set `OS_ACTIVITY_MODE=disable` in the scheme's environment variables.

## Backup System

- **Current write format: v19 (encrypted Apple Archive)**. Files are genuine Apple Encrypted Archives — first 4 bytes are `AEA1`, AES-CTR + HMAC via `ArchiveEncryptionContext` (profile `hkdf_sha256_aesctr_hmac__symmetric__none`), with LZFSE compression inside the AEA layer. The 256-bit symmetric key lives in the **iCloud Keychain** (`Backup/Archive/BackupEncryptionKeyStore.swift`, `kSecAttrSynchronizable` + `kSecAttrAccessibleAfterFirstUnlock`) so a backup written on one device restores on any device on the same Apple ID. Files are written `0600`. Contents: a `manifest.json` first entry (format version + entity counts + origin-store routing), `preferences.json`, then one NDJSON entry per Core Data entity type, prefixed `private/` or `shared/` to indicate origin store.
- **Read support: v17–v19** (`BackupReader.supportedFormatVersions`). v19 is the encrypted container; v17/v18 are plain LZFSE Apple Archives (magic `pbz*`) and still read so older backups and checkpoints restore. `BackupArchive.isBackupArchive(at:)` accepts both magics; `isEncryptedArchive(at:)` distinguishes them. **Legacy v5–v16 JSON-envelope `.mtbbackup` files cannot be read by the app at all** — that decoder was removed; use the external recovery process referenced in `Documentation/Architecture/BACKUP_SYSTEM.md`. The repo's own `Backups/*.mtbbackup` through 2026-04-01 are all this unreadable legacy format.
- Top-level entry point: `Backup/Archive/BackupCoordinator.swift`. UI calls `coordinator.exportBackup`, `coordinator.previewImport`, `coordinator.importBackup`.
- **Threading:** payload collection runs on the main actor (Core Data view-context queue); NDJSON encode, encryption, archive write, read-back verification, and decode all run off the main actor (`BackupWriter.encodeAndWrite`, `BackupImporter.decodeArchive` are `nonisolated async`).
- **Integrity:** export writes to a hidden temp file in the destination dir, re-reads it (`BackupReader.verifyStructure` — streams the whole archive, checks the manifest decodes and per-entity NDJSON row counts match), then atomically renames into place. An encode failure for any entity type aborts the whole export (`BackupWriter.WriterError`) rather than silently dropping data; a malformed entry on read surfaces as a warning in `BackupOperationSummary`.
- Auto-backup on macOS quit (`applicationShouldTerminate` → `.terminateLater`), on iOS scene-phase `.background` + a `BGProcessingTask` (`AppCore/BackupBackgroundTaskManager.swift`, id `DanielSDeBerry.MariasNoteBook.backup`), plus a configurable in-app interval loop; retention default 10. All automatic triggers are **change-gated** via persistent history (`Backup/Core/BackupChangeTracker.swift`) — an untouched dataset skips the backup. Honors the user's chosen destination folder.
- Restore goes through `BackupTransactionManager.executeWithRollback` (safety checkpoint + auto-rollback on failure). Checkpoints are written in the current v19 format via `BackupWriter`.
- Restore existence/relationship checks use `BackupEntityIndex` (one fetch per entity type, built lazily so child types see parents inserted earlier in the same restore) — not a fetch-request-per-record. Preview uses `EntityIDIndexCache` (one id-set fetch per type).
- The post-restore CloudKit export wait subscribes to `NSPersistentCloudKitContainer.eventChangedNotification` **before** `viewContext.save()` so a fast export isn't missed (`BackupService+Restoration.swift`).
- `replace` mode uses context-level deletes (NOT `NSBatchDeleteRequest`) so CloudKit mirroring sees proper delete tombstones.
- **Entity coverage is test-enforced:** `BackupCoverageTests` asserts `BackupEntityRegistry.allTypes` ≡ `BackupWriter.serializedEntityNames` ≡ `BackupImporter.handledEntityNames`, and that every model entity is either backed up or in an explicit, documented exclusion list (the 8 removed-feature tombstones). Adding an entity without backup coverage is a red test, not a future format version.
- Entity registry: `Backup/Core/BackupEntityRegistry.swift`. Per-entity DTO transformers in `Backup/Export/BackupDTOTransformers*.swift`. Per-entity importers in `Backup/Import/BackupEntityImporter+*.swift` (well-factored static methods).
