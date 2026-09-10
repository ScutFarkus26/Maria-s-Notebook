# Energy and Heat — Implementation Plan

Status: **Phase 1 on `perf/heat-1-zone-repair-gate`; Phase 2 in progress; Phases 3–5 running in parallel worktrees** · Owner: Danny · Created 2026-09-10

Source: the 2026-09-10 heat audit (recorded in the project memory under
`efficiency-hot-spots`). Earlier passes (2026-08-24, 2026-09-02) already fixed the view-layer
hot spots; this plan covers the sync and maintenance pipeline, which is what runs during a
normal school day whether or not the guide is looking at the screen.

Ground rules for every phase:

- One branch per phase (`perf/heat-<n>-<slug>`), one commit per phase, merged to `main` in
  order. Phases 1 and 2 are the payoff; 3–5 are cheaper and can follow at leisure.
- Build the app **and** the Daybook Assistant target after every phase — `CoreDataStack`,
  `PersistentHistoryProcessor`, and `SharedStoreZoneRepair` compile into both.
- Run the full test suite, not `-only-testing` (a filter that matches nothing still prints
  `** TEST SUCCEEDED **`). Read failures out of the `.xcresult`, not the log.
- Never create, delete, or move a CKShare zone. The 13-zone fragmentation came from an
  unguarded auto-create; every change here must leave share *creation* paths untouched.
- Do not run the macOS test host against the live store without a fresh backup — the test
  host launches the real app and its startup runs the launch repairs.

---

## Phase 1 — Zone repair: run only when something new needs attaching

**Landed 2026-09-10.** `SharedStoreZoneRepair+HistoryGate.swift` (gate decision, clean
watermark under `UserDefaultsKeys.sharedStoreZoneRepairCleanHistoryToken`, cleared by Reset Local
Cache), `+Detection.swift` rewritten to fetch object IDs on a background context, `+Attach.swift`
split out of the main file, `refreshCountsIfNeeded` replaces the 5 s recount (returns when the
history token has not moved). Six tests in `SharedStoreZoneRepairGateTests`. Deviation from the
plan: the orphan guard's inserted-entity names are not threaded through — history is the single
source of truth for the scope, and it also sees remote inserts the guard cannot. Full suite 896/0.

### Problem

