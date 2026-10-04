# Energy Fifty, wave four (2026-09-26)

Wave four of the Energy Fifty audit (private artifact "Daybook Energy Fifty"; earlier waves in the
`2026-09-25/26-energy-fifty-wave*.md` files): the sync and data items, one agent per item because
each touches data paths. Built in parallel worktrees off 49179a46 while wave three gated, merged on
top of wave three (d9942290), then gated together (iOS build-for-testing, macOS and Daybook
Assistant builds, full iOS suite on the iPhone 17 simulator) before landing.

| # | Change | Before → after | How measured |
|---|---|---|---|
| 12 | Launch repairs run in the migration pass's background context; Today's 30-day cleanup once a day in the background | main-thread work ~3 s after launch: 2 whole-table fetches + one participants fault per work row (+3 fetches one launch in ten, up to 3 view-context saves) → 0; participant SELECTs: one per work → one prefetch; Today cleanup: every TodayViewModel init on main → once per store per day off main | `LaunchRepairPassTests`, `TodayRetentionCleanupTests` (old code kept verbatim in the tests) |
| 13 | Zone-repair watermark advances on clean history passes; the gate's history read is scoped to the private store | transactions read per gate pass with 5 remote batches between shared inserts: 1,2,3,4,5 → 1,1,1,1,1 (n(n+1)/2 → n) | `SharedStoreZoneRepairWatermarkTests` |
| 25 | All-students PresentationRecordIndex built from column rows | managed objects created per rebuild at April-backup scale: 2,563 → 0; temporary heap ~1,970 KB → ~34 KB; time unchanged (the objects were never retained — this is churn, not residency). Still read on the calling context, so on the main thread for Today | `PresentationRecordIndexRowPathTests` |
| 43 | Backup export streamed one entity type at a time; preview reads counts and IDs; CSV parsed as UTF-8 bytes | export peak 53.8 → 38.2 MB (44,318 rows, 73 types); preview peak 38.0 → 29.6 MB; CSV (20k-row roster) 28.1 → 8.9 MB. Restore still decodes the whole archive | on-request `BackupExportPeakMemoryTests` (malloc sampler, medians of 6); archive/preview/CSV equivalence tests against verbatim old code |

## The gate

The first combined run failed five streamed-export tests that passed in each branch alone. The
export's `BackupSnapshotWatch` reused `ManagedObjectChangeFlag`, which also trips on the
process-wide `.presentationDataDidChange`; under the parallel suite other tests' stores post it, so
every streamed export fell back to the one-pass path. The flag gained `listensForImportSignal`
(default true, so its other users are unchanged) and the watch passes false: an import on its own
store still arrives as a save on its coordinator, and the end-of-run history check backs that up
(b3762f21).

The second run failed two of those tests on `preferences.json`: the tests compared the export's
settings with the old collector's read afterwards, and settings live in process-wide UserDefaults,
which `SchoolYearTests` writes while other suites run. The Debug-only `BackupPipelineRecorder`
seam now carries fixed settings that `BackupService.buildPreferencesDTO()` returns while bound, and
every collection those tests compare binds them (47b210d1). Release builds are unchanged.

Third run: all builds clean, 1,606 tests, 1,602 passed, 0 failed, 4 skipped (the known
`UUIDPredicateArgumentTests` crash probe, plus this wave's three on-request peak-memory tests).

## Found on the way (not fixed)

- `PersistentHistoryProcessor` keeps one token for a two-store container. A probe showed that from
  then on it reads only the token's store; if the newest transaction when the cursor was empty came
  from the shared store, it would stop seeing private-store imports (no post-import dedup, no
  entity notifications). This is item 14, previously parked as latent; it is a correctness risk.
- Backup, old one-pass path: with an unsaved insert in an entity type over 1,000 rows, the export
  writes that row twice and drops one saved row. The streamed path never takes that case; fixing the
  one-pass path changes output (Danny's call).
- Restore still holds the decoded payload and its deduplicated copy at once; the archive library's
  own buffers (~27 MB reading, ~30 MB writing + verifying) are now most of the export peak.
- Off the main thread, `.background` QoS work waited up to 50 s while builds loaded the Mac; the
  Today cleanup runs at `.utility` for that reason.
