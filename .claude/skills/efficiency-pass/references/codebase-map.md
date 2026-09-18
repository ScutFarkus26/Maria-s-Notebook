# Codebase map for efficiency work (Cosmic Daybook)

What already exists so a pass extends it instead of re-inventing it, where the
hot paths are, and what has been checked and should not be re-litigated.

## Ground truth about the runtime

- SwiftUI + Core Data + `NSPersistentCloudKitContainer`, two stores (`private.sqlite`,
  `shared.sqlite` for the CKShare-based Daybook Assistant companion).
- Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  Anything meant to run off the main actor must be marked `nonisolated` (types, free
  functions, statics). Core Data work on a background context lives in nonisolated code.
- Deployment target iOS 27 / macOS 27. Every iOS 26 and 27 API is available unconditionally.
- View contexts use `automaticallyMergesChangesFromParent`, so **every CloudKit import
  tick re-evaluates every visible body**. This is why per-body cost matters more here than
  in a typical app.
- Targets that share code: `Cosmic Daybook` (iOS + macOS) and `Daybook Assistant`
  (macOS companion). The Assistant has an explicit source list in `project.pbxproj`; a new
  AppCore/Services file the shared code calls must be added there by hand or its build breaks.

## Helpers to reuse (never duplicate these)

| Need | Use | Where |
|---|---|---|
| "Is now a bad time for discretionary work?" | `EnergyPolicy.shared.shouldDeferMaintenance` (thermal `.serious`+ or Low Power Mode) | `Utils/EnergyPolicy.swift` |
| Drop caches under pressure | observe `.memoryPressureDetected`, or clear from `AppDependencies.handleMemoryPressure` | `AppCore/AppDependencies.swift`, `Services/MemoryPressureMonitor.swift` |
| Date formatting | the static formatters on `DateFormatters` (~18) | `Utils/DateFormatters.swift` |
| Calendar math | `AppCalendar.shared`; Hebrew: `HebrewParshaService.gregorian` / `.hebrew` | `AppCore/AppCalendar.swift` |
| Thumbnail from a Core Data blob | `CachedThumbnail.image(from:cacheKey:)` | `Components/CachedThumbnail.swift` |
| Image from a file in the photos dir | `AsyncCachedImage` | `Components/AsyncCachedImage.swift` |
| Post-import dedup, scoped to what an import inserted | `DeduplicationCoordinator.requestDeduplication(insertedEntities:)` from the history processor; `requestDeduplicationAfterImport()` is the full-sweep safety net | `Services/DeduplicationCoordinator.swift` |
| Debounced remote-change handling | `CloudKitSyncStatusService.scheduleRemoteChangeHandling` (500 ms) | `Services/CloudKitSyncStatusService.swift` |
| Sync event log | `SyncEventLogger` (coalesces repeats, 1 s debounced write) | `Services/` |
| Preceding-lesson lookups in a loop | `BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)` | Services |
| Entity-scoped reaction to remote changes | `PersistentHistoryProcessor.processHistory` (posts `.schoolDayDataDidChange` etc.) | Services |
| Zone repair gating | `SharedStoreZoneRepair+HistoryGate` (`gateDecision`, clean watermark) | Services |
| Launch timing | `LaunchSignposts.begin/end` (category `Launch`) | `Utils/LaunchSignposts.swift` |
| Ad-hoc timing of a query | `PerformanceLogger.measure(screenName:itemCount:)` | `Utils/PerformanceLogger.swift` |
| Background/scheduled work | `BackupBackgroundTaskManager` (BGTaskScheduler registration pattern) | `AppCore/BackupBackgroundTaskManager.swift` |
| Network reachability | `CloudKitSyncStatusService.shared` (owns the single `NWPathMonitor`); never start a second | Services |
| Midnight / day change | `.onCalendarDayChange` modifier | `Utils/View+CalendarDayChange.swift` |

Services that already consult `EnergyPolicy`: `AppBootstrapper` (post-launch migrations),
startup Spotlight/search reindex, `AutoBackupManager`, `AlbumLibrary.buildIndexes`,
`SharedStoreZoneRepair`, `DeduplicationCoordinator`. A new piece of self-initiated work
should join that list; user-initiated work (Sync Now, a manual backup, a search) must not.

