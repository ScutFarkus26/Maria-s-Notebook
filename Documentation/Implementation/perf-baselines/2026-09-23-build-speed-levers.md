# Build-speed levers — 2026-09-23

Xcode 27.0 (27A266a), MacBook Air M4 (Mac16,12, fanless, 4P+6E cores), on AC power, Low Power Mode off.
Measured on `git archive` copies and rsync'd copies of the tree in the session scratchpad; the repo was
not built in place. For most of the session another Claude session was benchmarking Tide builds
(load average 20–150), so every A/B below is read from numbers load cannot distort — compiler
instruction counts (`/usr/bin/time -l` "instructions retired", `-stats-output-dir`
`Frontend.NumInstructionsExecuted`), cache-hit counts, and recompiled-file counts. Wall-clock
figures are given with the load they ran under.

## Where an edit-build goes

A one-line change inside a view body (`SampleWorkRow.swift`, load ≈19): **26 s wall** —
emit-module 15.9 s, driver planning 4.3 s, compiling the file 0.7 s, link 1.2 s. The emit-module job
re-runs on every build that changes any source and re-checks the whole module's declarations:

| emit-module job (stats-output-dir, one run) | |
|---|---|
| declarations type-checked (`Sema.NumDeclsTypechecked`) | 107,639 |
| source buffers (1,351 files + macro expansions) | 10,933 |
| function bodies type-checked | 2,748, 0.4 s in total |
| expressions type-checked | 22,146, 5.8 s (half inside `@State` initializer expansions) |
| instructions, standalone, quiet | 130 G, 15.9 s |
| same with `-enable-testing` dropped | 125 G (−4%) |

The remaining ~80% is `typecheck-decl` — signatures, attached-macro expansions, conformances — so no
code-style rewrite of bodies or expressions shrinks it. The slowest single expressions it reports
(`@State var viewModel = ClassAreaChecklistViewModel()`, 148 ms) are the first-reference charge for
checking the view model's declaration, the same attribution artifact as 2026-09-21.

No Xcode setting skips emit-module for an application target (Swift Build has none; the test target
runs its own 19 s emit-module too).

## Concurrent builds

The clean build the plan measured at 48 s (2026-09-04, quiet) took **255 s** at load ≈150 while the
Tide session was building (this build at `nice -n 15`, which exaggerates its share of the slowdown);
its emit-module job went from 37 s to 114–120 s. The standalone emit-module ran 138 s wall for 54 s
of CPU under the same load. `appstoreagent` held one core at ~95% for the machine's whole 14-day
uptime and WhatsApp another at ~96% during the first sample.

**Change:** every CLI build in `Cosmic Daybook/CLAUDE.md` now runs as
`/usr/bin/lockf -k /tmp/xcodebuild.lock nice -n 10 xcodebuild …` — agent builds queue instead of
thrashing, and Danny's own Xcode builds keep the performance cores.

## Compilation caching

`COMPILATION_CACHE_ENABLE_CACHING = YES` works with this project (explicit modules, SwiftUI and
Observation macros, App Intents metadata). Store: `~/Library/Developer/Xcode/DerivedData/CompilationCache.noindex`,
shared by every DerivedData folder under that root (confirmed: 48 K → 746 M after one build).

| build (Swift compile = summed task time) | load | wall | Swift compile | emit-module | replayed |
|---|---|---|---|---|---|
| macOS, uncached cold | ≈150 | 255 s | 1,928 s | 120 s | — |
| macOS, cached cold (populates the store) | ≈125 | 263 s | 1,871 s | 114 s | 0 |
| macOS, same tree, same path, fresh DerivedData | ≈180 | 86 s | 34 s | 0.3 s | 324 of 324 |
| macOS, same tree, **other path** (prefix mapping on) | ≈135 | 64 s | 34 s | 0.25 s | 324 of 324 |
| macOS, other path, **one line edited** | ≈45 | 115 s | 847 s | 72 s | all 55 compile jobs + emit-module missed |
| iOS Sim, after the changes below, cold | ≈25 | 75 s | 443 s (20 jobs) | 43 s | 0 |
| iOS Sim, same tree, other path | ≈23 | 22 s | 23 s | 0.19 s | 21 of 21 |

