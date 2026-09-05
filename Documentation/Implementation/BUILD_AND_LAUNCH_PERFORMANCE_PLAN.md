# Build and Launch Performance — Implementation Plan

Status: **Phase 0 and Phase 1 landed (uncommitted, 2026-09-04)** · Owner: Danny · Created 2026-09-04

## Implementation status (2026-09-04)

- **Phase 0** — `-warn-long-expression-type-checking=100` added and the function-body
  threshold lowered to 100 (project Debug `OTHER_SWIFT_FLAGS`). New `Utils/LaunchSignposts.swift`
  (`OSSignposter`, category `Launch`) with intervals `AppInit`, `CoreDataStack.init`,
  `PrepareStoresForLoad`, `LoadPersistentStores`, `StartupBootstrap`, `Bootstrap`, `EarlySetup`,
  `PostLaunchMigrations`, `SearchIndexRebuild`, and a `UIReady` event. The file is also added to
  the Daybook Assistant target because it compiles `CoreDataStack.swift`. Baseline saved to
  `perf-baselines/2026-09-04-clean-build.md` (60.06 s clean build, taken before any change).
- **Phase 1** — `-InitializeCloudKitSchema` unchecked in the shared scheme; CLAUDE.md build
  recipes now use `COMPILER_INDEX_STORE_ENABLE=NO` and `build-for-testing` /
  `test-without-building`, plus the build-setting rules (items 8, 9, 12, 14). The two stale
  DerivedData folders (empty July one; August one for the old `Documents/Projects/Apps` path)
  were deleted; one remains for the current path.
- **Verification** — app and Daybook Assistant both build; the 100 ms thresholds produce 146
  warnings at 62 sites (listed in the clean-build baseline as the Phase 4 work list). Signposts
  confirmed on the iOS 27 simulator: `perf-baselines/2026-09-04-launch-signposts.md`
  (`CoreDataStack.init` 273 ms with the schema argument vs 48 ms without, on an empty store).
  Still to do for Phase 0: capture the launch trace on the Mac with the production store.

Source: the 25-item audit against WWDC26 guidance (sessions 258, 262, 269, 222; group labs
8003, 8006, 8013). Every item is non-destructive: no data migration, no deleted features,
no model changes. The ordering below is chosen so each phase is verified by **one**
measurement and each PR touches files no other phase touches.

## Ordering principle

1. **Measure once, then change.** Phase 0 installs the instruments (build timing, launch
   signposts, slow-type-check warnings) that every later phase is verified against.
2. **Cheapest wins first, in a single commit.** Phase 1 is scheme and build-setting flips
   that need no code review and no tests.
3. **One PR per launch-path subsystem.** Phases 2–3 touch `AppCore/` and
   `Services/SearchIndexService.swift`; they are verified by the Phase 0 signposts.
4. **Structural work last, after Xcode 27 GM.** Splitting view bodies and carving packages
   changes many files; do it once the toolchain and the `refactor/main-actor-default`
   branch are both settled so there is no merge churn.

Prerequisite: merge `refactor/main-actor-default` first. Phases 2–3 add `nonisolated`
Core Data work and would otherwise conflict with it.

## Phase 0 — Instrumentation (½ day)

Goal: a repeatable clean-build number and a signposted cold launch.

| Item | Change | File |
|------|--------|------|
| 1 | Add `-Xfrontend -warn-long-expression-type-checking=100` and lower `-warn-long-function-bodies` to 100 | `project.pbxproj`, project-level Debug `OTHER_SWIFT_FLAGS` |
| 22 | Wrap each `Bootstrap:` timing in an `OSSignposter` interval (`.beginInterval` / `.endInterval`) so the phases show in the App Launch template | `AppCore/AppBootstrapper.swift`, `AppCore/CoreDataStack.swift` (init), `AppCore/MariasNotebookApp+Startup.swift` |
| 7 | Record the baseline: Product → Perform Action → Build With Timing Summary on a clean build; save the summary to `Documentation/Implementation/perf-baselines/` | none |

Verification: one clean build (timing summary saved) and one cold launch under
Instruments → App Launch. Keep both traces; every later phase is compared to them.

Note: the signposter for `CoreDataStack.init` must be `nonisolated static` because the
stack is constructed before the main actor's first hop and Core Data stays nonisolated
under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.

## Phase 1 — Configuration flips (1 hour, one commit)

No code changes; all reversible by editing the same line.