`SharedStoreZoneRepair.run` / `refreshCounts` → `collectOrphans`
(`Services/SharedStoreZoneRepair+Detection.swift`) fetches every row of all ~30 shared
entities on the **view context**, then calls `container.fetchShares(matching:)` on the whole id
list (~5,000 records; each id is a join against CloudKit's metadata tables). It runs:

| Trigger | Where | Frequency |
|---|---|---|
| Launch | `AppBootstrapper.runPostLaunchMigrations` (last step) | every launch |
| Any save that inserts a shared entity | `SharedStoreOrphanGuard.handleSave` → 200 ms debounce | every presentation, observation, attendance mark… |
| Every CloudKit import | `DeduplicationCoordinator.runDeduplication` completion | every import batch (minutes of them on first sync) |
| Sharing settings open | `ClassroomSharingView` 5 s loop → `refreshCounts` | every 5 s |
| Share state flips false → true | `ClassroomSharingService.updateShareState` | rare |

### Changes

1. **Persist a "clean" watermark.** After a pass finds zero orphans (or attaches all of them
   with none unrecoverable), store the current persistent-history token under
   `UserDefaultsKeys.zoneRepairCleanHistoryToken` (new key; add it to the synced/backup
   preference lists only if the existing pattern requires it — it is device-local, so probably
   not).
2. **Gate `runIfNeeded` on history.** Before scanning, ask `PersistentHistoryProcessor` (add a
   small nonisolated static `sharedEntityInsertsSince(token:in:)` that reads
   `NSPersistentHistoryChangeRequest.fetchHistory(after:)` with a change-type filter of
   `.insert` and entity names in `CoreDataStack.sharedEntityNames`). If there are none since the
   clean watermark, return without fetching anything. Remote imports of records that already
   sit in a share zone are inserts too, so the gate must also honour the existing
   `repairInProgress`/circuit-breaker guards and must **not** treat "history unavailable" as
   "clean" — fall through to the full scan on any error, exactly as today.
3. **Scope the scan.** `RepairScope.entityNames` becomes the set of shared entity names the
   history query actually saw inserted (plus, on a fallback, the full list). Both the orphan
   guard and the history processor already compute inserted entity names — pass them through
   instead of recomputing.
4. **Move the fetch off the view context.** `collectOrphans` takes a background context from
   `coreDataStack.newBackgroundContext()`, uses `returnsObjectsAsFaults = true` and
   `fetchBatchSize = 500`, and returns `[NSManagedObjectID]` grouped by entity. `attachOrphans`
   already re-materialises by object id on its own background context
   (`SharedStoreZoneRepair+Sharing.swift`), so nothing downstream needs the objects.
   `orphanCount` / `orphansByEntity` remain main-actor observable state, assigned once.
5. **Make the settings tick cheap.** Replace the 5 s `refreshCounts` loop in
   `ClassroomSharingView` with: run once on appear, then re-run only when the history token
   has moved since the last count (reuse the same helper as step 2). Keep the scene-phase guard.
6. **Collapse the two post-import triggers.** `DeduplicationCoordinator` chains a repair after
   every dedup pass; the orphan guard also fires on the saves that dedup itself performs. With
   the history gate in place both become no-ops when nothing needs attaching, so leave the call
   sites and let the gate do the work — do not remove them (they are the safety net after a
   Reset Local Cache).

### Tests (new file `Services/Sync/SharedStoreZoneRepairGateTests.swift`)

- Inserting a non-shared entity (e.g. a todo) after the watermark does not trigger a scan.
- Inserting a shared entity does; the scope contains only that entity name.
- A history fetch error falls through to the full scan.
- The watermark is only advanced after a pass that found nothing to attach.
- `collectOrphans` on a background context returns the same ids as the old view-context path
  (pin equivalence on an in-memory stack with a handful of records).

Use `NSEntityDescription.insertNewObject(forEntityName:into:)` and `NSFetchRequest(entityName:)`
in these tests if a second model is loaded in the process (see the memory note on two-model
crashes).

### Verification

- Launch signpost: `PostLaunchMigrations` interval on the Mac before/after with the production
  store.
- Instruments → Core Data template, or `-com.apple.CoreData.SQLDebug 1`: after recording one
  presentation, confirm there is no `SELECT … FROM ZSTUDENT` / `ZLESSON` / … burst 200 ms later.
- Sharing settings open for 60 s with no edits: zero fetches after the first.

### Risk

A wrong gate that *skips* a needed pass leaves a record outside the share zone, which poisons
the mirroring delegate (`NSCocoaErrorDomain 134060`) until the next successful pass. The
fall-through-on-error rule and the launch-time run (which stays unconditional on the first
launch after an upgrade, because the watermark key is absent) bound that risk.

---

## Phase 2 — Sync status: stop writing to disk per notification

### Problem

`CloudKitSyncStatusService+Observers` schedules `handleRemoteChange()` per
`.NSPersistentStoreRemoteChange`. The "cancel pending task" pattern coalesces nothing because
each task starts immediately. Each call:

- `SyncEventLogger.shared.log(...)` — JSON-encodes 50 events and writes UserDefaults.
- Two more `UserDefaults` writes (last-sync date, error removal).
- Assigns ~8 `@Observable` properties; `@Observable` notifies on every assignment even when the
  value is unchanged, so the three `CompactSyncStatusIndicator` instances in the toolbar and the
  `SyncingFromICloudOverlay` re-render per notification.

`handleSuccessfulCloudKitEvent` logs every `setup`/`import`/`export` event the same way, and
`handleLocalSave` runs per save with the same assignment pattern.

### Changes

1. **Debounce the remote-change handler.** Replace the cancel-and-respawn with a single
   debounced task (`Task.sleep(for: .milliseconds(500))`, cancel-on-new-arrival, run once when
   quiet). The `isImportingFromCloud` overlay logic already tolerates this (it has its own 5 s
   quiet timer).
2. **Assign only on change.** Add a private helper `setIfChanged(_ keyPath:, to:)` (or inline
   `if isSyncing { isSyncing = false }` guards) for every property written in
   `handleRemoteChange`, `handleLocalSave`, `handleCloudKitEvent`, and `updateSyncHealth`.
   `lastSuccessfulSync = now` is the one that legitimately changes every time; keep it, but it
   is only read by Settings, so consider moving it behind the debounce too.
3. **Event logger records transitions, not ticks.** `SyncEventLogger.log` gains a
   `coalesceKey:` — a repeat of the most recent event with the same key within 30 s updates
   that event's timestamp (and a `count`) instead of inserting a new row. Save through a 1 s
   debounced write rather than synchronously. The sync-history Settings view reads
   `events` in memory, so it needs no change beyond showing the count.
4. **UserDefaults writes** for last-sync date move behind the same debounce.

### Tests (`Services/Sync/SyncEventLoggerCoalescingTests.swift`, extend existing status tests
if any)

