# Type-check warnings vs. single-job measurement — 2026-09-21

Xcode 27.0 (27A266a), macOS destination, Debug, fresh DerivedData, `COMPILER_INDEX_STORE_ENABLE=NO`.
Machine was loaded (Xcode with two projects open, the app running under the debugger).

## What the batched clean build reports

74 distinct warnings: 73 `took N ms to type-check (limit: 100ms)` sites and one real one
(`WorkDeletionService.swift:265: result of 'try?' is unused`, fixed the same day). Xcode's
issue navigator showed 62 for the same tree — the timing set moves between builds.

Of the 73 timing sites, 17 point inside Apple's `@State` macro expansion
(`macro expansion @_StatePropertyWrapperStorage … init accessor for property '_x'`,
`macro expansion @State … expression`) — new since Xcode 27 made `@State` an attached macro;
nothing in project source to change. 22 sites also appear in the 2026-09-04 list; the rest are
new or drifted in.

## The same tree with every declaration checked once

`python3 Scripts/typecheck_timing.py build.log` — the build log's `builtin-SwiftDriver` line with
`-c` swapped for `-typecheck -wmo` plus `-debug-time-function-bodies` and
`-debug-time-expression-type-checking`. One frontend job, ~60 s.

| run | bodies over 100 ms | slowest |
|-----|--------------------|---------|
| 1 (loaded) | 3 | `StudentLearningWorkspace.body` 159 ms, `StudentSelectionSheet.workSelectionRow` 156 ms, `StudentHistoryTab.body` 103 ms |
| 2 | 0 | `LessonDetailView.editForm` 97 ms |
| 3 | 0 | `StudentLearningWorkspace.body` 90 ms, `RootDetailContent.curriculumPlanningContent` 81 ms |

31,271 bodies, **12.2 s** of body type-checking in total for the module in one job, against the
156.8 s the 47-job build spends in type checking (2026-09-04 `-stats-output-dir` sum). The
difference is referenced declarations being re-checked per job.

The run-1 outliers are single expressions, not complex ones: `StudentLearningWorkspace.swift:59`
is `StudentProgressTab(student: student)` (53–92 ms), `:61` is `StudentYearPlanTab(student:
student)` (34–56 ms), `StudentHistoryTab.swift:120` is `StudentTrackDetailView(enrollment:track:)`
(81 ms) — the first reference to those views pays for checking their declarations.
`workSelectionRow` is 16 sub-expressions of 1–9 ms each plus a 67 ms `HStack` builder closure; it
halves on a quiet run (75 ms).

## Conclusion

None of the 73 sites matches a pattern Apple's "Improving build efficiency with good coding
practices" says to rewrite (complex inferred initial values, long inferred closures, nested
ternaries with literals); the ones that had such expressions were annotated on 2026-09-04
(`LessonAlbumMatcher.candidates` has `let lexical: Double` etc. and is still flagged at 271 ms in
a batch job — it is 5 ms alone). Per-site rewriting stays off the table, as decided on 2026-09-04.
The lever Apple's guidance leaves is fewer declarations per job — Phase 6 (module split, explicitly
built modules), where the 12 s vs 157 s gap is the size of the prize.

**Outcome:** both `-warn-long-*` flags raised from 100 to 400 ms in the project's Debug
`OTHER_SWIFT_FLAGS` the same day, so the everyday build is warning-free and the tripwire only
fires on an expression no batch-job artifact can reach.