| Item | Change | Where |
|------|--------|-------|
| 16 | Uncheck the `-InitializeCloudKitSchema` launch argument (set `isEnabled = "NO"`; keep the argument so it is one click to re-enable after a model change) | `Maria's Notebook.xcodeproj/xcshareddata/xcschemes/Maria's Notebook.xcscheme` |
| 10 | Add `COMPILER_INDEX_STORE_ENABLE=NO` to the two `xcodebuild` recipes | `Maria's Notebook/CLAUDE.md`, any `Scripts/` build invocations |
| 11 | Split the test recipe into `build-for-testing` and `test-without-building` | `Maria's Notebook/CLAUDE.md` |
| 9 | Delete the two stale DerivedData folders (the 0 B one and the older of the two full ones); open the project from one path only | `~/Library/Developer/Xcode/DerivedData/` — outside the repo, safe |
| 12 | Add a one-line rule to `CLAUDE.md`: any future script phase must declare input and output file lists | `Maria's Notebook/CLAUDE.md` |
| 8, 14 | No change. Document in the same `CLAUDE.md` note that explicit modules, incremental Debug compilation, and DWARF-only Debug info are intentional | `Maria's Notebook/CLAUDE.md` |

Verification: cold launch under Instruments; the `CoreDataStack.init` interval should
drop by the CloudKit round-trip. No build-time change is expected from this phase.

## Phase 2 — Launch-path code fixes (1 day, one PR)

All four changes are local, testable, and land in `AppCore/`.

| Item | Change | File |
|------|--------|------|
| 17 | Add `@ObservationIgnored` to the 13 tracked `private var _service` caches (only `schoolDayChangeObserver` has it today). Services are created once and never replaced, so nothing observes them legitimately | `AppCore/AppDependencies.swift` |
| 21 | Replace the per-body `Logger.app(category: "App")` and the two `logger.info` calls with the file's static logger, logged from `.onChange(of: bootstrapper.state)` instead of on every evaluation | `AppCore/MariasNotebookApp+MainWindow.swift` |
| 20 | Read the two UserDefaults completion flags **before** `await MainActor.run` in `runPostLaunchMigrations`, so completed backfills never hop to the main actor | `AppCore/AppBootstrapper.swift`, the two `DataMigrations.backfill…` entry points |
| 18 | Cache `incoherentSchemaFindings` per store: key = store file modification date + model `versionChecksum`; store the "clean" result in UserDefaults and skip the SQL introspection when the key matches | `AppCore/CoreDataStack+SchemaVersion.swift` |

Tests to add in `Maria's Notebook Tests/AppCore/`:

- `AppDependencies`: accessing a lazy service does not trigger an Observation
  change (use `withObservationTracking` and assert the `onChange` closure never fires).
- Schema cache: a store with an unchanged mtime + checksum skips introspection; a
  changed mtime re-runs it. Both cases against an in-memory-backed temp SQLite file.

Verification: the Phase 0 launch trace, comparing the `Bootstrap` and
`CoreDataStack.init` intervals, plus the SwiftUI Instruments template showing no
`RootView` re-evaluation on first service access.

## Phase 3 — Persistent search index (1–2 days, one PR)

Item 19. The only phase that adds a file format, so it gets its own PR and a
version stamp.

1. Add `SearchIndexSnapshot: Codable` mirroring `index` and `resultsById`, written to
   `Application Support/SearchIndex.v1.json` after each rebuild (background, off the
   main actor).
2. On launch, `rebuildIndexAsync` first tries to decode the snapshot; if the decode
   succeeds, set `isReady = true` immediately and schedule an **incremental** update
   from persistent history since the snapshot's stored history token.
3. Fall back to the existing full rebuild when the snapshot is missing, fails to
   decode, or its version stamp differs.
4. Invalidate the snapshot in the same places the app already resets caches:
   backup restore, "Reset Local Cache", and classroom switch (`ClassroomWorkspaceStore`).

Files: `Services/SearchIndexService.swift` (+ new `SearchIndexService+Snapshot.swift`),
`AppCore/AppBootstrapper.swift` (call order only), `Backup/BackupService+Restoration.swift`
(invalidation hook).

Tests: round-trip encode/decode; snapshot invalidated on restore; incremental update
picks up one inserted note.

Verification: launch trace; the `SearchIndex` interval should move from the
migration tail to near-zero on a warm launch.

## Phase 4 — View-layer work, driven by Phase 0 warnings (2–3 days, several small PRs)