A Swift batch job's cache key covers every file of the module (primaries and secondaries), so one
edit anywhere misses every compile job. Caching therefore helps Clean Build Folder, a deleted
DerivedData, returning to an already-built tree, and a worktree's first build — not the edit loop.
With `SWIFT_ENABLE_PROJECT_PREFIX_MAPPING`, object files record `/^src/…` paths
(`dwarfdump`: `DW_AT_comp_dir ("/^src")`); Swift Build writes each target's
`compilation-prefix-map.json` mapping them back. Whether Xcode's debugger reads it was not
verified, so the project leaves project prefix mapping off.

**Changes:** project Debug `COMPILATION_CACHE_ENABLE_CACHING = YES` and
`COMPILATION_CACHE_LIMIT_SIZE = 10G` (Xcode prunes the store; its default limit could not be found,
and the data volume is 95% full). The CLAUDE.md worktree recipe adds `SWIFT_ENABLE_PREFIX_MAPPING`,
`SWIFT_ENABLE_PROJECT_PREFIX_MAPPING` and `CLANG_ENABLE_PREFIX_MAPPING`, and agents build once before
editing. The clean-build baseline recipe passes `COMPILATION_CACHE_ENABLE_CACHING=NO` so future
baselines stay compiles, and `Scripts/typecheck_timing.py` drops the caching flags from the driver
line.

## Batch size

The driver makes `max(-j, ⌈files / 25⌉)` batches: 47 on 2026-09-04, 55 today as refactors split files.

| clean compile, one driver invocation | jobs | compile-job instructions |
|---|---|---|
| default | 55 | 1,798 G |
| `-driver-batch-count 20` | 20 | 1,633 G (−9%) |
| `-driver-batch-count 10` | 10 | 1,592 G (−11.5%) |

A/B/A clean builds on the iOS Simulator with caching off (size limit 70 / default / size limit 70):
139 s / 135 s / 155 s wall, with load rising 18 → 54 across the three — no wall-clock difference
within noise, as expected while the single emit-module job is the long pole.

**Change:** `-driver-batch-size-limit 70` in project Debug `OTHER_SWIFT_FLAGS` (20 jobs for the app;
the test target and Daybook Assistant keep 10). The size limit, not `-driver-batch-count`, so a
three-file incremental build is not split across 20 jobs.

## Recompile cascades

The same kind of edit, incremental build, count of app files recompiled:

| edit | files |
|---|---|
| change a string literal inside a view body | 1 |
| add a file-scope `private func` to a file with no extensions (`WorkStepRow.swift`) | 3 |
| add a computed property to the `CDStudent` class body | 496 |
| add `extension CDStudent { var … }` to a leaf view file | 451 |
| add a `private func` to that same file afterwards | 451 |
| add a `private func` to `StudentEntity+Roster.swift` (an extension-only file) | 1,069 |
| add a `private func` to `SettingsModifiers.swift` (holds `extension View`) | 1,109 |
| add `private extension String { … }` to a leaf view file | 1,267 of 1,352 |
| add a `private func` to that same file afterwards | 1,267 |
| a body-only edit to an app file, effect on the test target | 0 test files |

An extension carries no dependency fingerprint, so a signature-level change anywhere in a file that
contains one — however unrelated, and whatever the extension's access level — marks every member
the file provides for the extended type as changed. At load ≈35 those near-full rebuilds took
3.5–4.5 min against ~30 s for the plain file.

Census: 516 files contain an extension; 34 mix an extension of a type used in ≥100 files with their
own types. Most are a ViewModifier plus its `extension View` wrapper, left as they are.

**Changes (pure moves; the only access change is `albumMatchToggleStyle`, `private` → internal):**

