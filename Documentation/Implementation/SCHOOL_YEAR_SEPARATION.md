# School Year Separation — Implementation Plan

Status: **In progress** — Phases 0–2 landed on `feature/school-year-separation` · Owner: Danny · Created 2026-06-15

## Implementation status (2026-06-15)

Landed and building green on `feature/school-year-separation`:

- **Phase 0 (engine)** — `SchoolYear` / `DateRange` / `SchoolYearSelection`, `SchoolYearStore`,
  `SchoolYearFilter` predicate factories, global picker + non-current-year banner, configurable
  start date, `FloridaGradeCalculator` integration, and unit tests.
- **Phase 1** — student roster scoped to "active this year"; the per-student unified notes
  timeline scoped to the selected year. The timeline already merges notes + presentations +
  work + meetings + attendance as items, so per-student *history review* is comprehensively
  year-scoped through that one integration.
- **Phase 2** — the Projects list scoped via `CDProject.overlaps` (creation through last
  session/edit).

Reframing from the original plan — the lens only visibly matters on *accumulating history*:

- Deliberately **not** wired (near-no-op for the current-year default, or no list to filter):
  the Today screen (single day), the Open Work queue and Presentations planning inbox
  (forward-looking), and the global Note tab (a quick-note composer, not a browser). The
  standalone `PresentationsListView` is orphaned/dead.
- **Remaining surfaces** if desired: Going Out (filters inside its view model), Meetings, the
  area-checklist coverage grid, and lens-driven date presets on the attendance reports.
  Phase 3 reports and Phase 4 (`schoolYearKey` stamp) remain optional.

## Counter epoch (2026-08-23)

The lens answers "which records do I see"; it does **not** answer "how long since…". Elapsed-day
counters measure from the last activity date, so across a summer they describe the calendar
rather than the child — on the first morning of school every child reads as neglected and every
open work item arrives stale. `SchoolYear/SchoolYearCounters.swift` adds a **counter epoch**: a
single date that clamps each counter's *start* forward, leaving the underlying dates untouched.
Anything older than the epoch counts from it, so counters read 0 on the first day of school.

- **Setting:** Settings → School Calendar → School year start. The month/day pickers now show the
  resolved date, and a "Day counters" segmented control chooses **Start of the school year** (the
  epoch, default) or **All history** (the old behavior, epoch `nil`). A "Reset counters to …"
  button appears when the epoch has drifted from the current year's start.
- **Rollover:** the epoch never moves on its own. When a new school year begins, `RootView` asks
  once — "Start Fresh" pins the epoch to the new year's start *and* moves the lens onto it;
  "Keep Counting" leaves both alone. `schoolYearCounterPromptAnsweredYear` keeps it to once a year.
- **Clamped sites** (all via `SchoolYearCounters.countFrom`): `SchoolDayCalculationCache`
  `.schoolDaysSinceCreation` (which covers `LessonAgeHelper` and so days-since-last-lesson,
  presentation aging, and work age), `WorkAgingPolicy.daysSinceLastTouch`,
  `FollowUpInboxEngine.schoolDaysSince`, the checklist staleness grid, days-since-last-meeting and
  "lessons since last meeting", the small-sequence planner, and the AI planner's readiness input.
- **Deliberately unclamped:** `schoolDaysBetween` (an explicit range, not an elapsed counter),
  `WorkAgingPolicy.isOverdue` / `lastSchedulingActionDate` (a date comparison — a genuinely missed
  due date shouldn't be forgiven by the calendar), `lastMeaningfulTouchDate` itself (it is also
  *displayed*), and "completed within 30 days" style recency filters.

## Overview

Let a guide view the classroom "by school year" without ever splitting, moving, or
deleting data. A single global **viewing lens** (a date filter) defaults to the current
year for an uncluttered working set, while the full multi-year record stays intact for
cumulative, cycle-spanning reports.

The lens is **cycle-first**: `This year` / `This cycle (3 years)` / `All time`, plus a
specific-year picker. Because every activity record is already timestamped, all three
views are derived from the same data — nothing is partitioned.