Do this only after Phase 0 has produced the actual warning list; do not split by line
count alone.

| Item | Change | Scope |
|------|--------|-------|
| 2 | For each body the compiler flags over 100 ms, extract the flagged subtree into its own `View` struct in the same file. Start with the four known: `AlbumDetailView`, `PostPresentationFollowUpView`, `RootView`, `TodayView` | one PR per feature folder |
| 24a | Replace `GeometryReader` with `onGeometryChange` or a `Layout` where it only reads size (20 sites; keep the ones that genuinely position children) | `grep -rn GeometryReader` list |
| 24b | Add `fetchBatchSize` (20–50) to `@FetchRequest`s that back a `List` or lazy stack; skip the ones that feed a count or a picker | the 113 files without it — do the list-backed ones only, expect ~30 |
| 25 | Verify: `grep -rnE "@State .* = .*\(\)" ` then confirm none of those views also assign the same property in `init` | read-only check |

Verification: Phase 0 clean-build timing; the flagged-body warnings should be gone.
Each PR is small enough to `Run Without Building` (item 6) between UI checks.

## Phase 5 — App icon (1 hour)

Item 13. In Icon Composer, build one `AppIcon.icon` from `Icon-1024.png`, add it to
`Assets.xcassets`, and point `ASSETCATALOG_COMPILER_APPICON_NAME` at it. Keep the old
`AppIcon.appiconset` in the repo until the archived build's icon is verified on iOS,
macOS, and visionOS; then remove it in a separate commit.

Verification: `actool` line in the build timeline; bundle size in the archive's
App Thinning report.

## Phase 6 — Modularization (1–2 weeks, after Xcode 27 GM)

Items 5 and 4, in this order because 5 removes duplicate compilation on every build
and defines the seam 4 will use.

1. **`DaybookCore` local package (item 5).** Move the 31 files the Daybook Assistant
   target currently recompiles from the app (Core Data stack, schema version, orphan
   cleanup, CloudKit config, entities, sharing permissions, `AppCalendar`, `SaveCoordinator`,
   the model bundle) into `Packages/DaybookCore`. Both apps depend on the package;
   the Assistant's `PBXSourcesBuildPhase` file list shrinks to its own files. Make
   the moved types `public` only where the two apps actually import them.
2. **Leaf feature packages (item 4).** One package per folder with no inbound
   dependencies from the rest of the app: `Parsha`, `Stories`, `PerpetualCalendar`, then
   `Albums`. Each is one PR: move the folder, add the package, fix imports, run tests.
   Stop after `Albums` and re-measure; further splits only if the timing summary shows
   the main module is still the long pole.

Constraints from the codebase:

- Package targets must set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
  `SWIFT_STRICT_CONCURRENCY = complete` in `swiftSettings` to match the app, or the
  main-actor-default rules break at the module boundary.
- The Core Data model must stay in one bundle; `CoreDataStack.sharedModel()` loads it
  by name, so the package that owns `MariasNotebook.xcdatamodeld` exposes
  `Bundle.module`.
- Keep the two-store configuration names and entity routing exactly as they are;
  nothing in this phase touches the schema.

Verification: clean-build timing summary; an edit inside `Parsha` should rebuild only
that module and relink.

## Ongoing (no code)

- **Item 23.** After the next TestFlight build, open Organizer → Metrics and note the
  launch-time, hang-rate, and hitch goals as the field baseline. Revisit after
  Phases 2–3 ship.
- **Item 15.** New previews use `.previewEnvironment()`; no inline stacks.
- **Item 3.** Re-run the Phase 0 clean build on each Xcode 27 beta and at GM.

## Effort summary

| Phase | Effort | Expected effect |
|-------|--------|-----------------|
| 0 | ½ day | measurement only |
| 1 | 1 hour | Debug launch: removes the CloudKit schema round-trip |
| 2 | 1 day | launch: fewer main-actor hops, no cascade invalidation at first render |
| 3 | 1–2 days | warm launch: search index ready immediately |
| 4 | 2–3 days | build: flagged bodies gone; runtime: narrower invalidation |
| 5 | 1 hour | bundle size, actool time |
| 6 | 1–2 weeks | build: incremental edits rebuild one module; Assistant no longer recompiles core |

Phases 0–3 fit in one week and deliver the whole launch-time story. Phase 6 is the
only phase that materially changes clean-build time for the main module and should
wait for GM.
