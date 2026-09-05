# Launch signpost baseline — 2026-09-04

Environment: iPhone 17 simulator, iOS 27.0 (24A5408d), Debug build, **empty database, no iCloud
account**. This is a smoke test of the `Launch` signposts, not the real launch baseline — take
that on the Mac with the production store (see "How to capture" below).

`xctrace record --template 'App Launch' --launch` could not attach to the simulator
("Cannot communicate with the device to launch the process"), and `log show` drops info-level
lines, so the numbers come from `log stream --signpost` captured during two `simctl launch` runs.

| Interval | Run A: `-InitializeCloudKitSchema` on (first launch after install) | Run B: argument off (warm) |
|---|---|---|
| `AppInit` | 289 ms | 52 ms |
| `CoreDataStack.init` | 273 ms | 48 ms |
| `PrepareStoresForLoad` | 84 ms | 26 ms |
| `LoadPersistentStores` | 162 ms | 13 ms |
| `StartupBootstrap` | 20 ms | 6 ms |
| `Bootstrap` (to `UIReady`) | 4 ms | 1 ms |
| `PostLaunchMigrations` (starts 3 s after `UIReady`) | 76 ms | 18 ms |
| `SearchIndexRebuild` | 17 ms | 3 ms |

Notes:

- Run A includes first-launch cache warm-up, so only part of the 225 ms gap is the schema call.
  With no iCloud account the schema initialization fails fast ("A Core Data error occurred")
  ~120 ms after the stores load; on a signed-in device it is a full CloudKit round-trip. An
  earlier, un-instrumented first launch on this simulator logged the same failure 16 s after
  launch, which is the order of magnitude to expect when the call actually reaches the network.
- Everything after `UIReady` is off the critical path by design (3 s delay). The intervals
  worth watching on real data are `PrepareStoresForLoad` (Phase 2, item 18),
  `LoadPersistentStores`, and `SearchIndexRebuild` (Phase 3, item 19).

## How to capture on the Mac (real store)

```bash
# Terminal 1 — stream the Launch category while the app starts
log stream --level debug --signpost --style compact \
  --predicate 'subsystem == "DanielSDeBerry.MariasNoteBook" AND category == "Launch"'

# Terminal 2 — cold-launch the Debug build (or Run Without Building in Xcode)
open -a "Montessori Daybook"
```

Or in Instruments: App Launch template → the intervals appear under **os_signpost**,
subsystem `DanielSDeBerry.MariasNoteBook`, category `Launch`.

## After Phase 2 (same simulator, same empty store, Debug build of `perf/phase-2-launch-path`)

Three consecutive cold launches; the first is a cache miss (fresh install), the next two hit
the physical-schema cache for both stores.

| Launch | `PrepareStoresForLoad` | skip logged |
|---|---|---|
| 1 | 50 ms | no (first verification, key recorded) |
| 2 | 20 ms | private.sqlite, shared.sqlite |
| 3 | 16 ms | private.sqlite, shared.sqlite |

The remaining ~16 ms is the two metadata reads (newer-build guard, migration check), the orphan
metadata cleanup, and the version stamp. On the production store the table walk scales with the
number of tables, so the saving there should be larger; capture it on the Mac.
