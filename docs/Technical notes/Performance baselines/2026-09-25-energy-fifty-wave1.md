# Energy Fifty, wave one (2026-09-25)

The 2026-09-25 audit listed 50 battery and memory items for the Mac and the iPad (private
artifact "Daybook Energy Fifty"; numbers below refer to it). Wave one is the view-layer and
read-path items plus three UI items Danny decided: 17, 19–21, 23, 24, 26–36. Four agents
did them in parallel worktrees; each merged branch passed an iOS build-for-testing, a macOS
build, a Daybook Assistant build and the full iOS test suite together before landing.

## Baseline: the Mac copy in daily use, before any change

Xcode's Debug build, launched from Xcode on 24 Sep at 14:12 and running under `debugserver`
for 24 h on the M4 MacBook Air, on battery, mostly idle. Taken with `top -stats …idlew,power`, `footprint`,
`heap -s` and `/usr/bin/log show`.

| Measure | Value |
|---|---|
| CPU while idle / CPU time in 24 h | 0% / 15.7 s |
| `phys_footprint` (peak) | 115 MB (148 MB), 111 MB of it compressed |
| Live heap | 68 MB in 515k allocations |
| Largest heap groups | SwiftUI `PropertyList.Element` 29.5k (4.7 MB); observation tracking dictionaries 3.4k (2.7 MB); SF Symbols' parsed SVG ~3 MB; 1,184 `_CDSnapshot_Lesson_` (the whole lesson table) |
| Reminders sync retries ("list not found") | 39 in 24 h, mostly in pairs 2 s apart |

The build itself is a cost: `-Onone`, code-coverage counters (`__llvm_prf_cnts`) and an
attached debugger (item 1). Compare later numbers against a Release build.

## Wave one results

Static counts unless a test is named; "per pass" means per SwiftUI body evaluation.

| # | Change | Before → after | How measured |
|---|---|---|---|
| 17 | Students roster save listener filtered to the tables its tokens read | 4 queries per unrelated save burst → 0 | `StudentsViewSaveGateTests` |
| 19 | Work card fan-out lookup moved into the menu's own view | 4 fetches + participant faults per card redraw → 0 | `WorkCardMenuLookupTests` (hosted window, iOS) |
| 20 | Week-plan check-in pills use their group's names | 6 fetches per pill per redraw → 0 | `WorkCheckInPillNamesTests` (13 fallback cases) |
| 21 | Today keeps the ready queue and needs-lesson count until inputs move; toast in its own view | 5 appearances: 5 → 1 queue builds, 5 → 1 counts; body re-runs per toast 2 → 0 | `TodayAppearanceGateTests` |
| 23 | Three-Year View prefetches participants; `class_curriculum_map` builds one lesson's cells | 30 participant faults → 0 (30 work rows) | `CurriculumMapScopedReadsTests` |
| 24 | Lesson lookups via the catalog, attendance badges via `count(for:)` | 2×N fetches → 0 (relationships); 2 year-long fetches → 2 COUNTs | `LessonCatalogContextLookupTests`, `AttendanceInfoRowCountTests` |
| 26 | MCP lessons resolved by id; chat context reads scoped | `record_presentation` ×5: 5×L lesson rows → 5 (by id) | `MCPLessonReferenceResolutionTests`, `ChatContextAssemblerScopedReadsTests` |
| 27 | Lessons screen reads the catalog; derived orders built lazily | live lesson result sets 2 → 1; catalog rebuilds per change 4 → 2 | `LessonCatalogScreenOrderTests` |
| 28 | Map rows and roster cards measured in content space | per scroll step: 1 preference action + Task + state write → 0 | hosted probe (not committed) |
| 29 | Lessons map sections memoised (memo half only) | section builds per pass 1 → 0 when inputs are unchanged | `MapLayoutMemoTests`, `MapHoverTargetTests` |
| 30 | Attendance log filters once per render | filter passes per body ~12 → 1 | `AttendanceLogFilterTests` (200 combinations) |
| 31 | Stable focused values for File ▸ New and the Album menu | Album menu rebuilds per page turn 1 → 0 | `FocusedMenuActionsTests` + macOS build |
| 32 | Chip rows wrap with `FlowLayout` (5 of 6 sites) | platform scroll views per row 1 → 0 | static |
| 33 | Work grid ages computed once per pass | age sort, 80 works: 1,824 → 80 age computations | `OpenWorkGridSortTests` |
| 34 | Sticky grid labels watch one number | label rebuilds per vertical scroll frame: 1 per row → 0 | static |
| 35 | Chat text paced to ≤ 10 updates/s | synthetic stream of 600 chunks: 600 → 43 updates | `StreamingTextThrottleTests` (dormant: chat doesn't stream today) |
| 36 | Quick Note pulse plays twice | continuous → 2 cycles | static |

## Left for Danny or a later wave

- 29, lazy rows: iOS 27 rebuilds far-scrolled `LazyVStack` rows, resetting a row's
  sideways-scrolled pill strip, so it needs a decision.
- 32, Progress Dashboard row: its collapsed strip scrolls one line on purpose and the
  chevron expands it; wrapping would change that, so it needs a decision.
- 30, fetching this month from `init`: a `@FetchRequest` built in `init` is put back on every
  parent redraw, so the log's existing on-appear narrowing already reverts. The follow-up is
  a child view keyed by the date range.
- 26, `studentID ==` on chat's open-work read: SQLite then picks a different index and row
  order, changing which 8 items chat lists; left as is.
- 35: chat doesn't stream (`ChatService` calls `streamConversation` without `timeout:`).
  Turning streaming on would be a visible change.
- New candidates: `TodayView.init` builds a new `TodayViewModel` (and cleanup task) on every
  parent redraw; the Week plan check-in pill's own context menu builds its rows on every
  column redraw.
