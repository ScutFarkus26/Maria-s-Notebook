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
| Post-import dedup, scoped to what an import inserted | `DeduplicationCoordinator.requestDeduplication(insertedEntities:)` from the history processor; an import event alone (`requestDeduplicationAfterImport()`) runs nothing; a failed history read asks for the full sweep | `Services/DeduplicationCoordinator.swift` |
| Debounced remote-change handling | `CloudKitSyncStatusService.scheduleRemoteChangeHandling` (500 ms) | `Services/CloudKitSyncStatusService.swift` |
| Sync event log | `SyncEventLogger` (coalesces repeats, 1 s debounced write) | `Services/` |
| Scoped reads for a sequence / track / student | `SequenceTrackService+ScopedReads` (`sequenceLessons`, `trackCandidates`, …) | Services |
| Preceding-lesson lookups in a loop | `BlockingAlgorithmEngine.buildPrecedingLessonCache(lessons)` | Services |
| Entity-scoped reaction to remote changes | `PersistentHistoryProcessor.processHistory` (posts `.schoolDayDataDidChange` etc.) | Services |
| Zone repair gating | `SharedStoreZoneRepair+HistoryGate` (`gateDecision`, clean watermark) | Services |
| Launch timing | `LaunchSignposts.begin/end` (category `Launch`) | `Utils/LaunchSignposts.swift` |
| Ad-hoc timing of a query | `PerformanceLogger.measure(screenName:itemCount:)` | `Utils/PerformanceLogger.swift` |
| Background/scheduled work | `BackupBackgroundTaskManager` (BGTaskScheduler registration pattern) | `AppCore/BackupBackgroundTaskManager.swift` |
| Network reachability | `CloudKitSyncStatusService.shared` (owns the single `NWPathMonitor`); never start a second | Services |
| Midnight / day change | `.onCalendarDayChange` modifier | `Utils/View+CalendarDayChange.swift` |
| Keep a derived value until one of its entities changes (rebuild on next read) | `ManagedObjectChangeFlag(entityNames:context:)` + `consume(pendingIn:)`: set synchronously by ObjectsDidChange on the context, DidSave on the same coordinator, `.presentationDataDidChange`, or a reset; also sees unannounced pending edits. Used by Today's ready queue and the Students roster memo | `Utils/ManagedObjectChangeFlag.swift` |
| Reload only while a screen is on screen (TabView keeps visited tabs alive with live `.onReceive`/`.onChange`) | `.onChangeWhenVisible(of:catchUpOnAppear:)` / `.onReceiveWhenVisible(_:catchUpOnAppear:)`: hidden = mark stale, run once on reappear (pass `false` when the screen's own `.task`/`.onAppear` already reloads). No-op-safe on macOS, where the split-view detail is torn down. Wired: Students DidSave token refresh, Progress. Not yet wired (2026-09-23): `PresentationsView+Body.swift` onPresentationDataChange → debounce, `WorksAgendaView.swift:~217`, `WeekPlanSection.swift:~104` (`ClassCurriculumMapView` needs nothing: its watcher runs inside `.task`, which is cancelled while hidden) | `Utils/View+WhenVisible.swift` |

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
   An import event with no history report (an empty CloudKit poll) runs no pass; only the
   launch pass and a failed history read still sweep every entity.
2. **View layer**: computed properties doing filter/sort/group per body pass (the audit
   script ranks these by read count); per-keystroke search in `AppSearchView` with no
   debounce. The per-card `@FetchRequest`s in `PresentationPill`, `PresentationPlannerCard`
   and `PracticeSessionCard` were removed in the 2026-09-10 audit (cards now take
   non-optional arrays from the parent); do not go looking for them.
3. **Per-student loaders**: fixed 2026-09-18 (`perf-baselines/2026-09-18-per-student-loaders.md`).
   `StudentProgressTabViewModel.loadData` fetches by student / active track and looks
   lessons up one at a time; `SequenceTrackService` reads through
   `SequenceTrackService+ScopedReads` (a `CONTAINS[cd]` superset of the trimmed,
   case-insensitive match it still applies in memory). Both keep managed-object
   fetches so unsaved rows in the caller's context are still seen. Remaining
   per-student whole-table reads: `StudentAnalysisService` (Insights) and
   `StudentTrackDetailView` (all lessons + all marks).
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
- `makeSplitStoreContext()` (the SQLite test store) has a shared configuration and no
  CKShare, so `SequenceTrackService.getOrCreateTrack` throws there by design; seed
  tracks directly when a SQLite read test needs one.
- A predicate on a `UUID` attribute needs a `UUID` argument; a `uuidString` matches on
  SQLite and silently finds nothing on the in-memory store (`UUIDPredicateArgumentTests`).
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