## Where the energy goes (by pipeline)

1. **Sync and maintenance pipeline** (runs all school day, screen on or off): remote-change
   notifications → history processing → dedup → zone repair → Spotlight/search reindex →
   auto backup. Fixed in the 2026-09-10 heat audit (history-gated, debounced, background
   context). The 2026-09-17 pass closed the last of the listed leftovers: the post-import
   dedup is now scoped by `DeduplicationScope` to the entities the history processor saw
   inserted (an import that inserts nothing runs no pass), the same-name lesson and
   same-title track merges read only their key columns before materialising anything,
   and attendance/album indexing had already been fixed (column pre-check; `.utility`).
   Only the launch pass and the import-event safety net still sweep every entity.
2. **View layer**: computed properties doing filter/sort/group per body pass (the audit
   script ranks these by read count); per-keystroke search in `AppSearchView` with no
   debounce. The per-card `@FetchRequest`s in `PresentationPill`, `PresentationPlannerCard`
   and `PracticeSessionCard` were removed in the 2026-09-10 audit (cards now take
   non-optional arrays from the parent); do not go looking for them.
3. **Per-student loaders**: `StudentProgressTabViewModel.load` pulls 8 whole tables per
   student; `SequenceTrackService` refetches whole tables per (student, lesson) cell in
   checklist batch loops.
4. **Memory residents**: `AlbumLibrary` (page text of every album PDF, covers, embeddings;
   now pressure-aware), `ImageCache`, `SearchIndexService` (ids only now), the
   `PresentationRecordIndex`.

## Verified OK on 2026-09-10 (do not re-audit unless the code changed)

All `repeatForever` animations are gated or bounded; RootView / StudentsView / WorksAgenda
observers are debounced; EventKit syncs are throttled to 10 min; backups are change-gated;
image caches are bounded; `NWPathMonitor` is a single shared instance with a cancelling holder.

## Traps specific to this repo

- `.NSPersistentStoreRemoteChange` carries only a history token; reading
  `NSInsertedObjectsKey` etc. off it is always empty and a filter built on it fails open.
- Never create, delete, or move a CKShare zone. The 13-zone fragmentation came from an
  unguarded auto-create.
- The macOS test host is the real app; its startup runs launch repairs on the live store.
  Run the suite on the iOS simulator unless a fresh backup exists.
- `-only-testing` that matches nothing still prints `** TEST SUCCEEDED **`. Run the whole
  suite, and read failures from the `.xcresult` (the log does not contain them).
- Two `xcodebuild`s at once lock the build DB. Serial only. Never pipe xcodebuild through
  `tail`: the exit code becomes tail's.
- Two Core Data models in one process (migration-style tests) crash the `CD…(context:)`
  initialisers; use `NSEntityDescription.insertNewObject(forEntityName:into:)`.
- The 100 ms type-check warning is per file; long `+` interpolation chains and literal date
  arithmetic inside `#expect` are the usual cause. Only a clean build shows them.
- Agent worktrees can start many commits behind `main`, and worktrees created before
  2026-09-15 still have the app folder and project named `Maria's Notebook` (the scripts
  detect this). Check `git merge-base HEAD main` first. If you are behind and the files you
  will touch changed on `main` (`git diff --stat HEAD...main -- <files>`), stay on your base,
  do the work, and say in the report that the diff needs a merge against `main`; do not
  rebase or merge on your own inside an eval or agent run.
- This Mac has two simulators named "iPhone 17" and two named "iPhone 17 Pro". Pass
  `SIM_ID=<UDID>` to `verify.sh` (from `xcrun simctl list devices available`) when it matters.
- SwiftLint config is `Cosmic Daybook/.swiftlint.yml` (the Edit/Write hook runs it). Some
  files carry pre-existing `file_length` / `type_body_length` violations; check a baseline.
- Timing tests under the parallel suite must poll with a deadline, never sleep a fixed
  interval; main-actor tasks can wait seconds for a turn.