| from | moved | to |
|---|---|---|
| `Students/Progress/StudentProgressComponents.swift` | `StepProtocol` + `CDLesson`/`CDWorkStep`/`CDTrackStep` conformances | `Students/Progress/StepProtocol.swift` |
| `Presentations/FollowUp/PresentationFollowUpTypes.swift` | `extension CDLessonPresentation` (follow-up accessors) + its `String.nilIfEmpty` | `Presentations/FollowUp/LessonPresentationEntity+FollowUp.swift` |
| `AppCore/RootView.swift`, `Todos/Views/TodoEditSheet.swift` | `UUID` / `URL` `@retroactive Identifiable` | `Utils/Identifiable+Retroactive.swift` |
| `Schedules/SchedulesView.swift` | `Color(hex:)` | `Utils/Color+Hex.swift` |
| `Students/Roster/StudentCardHelpers.swift` | `Color.cardBackground` | `Students/Roster/Color+CardBackground.swift` |
| `Albums/AlbumsLibraryView.swift` | `Text.albumHighlightedSnippet` | `Albums/Text+AlbumHighlightedSnippet.swift` |
| `Albums/LessonAlbumMatchSheet.swift` | `View.albumMatchToggleStyle()` | `Albums/View+AlbumMatchToggleStyle.swift` |
| `Students/Watching/WatchItemRow.swift` | `watchClearConfirmation` + its private modifier | `Students/Watching/WatchClearConfirmationModifier.swift` |
| `Presentations/Workflow/UnifiedPresentationWorkflowPanelComponents.swift` | `CardBackground`, `View.cardBackground`, `Animation`/`Font` workflow styles | `Presentations/Workflow/UnifiedPresentationWorkflowStyles.swift` |
| `Components/StudentSharedComponents.swift` | `BobbingAnimationModifier` + `bobbingAnimation`/`studentCardRasterization` | `Components/StudentCardModifiers.swift` |
| `AppCore/ClassroomWorkspaceStore.swift` | `activeClassroomEnvironment` + its private modifier | `AppCore/ActiveClassroomEnvironmentModifier.swift` |
| `Services/ToastService.swift` | `ToastOverlayModifier` + `View.toastOverlay` | `Services/ToastOverlayModifier.swift` |

`RootView.swift` had the most edits of the lot (6 in 60 days) and its `UUID` extension put every
signature edit there in the ~1,200-file class. Not moved: `Backup/SaveCoordinator.swift` and
`Students/Models/StudentModel.swift`, which the Daybook Assistant compiles by path.

## Bottom-layer module split (Phase 6 re-examined)

A read-only analysis (scripts in the session scratchpad, `split-analysis/`) classified every
top-level declaration as UI (views, modifiers, `@State`/`@Environment` users, `@Observable`
view models, `AppDependencies`, App Intents) or not, and closed the non-UI set under references.
Result: one connected non-UI layer of 683 whole files + 18 to split (≈50% of top-level
declarations, 43% of lines, all 942 `@NSManaged` properties, all of `Backup/` and
`Services/MCPServer/`), blocked by three upward references — `AppRouter` → `RootView.NavigationItem`,
six files → `AppDependencies`, and `AttendanceEmail`'s `MailComposerView` factory — plus ~510 types and
~2,100–2,500 members that would need `package`/`public`. It predicted the layer at ~41% of
emit-module work.

The spike measured it directly: the app's emit-module command re-run over the 684 bottom-layer files
only, alternating with the full module (macOS, uncached, load 14–20):

| emit-module | wall | instructions |
|---|---|---|
| full module (1,363 inputs), two runs | 20.2 s / 21.5 s | 130 G |
| bottom layer only (684 inputs), two runs | 4.4 s / 3.3 s | 26 G |

The bottom-only run had 224 errors, all missing symbols from the 18 not-yet-split files
(`SaveCoordinator`, `AlbumSearchCorpus`, `AppRouter`, …), so it slightly understates the layer;
even allowing for that it is ~20–25% of emit-module work, not 41%. The view layer — `@State` and
`@Observable` expansions, `some View` signatures — is the bulk. A split would take ~3–4 s off a
~16 s view-edit emit-module, at the price of the three cuts, 18 file splits and a permanent
`public` surface. **Not worth doing on its own.** The per-edit floor belongs to the SwiftUI layer.

## Tested and ruled out

| idea | result |
|---|---|
| `SWIFT_EMIT_LOC_STRINGS = NO` in Debug (there is no string catalog) | 1,972 G vs 1,952 G compile instructions — no gain |
| `ENABLE_TESTABILITY` only for testing | emit-module −4%; would split Run and Test products |
| `SWIFT_ENABLE_EXPLICIT_MODULES = NO` | body-edit builds 34–58 s vs 55 s, planning 3–7 s either way — noise; also disables caching |
| `-incremental-dependency-scan` | planning 4.3–7.6 s vs 6.4–7.8 s — noise |
| preview regression | all 102 `#Preview` bodies still hoisted |
| No-op build | 1–4 s |

## Not done here

- Time Machine backs up `~/Library/Developer/Xcode/DerivedData` (29 GB, rewritten every build) to a
  network destination. Excluding it is Danny's call:
  `tmutil addexclusion ~/Library/Developer/Xcode/DerivedData`. Not measured.
- The eight DerivedData folders left by the removed `wave5-*`/`energy-*` worktrees (~19 GB) were
  moved to the Trash, not deleted.
