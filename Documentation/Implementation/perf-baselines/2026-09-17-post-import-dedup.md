# Post-import deduplication — 2026-09-17

The pass `DeduplicationCoordinator` runs 5 s after every CloudKit import, all school
day, on a fresh background context at `.utility`.

## How it was measured

Unit test `DeduplicationFootprintTests.cleanPassLeavesNoRegisteredObjects`
(iPhone 17 simulator, iOS 27.0, Debug, in-memory stack seeded with 300 lessons and
30 tracks, no duplicates). It runs `DataCleanupService.deduplicateAllModels` on a
background context and reads `registeredObjects.count` afterwards: every registered
object is a row that was faulted in, decoded and held for the life of the context.

Static count of what one pass reads (from the code, not a trace): before, 39
`id`-column dictionary fetches plus two full-table object fetches (Lesson, Track);
after, one dictionary fetch per entity *in scope* and no object fetch on a clean
store.

## Numbers

| Measure | Before | After |
|---|---|---|
| Objects registered after a clean full pass (300 lessons + 30 tracks) | 330 | 0 |
| Entities read per post-import pass | all 41 steps | only the entities the import inserted |
| Passes per import that inserted nothing | 1 full pass | 0 (context never created) |
| Launch pass (`MigrationRunner`) | every entity | every entity (unchanged) |

The live store is larger than the fixture (the whole curriculum is in `Lesson`), so
the absolute object count there is higher; the ratio is what matters.

## What changed

- `DataCleanupService.sameNameLessonGroups` / `sameTitleTrackGroups` read only the
  key columns (`name`, `area`, `sequence`, `parshaKey`; `title`) plus the objectID
  first and materialise only colliding rows. A context with pending changes takes
  the old full-table path, so results are identical (`DeduplicationScopeTests`
  pins the equivalence).
- `DeduplicationScope`: `deduplicateAllModels(scope:)` skips every step whose
  entity is out of scope. `PersistentHistoryProcessor` reports the entities each
  remote batch inserted; the import-event caller is the full-sweep safety net used
  only when no history report arrives in the same debounce cycle.

Not measured on a device: CPU per import burst. The Instruments recipe is in
`.claude/skills/efficiency-pass/references/measurement.md` (Data Persistence +
Time Profiler while a peer device saves a record).