- 100 `log` calls with the same key within 30 s produce one event with `count == 100`.
- Different keys, or the same key after 30 s, produce separate events.
- Cap of 50 still holds.
- Status service: 50 remote-change notifications in 100 ms yield one `handleRemoteChange`
  (inject a counter or observe the logger).

### Verification

Console/`log stream --predicate 'subsystem == "<app>"'` during a Sync Now: one "Remote changes
received" line per burst instead of dozens. `defaults read` of the sync-history key should not
change size during an idle import.

---

## Phase 3 — Planner cards: one fetch per column, not two per card

### Problem

`WeekDayColumn+Bands.presentationCard` passes `cachedLessons: nil, cachedStudents: nil`, so each
`PresentationPlannerCard` falls back to its own two unpredicated `@FetchRequest`s (all lessons,
all students). Each is a live `NSFetchedResultsController` that diffs on every context change.
`PresentationPill` has the same fallback when created from `Components/DropZone.swift` and
`Inbox/InboxSheetView.swift`. `Work/Practice/PracticeSessionCard.swift` fetches all students and
all work per card with no cache path at all (and nests itself for group sessions).

### Changes

1. `WeekPlanSection` already holds a `@FetchRequest` of lesson assignments; add two `@State`
   arrays (`lessons`, `students`) loaded once in its existing data-load path
   (`WeekPlanSection+Data.swift`) and refreshed on the same triggers it already uses for
   check-ins. Pass them through `WeekDayColumn` (new `let` parameters) into `presentationCard`.
   The drag-preview copy already passes empty arrays; keep that.
2. Give `DropZone` and `InboxSheetView` the same treatment from whatever parent already has
   the arrays (`PresentationsViewModel.lessons` for the overview; the inbox sheet loads its own).
3. **Delete the fallback `@FetchRequest`s** from `PresentationPlannerCard` and
   `PresentationPill` once every call site passes caches — make `cachedLessons`/`cachedStudents`
   non-optional. Leaving them "unused" still constructs the controllers.