This matches both how the leading Montessori platforms work and AMI elementary practice
(see [References](#references)).

## Principles (and why)

1. **Continuous record, never partitioned.** Transparent Classroom keeps a child's full
   history forever; Montessori Compass's own docs warn that defining *discrete* school
   years blocks cumulative cross-year reports and recommend one continuous ("ongoing")
   range. We derive the year from existing timestamps, so yearly **and** cumulative views
   coexist for free.
2. **The three-year cycle is the real unit.** AMI elementary records are kept per child
   across all three years (initial presentation → deeper follow-ups → independent work).
   So the lens leads with the cycle, not the calendar year.
3. **Evergreen data is never filtered.** Students and the lesson/curriculum library
   persist across cycles; only *activity* records are year-scoped.
4. **Keep it frictionless.** AMI: "observation is more important than record-keeping."
   No per-record year-stamping and no separate stores in the core design — a filter only.
5. **Additive & reversible.** CloudKit schema stays additive. `All time` = no predicate =
   exactly today's behavior, so the feature cannot lose data and can be switched off
   instantly.

## The lens (selection model)

```swift
enum SchoolYearSelection: Equatable, Codable {
    case year(SchoolYear)          // a single school year   [start, end)
    case cycle(anchor: SchoolYear) // anchor + two preceding years (rolling 3-year window)
    case allTime                   // no date filter
}
```

- **Default** = `.year(current)`. Persisted in `AppStorage`.
- Resolved by the store to an optional `DateRange` (`nil` for `.allTime`).

```swift
struct SchoolYear: Equatable, Codable, Identifiable {
    let startDate: Date    // e.g. 2025-09-01
    let endDate: Date      // exclusive; next year's start
    var key: String        // "2025-2026"
    var label: String      // "2025–2026"
    var id: String { key }
}
```

Boundaries come from a **configurable start month/day** (default Sept 1, matching today's
`FloridaGradeCalculator`).

**Per-student report cycle (AMI-correct cumulative).** For progress reports, the cycle is
anchored to the *child* — their first year in their current level (from `dateStarted` /
`levelRaw`) spanning three years — so a child's cumulative report covers their actual
cycle rather than a global rolling window. The global lens uses the rolling window; the
report uses the child-anchored cycle.

## Data classification

| Class | Entities | Year filter |
|---|---|---|
| **Evergreen** | `CDStudent`, `CDLesson` (+attachments, sampleWorks), `CDTrack` / `CDSequenceTrack`, `CDProcedure`, `CDSupply`, `NoteTemplate` / `MeetingTemplate` / `TodoTemplate`, `CDResource`, schedules | **Never** |
| **Year-scoped activity** | `CDNote`, `CDWorkModel`, `CDLessonAssignment`, `CDAttendanceRecord`, `CDPracticeSession`, `CDProject` / `CDProjectSession`, `CDTodoItemEntity`, `CDStudentMeeting` / `CDScheduledMeeting`, `CDWorkCheckIn`, `CDIssue`, calendar entries, Going Out | **Yes** |

## Filtering semantics

Given a resolved range `[start, end)`:

- **Point-in-time** — include if the governing date ∈ `[start, end)`:
  - `CDNote.createdAt`
  - `CDAttendanceRecord.date`
  - `CDLessonAssignment`: `presentedAt ?? scheduledForDay ?? createdAt`
  - `CDPracticeSession.date`, `CDProjectSession.meetingDate`, `CDStudentMeeting.date`, `CDWorkCheckIn.date`
  - `CDTodoItemEntity`: `scheduledDate ?? dueDate ?? createdAt`
- **Span (overlap — "show while active")** — `CDWorkModel`: include if
  `createdAt < end AND (completedAt == nil ? (lastTouchedAt == nil OR lastTouchedAt >= start) : completedAt >= start)`.
  Open work shows in its start year **and** every later year it's still being touched.
  (`CDProject` is handled in Phase 2 via its `CDProjectSession.meetingDate` activity plus
  `isActive`, since Project has no `completedAt`.)
- **Roster (filtered default)** — active-in-range:
  `dateStarted <= end AND (dateWithdrawn == nil OR dateWithdrawn >= start)`.
  `nil dateStarted` ⇒ always shown.
- **Fail-open** — any record whose governing date is `nil` is **always shown** (never
  silently hidden).
- **`.allTime`** ⇒ no predicate (today's behavior).

Centralize as predicate factories so every fetch site shares one source of truth and
`.allTime`/`nil` short-circuits cleanly:

```swift
enum SchoolYearFilter {
    static func pointInTime(_ keyPath: String, in range: DateRange?) -> NSPredicate?
    static func span(createdAt: String, completedAt: String,
                     touchedAt: String, in range: DateRange?) -> NSPredicate?
    static func roster(in range: DateRange?) -> NSPredicate?
}
// callers AND the result into their existing predicate, skipping when nil
```

## New components

- `SchoolYear.swift` — value type + boundary math.
- `SchoolYearSelection.swift` — enum + `DateRange`.
- `SchoolYearStore.swift` — `@Observable @MainActor`. Reads configured start + selection
  from `AppStorage`; computes `availableYears`, `current`, `currentCycle`; vends
  `range(for:)`, the predicate factories, and `cycle(for student:)`. Injected via
  `.environment` in `MariasNotebookApp` / `RootView`.
- `SchoolYearPicker` — toolbar `Menu`: `This year` / `This cycle` / `All time` + each
  available year.
- Non-current-year **banner** — tinted "Viewing 2024–2025" whenever the selection isn't
  the current year (prevents "where did my data go?").
- Settings row "School year starts on…" (month/day), default 9/1.
- New `UserDefaultsKeys`: `schoolYearStartMonth`, `schoolYearStartDay`,
  `schoolYearSelection`.

## Integration points

- `FloridaGradeCalculator` — read the configured start instead of the `static let 9/1`
  (grade logic unchanged). It is the single boundary source today.
- `TodayDataFetcher` (~40 fetches) — inject the store range into the *activity* fetches.
- `StudentsView` / `StudentsViewModel` — default roster to active-in-range; extend
  `StudentsView.selectedFilter` with an "All students" option.
- `PresentationsViewModel`, `ClassSubjectChecklistViewModel`, `ProjectsRootView`,
  `GoingOutRootView`, meetings — AND the year predicate into existing fetches.
- Attendance reports (`AttendanceAbsenceReport`, `AttendanceTardyReport`) — already use
  `schoolYearStart()`; swap to the selection range and add a cumulative/cycle option.
- `@FetchRequest` views — rebuild the predicate when the selection changes (construct
  from the store in `init`, or key the container with `.id(selection)`; small lists may
  post-filter in memory).
- **Untouched:** Lessons, Procedures, Supplies, Tracks, Templates.

## Phasing

**Phase 0 — Foundation + prove it on one surface**
- `SchoolYear`, `SchoolYearSelection`, `SchoolYearStore`, `AppStorage` keys, `.environment`
  injection.
- Toolbar picker (`This year` / `This cycle` / `All time` + specific years) + non-current
  banner.
- Configurable start date in Settings; `FloridaGradeCalculator` reads it.
- Wire **Today only**. Verify decluttering works and `All time` == unchanged behavior.
- Unit tests: boundary math, cycle window, roster + overlap predicates.

**Phase 1 — Core working surfaces**
- Roster default (active-in-range) + "All students" toggle.
- Presentations, Checklist, Open Work.

**Phase 2 — Remaining activity**
- Projects (+ session-driven visibility), Meetings, Going Out, Notes lists, Issues,
  calendar.

**Phase 3 — Reports (cycle-first)**
- Attendance + progress reports scoped to the selection; default each child's progress
  report to **their cycle** (cumulative), with a single-year option. Exports respect the
  selection.

**Phase 4 — Optional hardening (only if needed)**
- Add a *nullable* `schoolYearKey` stamped on new activity records, with a one-time
  backfill derived from timestamps. Makes the lens robust if the start date is changed
  later (history won't re-bucket). Additive nullable attribute → CloudKit-safe. Skip
  unless reconfiguring the boundary mid-stream becomes a real need.

## Risks & constraints

- **CloudKit additive-only** — nothing removed; the only schema touch (Phase 4) is a
  nullable attribute. Safe.
- **~40 fetch sites** in `TodayDataFetcher` — broad but mechanical; the single
  predicate-factory keeps them consistent.
- **`@FetchRequest` dynamic predicate** — must rebuild on selection change; verify the
  current Observation / `@FetchRequest` pattern (per CLAUDE.md auto-research) before
  coding.
- **Zero-warnings + Swift 6 strict concurrency** — store is `@MainActor @Observable`.
- **Day-boundary / time zone** — reuse `AppCalendar` for start-of-day normalization.
- **Summer edge case** — with a Sept 1 start, June–Aug falls into the *just-ended* year;
  the configurable start lets the guide shift summer prep into the new year.

## Open decisions (defaults chosen; easy to flip)

1. **Personal vs shared lens** — *default: personal* (`AppStorage`, per-device; each
   teacher picks their own year). Alternative: a shared-store classroom setting so
   co-teachers snap to one active year (more involved).
2. **Default start date** — *default: keep Sept 1*, now editable. Change if summer prep
   should count as the new year.
3. **Cycle window** — *default: rolling 3-year (anchor + 2 prior)* for the global lens;
   **child-anchored** for reports.

## References

- [Montessori Compass — School Year Manager](https://support.montessoricompass.com/article/119-school-year-manager)
  (school years are optional date *filters*; finished years become view-only but stay
  visible; defining discrete years blocks cumulative cross-year reports → they recommend a
  continuous range).
- [Transparent Classroom](https://www.transparentclassroom.com/) (sessions + classrooms;
  never deletes data; full child history retained; supports cumulative multi-year reports).
- [Best Montessori Record-Keeping Software 2026 (onespot)](https://www.onespotapps.com/post/the-best-montessori-record-keeping-software).
- [Forest Bluff — Montessori Assessment & Evaluation](https://www.forestbluffschool.org/montessori-assessment-and-evaluation)
  (no grades/tests; records = presentations, depth, mastery, follow-up across the 3-year
  cycle).
- [AMI Prague — Observation & Record-Keeping](https://amiprague.cz/montessori-observation-and-record-keeping/)
  ("observation is more important than record-keeping").
- [Trillium — Montessori Elementary Planning](https://www.trilliummontessori.org/montessori-elementary-planning/)
  (macro digital record for next-teacher handoff vs. micro daily journal; 5–7 lessons/week
  per child).
