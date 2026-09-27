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
- `SWIFT_APPROACHABLE_CONCURRENCY = YES` turns on `NonisolatedNonsendingByDefault`: a
  `nonisolated async` function runs on its **caller's** actor, so one called from main-actor
  code runs on the main thread. Only `@concurrent` leaves the main actor (2026-09-25: backup
  encode/encrypt/verify ran on main despite comments saying otherwise).
- Targets that share code: `Cosmic Daybook` (iOS + macOS) and `Daybook Assistant`
  (an iPhone/iPad companion: `SDKROOT = iphoneos`, no Catalyst). The Assistant has an explicit
  source list in `project.pbxproj`; a new AppCore/Services file the shared code calls must be
  added there by hand or its build breaks.

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
| Entity-scoped reaction to remote changes | `PersistentHistoryProcessor.readHistory(after:author:in:)`, one position per store (the actor posts `.schoolDayDataDidChange` etc.) | `Services/PersistentHistoryProcessor+StoreHistory.swift` |
| Zone repair gating | `SharedStoreZoneRepair+HistoryGate` (`gateDecision`, clean watermark; since 2026-09-26 a clean history pass advances the watermark too, so each pass reads only what arrived since the last) | Services |
| Launch repairs | `MigrationRunner.runIfNeeded(coreDataStack:includeIntegrityRepairs:)`: every launch repair in one background-context pass (the two whole-table assignment repairs one launch in ten, as before); nothing on the view context | `Services/MigrationRunner.swift` |
| Delete old per-day rows | `TodayRetentionCleanup.startIfDue(for:)`: background context at `.utility`, once per store per day (`TodayRetentionCleanupGate`), same cutoff and caps as the old main-thread cleanup | `Today/Support/TodayRetentionCleanup.swift` |
| Launch timing | `LaunchSignposts.begin/end` (category `Launch`) | `Utils/LaunchSignposts.swift` |
| Ad-hoc timing of a query | `PerformanceLogger.measure(screenName:itemCount:)` | `Utils/PerformanceLogger.swift` |
| Background/scheduled work | `BackupBackgroundTaskManager` (BGTaskScheduler registration pattern) | `AppCore/BackupBackgroundTaskManager.swift` |
| Network reachability | `CloudKitSyncStatusService.shared` (owns the single `NWPathMonitor`); never start a second | Services |
| Midnight / day change | `.onCalendarDayChange` modifier | `Utils/View+CalendarDayChange.swift` |
| Keep a derived value until one of its entities changes (rebuild on next read) | `ManagedObjectChangeFlag(entityNames:context:)` + `consume(pendingIn:)`: set synchronously by ObjectsDidChange on the context, DidSave on the same coordinator, `.presentationDataDidChange`, or a reset; also sees unannounced pending edits. Used by Today's ready queue and the Students roster memo. A watcher that must hear only its own store passes `listensForImportSignal: false` (that signal names no store) | `Utils/ManagedObjectChangeFlag.swift` |
| Read the whole model across several main-actor turns and know it was one moment | `BackupSnapshotWatch` (the flag without the import signal, asked after each type, then persistent history at the end); `BackupWriter+Streaming` streams the export one entity type at a time and falls back to the one-pass collect on any change or unsaved edit | `Backup/Archive/` |
| Fold presentation records without making managed objects | `PresentationRecordIndex` reads dictionary rows of just its columns (`+Rows`); the managed-object read still runs when the context holds pending edits of the three entities, in a child context, and for lesson-scoped builds | `Services/PresentationRecordIndex+Rows.swift` |
| Build a whole-record index off the main thread | `PresentationRecordIndex.readInBackground(students:from:)` (`@concurrent`, own private context on the coordinator) — only when `readPath` says the view context would take the column read; Today numbers every rebuild (`readyForNextGeneration`) so an overtaken one never publishes | `Services/PresentationRecordIndex+Background.swift`, `Today/ViewModels/TodayViewModel+ReadyForNext.swift` |
| Resolve a file URL once per stored bookmark/path, not per redraw | `DocumentFileURLMemo` in `@State` (taps still resolve afresh) — Student Files cards, Book Club Open PDF, Resource detail | `Utils/DocumentFileURLMemo.swift` |
| The iCloud Documents container URL without blocking the main thread | `UbiquityContainerCache` (looked up off-main at launch and on account change; each read checks the identity token) behind `…FileStorage.directory()`, `BackupFolderStorage` and the note-photo folder | `Utils/UbiquityContainerCache.swift` |
| Read, write or delete a file in the iCloud container | `UbiquitousFile`: `isAvailable` / `needsDownload` (iOS `.name.icloud` placeholders, macOS dataless), `ensureLocal` / `localURL(for:)` (async coordinated read, waits for the download, 60 s cap, off-main), `coordinatedWrite` / `Copy` / `Move` / `Delete` / `Replace`. Reads of files already local stay uncoordinated (write-once names). On iPhone/iPad `UbiquitousDownloadSweep` requests every not-current file once per launch/foreground (≥ 1 h apart, `EnergyPolicy`-gated, backups skipped) | `Utils/UbiquitousFile.swift`, `Services/UbiquitousDownloadSweep.swift` |
| Parse CSV | `CSVParser`, which reads through `CSVRecordScanner` (the text's UTF-8 bytes, not an `Array` of 16-byte `Character`s) and falls back to the character reader when a delimiter touches a non-ASCII neighbour; `LegacyCSVParser` in the tests is the old parser verbatim | `Utils/CSVRecordScanner.swift`, `Utils/CSVUtils.swift` |
| A lesson by id in a view body (no table scan) | `lessonCatalog.lesson(id:in:)`: the catalog's row when it belongs to that context and isn't deleted, else the old `object(_:id:)` fetch | `Lessons/LessonCatalog+ContextLookup.swift` |
| Lessons in the Lessons screen's order / any derived catalog order | `LessonCatalog.sortedByAreaSortIndexAndOrder` (area, sortIndex, orderInSequence); derived orders rebuild on first read behind the observed `version` — read `version` in a body that must refresh on any lesson change | `Lessons/LessonCatalog.swift` |
| Keep a value built from saved sequence/section orders | `FilterOrderStore.revision` (bumped on every save and cache reset); `MapLayoutMemo` keys the Lessons map's sections on it plus catalog version, area and spine | `Components/FilterOrderStore.swift`, `Lessons/LessonsScopeMapLayout.swift` |
| Menu-bar actions that don't rebuild menus per body pass | a reference-type focused value filled in `onAppear` (`FocusedSearchAction`, `QuickCaptureActions`, `AlbumFocusActions`), never a struct of closures | `AppCore/AppCommands.swift`, `Albums/AlbumModels.swift` |
| Pace streamed text onto the screen | `StreamingTextThrottle` (≤ 10 updates/s, always flushes the last text) | `Chat/StreamingTextThrottle.swift` |
| Reload only while a screen is on screen (TabView keeps visited tabs alive with live `.onReceive`/`.onChange`) | `.onChangeWhenVisible(of:catchUpOnAppear:)` / `.onReceiveWhenVisible(_:catchUpOnAppear:)`: hidden = mark stale, run once on reappear (pass `false` when the screen's own `.task`/`.onAppear` already reloads). Since 2026-09-25 they also treat a Mac window nobody can see (minimized, covered, other Space) as hidden and catch up once when it's visible again, whatever `catchUpOnAppear` says. Wired (2026-09-23): Students DidSave token refresh, Progress, Presentations (pending tokens → change tokens), Works Agenda DidSave, Week plan check-ins, the desktop companion's counts, Albums' activation refresh (`ClassCurriculumMapView` needs nothing: its watcher runs inside `.task`, which is cancelled while hidden) | `Utils/View+WhenVisible.swift`, `Utils/WhenVisibleGate.swift` |
| Know whether a Mac window can be seen (SwiftUI and `scenePhase` don't report occlusion) | `.onWindowVisibilityChange { visible in … }` (a zero-size `WindowOcclusionProbe` watching its own window; no-op on iOS) | `Utils/View+WindowOcclusion.swift`, `Components/WindowOcclusionProbe.swift` |
| Show the main window from AppKit or the companion | `MainWindowRegistry.bringMostRecentForward()` (weak registry filled by `EnsureResizableWindow`); `openWindow(id: "mainWindow")` only when none is open | `AppCore/MainWindowRegistry.swift` |
| Answer a notification every main window hears exactly once | `MainWindowRegistry.shared.answersRequests(in:)` (`MainWindowCandidate.indexToAnswer`: most recently used open main window); `OpenWindowOnNotificationModifier` does it for its four window requests | `AppCore/MainWindowRegistry.swift` |
| App-wide services (bootstrap, sync status, pushes, backups, Spotlight, MCP) | `AppServicesLauncher.startIfNeeded` — once per process, from the first main window's `.task` or, for an MCP-only launch, the app delegate | `AppCore/AppServicesLauncher.swift` |
| Act on scene activation only when the day, school calendar or counter epoch changed | `.onCalendarDayChange` (via `CalendarDayActivationGate`) | `Utils/View+CalendarDayChange.swift`, `Utils/CalendarDayActivationGate.swift` |
| Copy EventKit data into Core Data without rewriting unchanged rows | `EventKitMirror` (assign only differing fields; stamp `lastSyncedAt` only on new/changed rows) | `Services/EventKitMirror.swift` |
| Drop rebuildable caches when the app goes idle (the Mac almost never sends memory pressure) | `AppDependencies.trimIdleMemory(reason:)` → `AlbumLibrary.releaseMemory(critical: false)` only (image cache left alone by Danny's choice); iOS on `.background`, Mac 10 min after resign-active or when the last main window closes (`IdleMemoryTrimPolicy`, `IdleMemoryTrimController`). Never posts `.memoryPressureDetected` | `AppCore/` |
| Reload on presentation/lesson changes only while visible | `.onPresentationDataChangeWhenVisible` (the Presentations counter pattern packaged; the counter lives in the modifier) | `Utils/View+PresentationDataChangeWhenVisible.swift` |
| Decode or save a photo without a full-size decode | `PhotoImageIO` (ImageIO thumbnails at display size, `CGImageDestination` transcode that matches the old output byte for byte); `CachedPhotoLoader` for disk hits off the main thread; `ImageCache` budget 32 MB | `Services/PhotoImageIO.swift`, `Components/CachedPhotoLoader.swift` |
| A first-page thumbnail of a student's PDF | `StudentFileThumbnailCache` (rendered once per file version, cached on disk; no live `PDFView`) | `Students/Files/` |
| An album's outline, lessons and page count without keeping its PDF open | `AlbumContents` (read once); `Album.document` opens on demand and `releaseDocument()` closes it (called by `releaseMemory` at both levels) | `Albums/AlbumContents.swift`, `Albums/AlbumLibrary.swift` |
| Album search text, vectors and saves | `AlbumTextFolds` (fold off-main, once per album, on first search), `AlbumPageTextReader` (reopens the PDF every 50 pages), `AlbumVectorCacheFile` (raw Float32 cache), `AlbumSaveDebouncer` (per-key debounce: ink by page, position by album; flush on disappear/background) | `Albums/` |
| Release something after a quiet period (resettable, injected clock) | `IdleCountdown` (used for the album query model: released 5 min after the last search) | `Albums/IdleCountdown.swift` |
| Mac maintenance on a schedule | `ScheduledBackupActivity` (`NSBackgroundActivityScheduler`, 10% tolerance, `.utility`, honours `shouldDefer`); timing in `ScheduledBackupTiming` | `Backup/Core/` |

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
   debounce. The per-card `@FetchRequest`s in `PresentationPlannerCard` and
   `PracticeSessionCard` (and the since-deleted `PresentationPill`) were removed in the 2026-09-10 audit (cards now take
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
5. **The 2026-09-25 "Energy Fifty" audit** (private artifact "Daybook Energy Fifty"; baseline
   and per-item numbers in `perf-baselines/2026-09-25-energy-fifty-wave1.md`) lists 50 items by
   number. Wave one landed 2026-09-25: items 17, 19–21, 23, 24 and 26–36 (29 as the memo half
   only; 32 without the Progress Dashboard row). Wave two landed the same day
   (`perf-baselines/2026-09-25-energy-fifty-wave2.md`): 2, 3, 4, 6–11, 15, 16, 18, 48, 50 — the MCP
   bridge and MCP-only launch, occlusion-aware gates, services once per process, EventKit
   mirrors writing only changed rows, backup encoding `@concurrent`, the Mac backup on
   `NSBackgroundActivityScheduler`. 49 (the Assistant's push background mode) was left as is.
   Wave three landed the same day (`perf-baselines/2026-09-26-energy-fifty-wave3.md`): 5, 37–41,
   44–47 — idle trims, album covers/PDFs/model/canvases, photo attach and cache, Student Files
   thumbnails, the remaining hidden iPad tabs, UIKit memory warnings.
   Wave four landed 2026-09-26 (`perf-baselines/2026-09-26-energy-fifty-wave4.md`): 12, 13, 25,
   43 — launch repairs and the Today cleanup off the main thread, the zone-repair watermark on
   clean passes, the presentation index from column rows, the streamed backup export.
   Wave five landed 2026-09-27 (`perf-baselines/2026-09-27-energy-fifty-wave5.md`): 42 and the
   remaining halves of 25 and 43 — album vectors as raw floats, folds off-main, extraction reopening
   the PDF, Today's index read off the main thread, restore holding the backup once — plus six bugs
   from the audit's margins. 14 landed separately (per-store history cursor, 74d767f1). Still open:
   1 (Danny now runs the Release copy; re-take the baseline); 22 parked, 49 left by decision.

## Found by the audit rules on 2026-09-27, not yet fixed

The twelve rules added that day flag these on main 20e21cbd; each is a real candidate:

- `model_built_in_view_init`: `QuickNoteSheet` (two inits), `AIPlanningAssistantView`,
  `DataManagementGrid`, `StudentDetailView`, `WorkDetailView` build their model in `init` (a new
  one per parent redraw, as TodayView did).
- `file_resolve_in_view`: `LessonDetailView+FileHandling.resolveLessonFileURL()` is read from the
  view's body.
- `heavy_loop_without_pool`: `StoryAnalyzer` reads PDF pages in two loops with no pool;
  `StoryLessonMatcher` embeds word by word.
- `ubiquity_container_lookup`: none since 2026-09-27 (`BackupFolderStorage` now reads `UbiquityContainerCache`).
- `open_window_call`: the Keyboard Shortcuts `WindowGroup` (pressing ⌘/ twice opens a second
  window; a `Window` scene would not).

## Verified OK on 2026-09-10 (do not re-audit unless the code changed)

All `repeatForever` animations are gated or bounded; RootView / StudentsView / WorksAgenda
observers are debounced; EventKit syncs are throttled to 10 min; backups are change-gated;
image caches are bounded; `NWPathMonitor` is a single shared instance with a cancelling holder.

## Traps specific to this repo

- `.NSPersistentStoreRemoteChange` carries only a history token; reading
  `NSInsertedObjectsKey` etc. off it is always empty and a filter built on it fails open.
- A history token read from a transaction covers only that transaction's store, and a fetch
  given a token ignores `affectedStores`. A cursor that has to see both stores keeps one
  token per store (as `PersistentHistoryProcessor` does); one shared token silently stops
  reading the other store. Pinned by `PersistentHistoryTokenScopeTests`.
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
- Simulator names can repeat on this Mac. `verify.sh` takes the first available device named
  `SIM_NAME` (default "iPhone 17"); pass `SIM_ID=<UDID>` (from `xcrun simctl list devices
  available`) when it matters, and give each parallel agent its own device.
- SwiftLint config is `Cosmic Daybook/.swiftlint.yml` (the Edit/Write hook runs it). Some
  files carry pre-existing `file_length` / `type_body_length` violations; check a baseline.
- Timing tests under the parallel suite must poll with a deadline, never sleep a fixed
  interval; main-actor tasks can wait seconds for a turn. The other half: keep synchronous
  `@MainActor` tests light. One that seeds thousands of rows and collects without an `await`
  holds the main actor for its whole run; on 2026-09-26, with four such tests newly added
  and another build loading the Mac, `StreamingTextThrottleTests` missed its 10 s window.
  Seed only the types a test needs.
- `.contextMenu { … }` (and any non-escaping `@ViewBuilder` closure argument) runs on every
  body pass of its view. A fetch or lookup inside it belongs in a nested `View`'s body, which
  only runs when the menu is shown (`SameWorkPeersMenu`, `WorkCardStatusMenu`).
- A `@FetchRequest` built in a view's `init` is put back every time the parent re-creates the
  view, undoing any later `nsPredicate` change. "Narrow the fetch on appear" silently reverts
  to the init request after a parent redraw (the attendance log does this today).
- On iOS 27 a `LazyVStack` rebuilds rows that scroll far away: fresh `@State`, and inner
  horizontal scroll views reset to their start. Lifting pin state isn't enough; that is why
  the Lessons map stayed eager.
- Chat answers do not stream: `ChatService` calls `streamConversation` without `timeout:`, so
  the protocol's non-streaming default runs and each answer arrives in one piece.
- Adding a predicate can make SQLite pick another index (check `EXPLAIN QUERY PLAN`), which
  changes the row order of a fetch without complete sort descriptors, and so which rows a
  capped read keeps.
- `verify.sh` was rewritten on 2026-09-27: every build goes through the lock (the Assistant on
  the iOS simulator — it does not build for macOS), the suite runs with `test-without-building`
  (verdict line `** TEST EXECUTE SUCCEEDED **`), and the totals and failures come from `xcrun
  xcresulttool get test-results summary`. A hand-rolled gate should do the same.
- `AlbumSemanticBackendTests` need the sentence-embedding model, which the iPhone 17 simulator
  loads in ~100 ms and the iPhone Air / iPhone 17e simulators never load. Run gates on iPhone 17;
  on the others those two tests fail (and can starve main-actor timing tests such as
  `StreamingTextThrottleTests.scheduledUpdateArrives`).
- An in-memory store gets `fetchOffset` + `fetchLimit` wrong on an unsorted fetch (the second
  1,000-row page of 1,205 notes held one row). Page only SQLite stores, or sort.
- On macOS 27 a split view's detail column is not a navigation stack: a root screen that pushes
  (`NavigationLink(value:)`, `.navigationDestination`) must own a `NavigationStack` on every platform.
- Memory-pressure events can arrive merged (`[.warning, .critical]`): test with `contains`.
- A `@State` value assigned in `init` is built on every init of the view (SwiftUI keeps the first);
  make an `@Observable` model lazily in the owning view (`TodayRootView`) instead.
- Restore's import is one main-actor turn from the replace-mode clear to the save; never add an
  `await` inside it (see CLAUDE.md, Backup System).
- `.presentationDataDidChange` is process-wide and names no store. Anything that must react
  only to its own store must not listen to it: under the parallel suite other tests' stacks post
  it, and on 2026-09-26 that sent every streamed backup export in the suite back to one pass
  (five failures that each test file alone never showed).
- Off the main thread, `.background` QoS work waited up to 50 s while builds loaded the Mac
  (2026-09-26). Use `.utility` for work a test or the guide waits on.
- `PersistentHistoryProcessor` keeps one history token for the two-store container, and from
  then on reads only that token's store. If the newest transaction when its cursor was empty
  came from the shared store, it stops seeing private-store imports (no post-import dedup, no
  entity notifications). Energy Fifty item 14; a correctness risk, not yet fixed.