4. `PracticeSessionCard`: hoist `allStudents`/`allWork` to `WorkDetailView+PracticeTracking`
   (one fetch, predicated to the work's students) and pass them down; the nested group-session
   cards receive the same arrays.

### Tests

There are no view tests for these; rely on the build plus a manual pass. Add a
`PresentationPlannerCardSnapshotTests` only if snapshot infrastructure already exists (it does
not today — do not add a dependency for this).

### Verification

Instruments → SwiftUI template on the week planner while a background context saves a note:
`PresentationPlannerCard` body count should be zero for cards whose data did not change.
`-com.apple.CoreData.SQLDebug 1`: opening the week planner runs two lesson/student selects
total, not two per card.

---

## Phase 4 — Thermal and Low Power Mode gating

### Problem

Nothing in the app reads `ProcessInfo.processInfo.thermalState` or
`isLowPowerModeEnabled`. Apple's guidance is to defer discretionary work at `.serious` and
above and under Low Power Mode.

### Changes

1. New `Utils/EnergyPolicy.swift`: a small `@MainActor @Observable` singleton exposing
   `shouldDeferMaintenance: Bool` (true when thermal state ≥ `.serious` or Low Power Mode is on),
   fed by `ProcessInfo.thermalStateDidChangeNotification` and
   `.NSProcessInfoPowerStateDidChange`. Hold the observers in a nonisolated holder whose `deinit`
   removes them, matching `NetworkMonitoring.MonitorHolder`.
2. Consult it in: `DeduplicationCoordinator.requestDeduplication` (re-arm the 5 s timer and
   retry later instead of running), `SharedStoreZoneRepair.runIfNeeded` (skip; the Phase 1 gate
   means the next trigger will catch up), `AlbumLibrary.buildIndexes` (pause between albums),
   `SearchIndexService.refresh` and `SpotlightIndexer.reindexAll` (skip this launch — both are
   change-gated and will run next time), and `AutoBackupManager.performScheduledBackup` (defer
   one interval; never defer the quit/background/pre-destructive backups).
3. Never gate user-initiated work (Sync Now, manual repair, manual backup, search).

### Tests

`EnergyPolicyTests`: inject the two inputs and pin the boolean; each call site takes the policy
as a parameter with a default of `.shared` so tests can pass a deferring stub and assert the
work did not run.

---

## Phase 5 — Smaller fetch-shape fixes

Each is independent; land in one commit.

1. **Album text extraction priority.** `AlbumLibrary.buildIndexes` and `loadCoverIfNeeded`
   spawn `Task.detached(priority: .userInitiated)`; change the index pass to `.utility` (covers
   can stay `.userInitiated` — they are on screen). Add an `await Task.yield()` between albums.
2. **Attendance strong dedup pre-check.** `deduplicateAttendanceRecordsStrong` fetches the
   whole table. Add a dictionary fetch (`propertiesToFetch: ["studentID", "day"]`, grouped, with
   a `count(*) > 1` having-clause via `NSExpressionDescription`) and return early when no
   group repeats — mirror `duplicatedIDs(of:using:)`. Pin with a case in
   `AttendanceDeduplicationTests`.
3. **Days-since-last-lesson.** `StudentsViewModel.LessonQueryContext` materialises a year of
   assignments plus every lesson to find max `presentedAt` per student. Replace with one
   dictionary fetch (`presentedAt` max grouped by… assignments carry a student-id list, so group
   in Swift from a `propertiesToFetch: ["presentedAt", "studentIDs"]` dictionary fetch instead
   of faulting objects) and a `fetchLimit` on the Parsha-exclusion lesson query (`area ==
   "Parsha" OR sequence == "Parsha"` as a predicate instead of filtering every lesson in Swift).
   Existing `StudentsViewModel` tests cover the output shape; add one that seeds two students and
   checks the days map.
4. **`refreshCounts` no longer needed on the 5 s loop** after Phase 1 — delete the loop
   entirely if Phase 1 step 5 left anything behind.

---

## Order and estimates

| Phase | Payoff | Risk | Rough size |
|---|---|---|---|
| 1 Zone repair gate | Highest — fires on every classroom write | Highest — touches sharing-repair logic | ~300 lines + tests |
| 2 Sync status debounce | High during any import | Low | ~150 lines + tests |
| 3 Planner card fetches | Medium, planner screen only | Low, mechanical | ~120 lines |
| 4 Thermal gating | Medium, only when already hot | Low | ~120 lines + tests |
| 5 Fetch shapes | Low each | Low | ~100 lines |

Do 1 and 2 first and measure before deciding whether 3–5 are worth a session; the heat
complaint is most likely explained by 1 alone.

## Measuring before and after

Same device, same store, same 10-minute script: launch, open Today, record one presentation,
mark attendance for three students, open the week planner, leave the app in the foreground
idle for five minutes. Capture with Instruments → Energy Log (iPad) or `powermetrics
--samplers tasks -n 60` (Mac), and note CPU time from the Activity Monitor "Energy" tab. Record
the numbers in `perf-baselines/2026-09-<day>-heat-<before|after>.md` alongside the existing
launch baselines.
