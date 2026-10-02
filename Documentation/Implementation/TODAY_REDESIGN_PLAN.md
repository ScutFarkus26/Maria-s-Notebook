# Today redesign plan

Source: the "Today View Redesign" canvas (https://claude.ai/artifact/APGbKvVfA6j3T1fuqfzwPR), Mac Before/After
boards with numbered red (problem) and green (fix) notes and a blue efficiency note. Danny approved the plan on
2026-10-02 with these decisions:

1. The Mac todo editor moves into an **inspector panel** on the right (`.inspector`), not into the agenda column.
2. The sync dot is **hidden while sync is fine**, app-wide; it appears for syncing, pending, error and offline.
3. The school-year picker is **hidden on Today only**.
4. Scheduled meetings get **their own small section** ("Meetings") between Lessons and Gone quiet.

Branch `claude/today-view-analysis-275c3c`. No Core Data schema change: `TodoItem.linkedWorkItemID` already exists
and is already in the backup (`BackupTypes+Misc.swift:17`), but nothing reads or writes it yet.

Coordination: the Checklist redesign session (branch `claude/checklist-view-analysis-5d42f6`) edits
Components/Checklist/**, Components/ClassSubjectChecklistView.swift, Components/StickyLeftItem.swift,
CurriculumMap/*, Lessons/Checklist/ViewModels/**, Students/Progress/StudentChecklistState.swift and one line in
AppCore/Constants/UserDefaultsKeys.swift. Stay out of those. It stays out of Today/, Todos/, RootView.swift,
Commands, TodoTag and the MCP tools.

All paths below are under `Cosmic Daybook/`.

## Phase 1 — Engine (efficiency; no visible change)

- **Open work fetched once per reload.** `TodayViewModel.swift:249` calls `TodayDataFetcher.fetchWorkData`, and
  `TodayWorkLoader.loadWork` (`TodayWorkLoader.swift:58`) fetches it again. Pass the first result through.
- **Students through the roster store, not whole-table fetches.** `TodayCacheManager.loadStudentsIfNeeded`
  (`TodayCacheManager.swift:43`) refetches every student whenever an ID is missing. Departed and hidden students
  never get cached, so this repeats about 5 times per reload. The recent-notes step (`TodayViewModel.swift:316`)
  and the departed-student fetch (`TodayFollowUpLoader.swift:47`) do it again. Cache misses too, or resolve
  through `RosterStore`.
- **Refresh after edits in other windows.** Nothing reloads Today when work, a presentation, a check-in or a todo
  changes in its own window. Add `ManagedObjectChangeFlag`s (the Roster and Meetings pattern; see
  `MeetingQueueModel`) for those entities and feed them into `scheduleReload()`. Watch the onReceive-debounce
  gotcha: keep the debounce on the model.
- **Todos fetch with a predicate.** `TodayViewTodoSection.swift:69` fetches every incomplete todo, then filters
  and sorts in memory on every redraw. Use a predicate for incomplete and not someday, plus due or scheduled on or
  before the selected day, or no date if the section shows those today. Keep current behavior.
- **Lesson rows stop walking attachments** (`TodayViewAgendaSection.swift:167`) on every draw. Compute "has a
  plan" once per reload in the loader.
- **Quiet-work true count.** `TodayScheduleBuilder.swift:113` keeps the top 15 stale items. Keep the 15 rows, but
  expose `staleTotalCount` so the UI can say "See all 15+" / the real number.
- Expose for later phases (no UI yet): absent student IDs for the selected day (reuse
  `PresentationRecorder.absentStudentIDs`) and a per-work list of linked open todos (`linkedWorkItemID`).
- Measure: an `os_signpost` interval around `reload()`, plus a count of fetches before and after. Put the
  numbers in the commit message.

## Phase 2 — Mac layout

- `TodayViewSectionOrder.swift:66` `twoColumnLayout`: the **plan becomes the wide left column** (Lessons,
  Meetings, Gone quiet), with a **340-pt right column** holding the Needs-a-lesson card, Todos, then the
  count-gated sections (Watching, Ready for next, Following presentations, Recent notes, Calendar, Reminders,
  Parent reports, Day Pad, Done today). Keep `TodaySectionVisibility` as the single rule. Update
  `macLeftColumnOrder`/`macRightColumnOrder` and their tests.
- **Right Now goes away on the Mac.** Next Up becomes the highlighted first card (phase 3). "Open work to check"
  becomes the Gone quiet header (phase 4).
- **The todo editor moves to an inspector** (`.inspector(isPresented:)`, about 320 pt) and no longer replaces the
  agenda (`rightColumnContent`, `TodayViewSectionOrder.swift:98`).
- The Needs-a-lesson card (`TodayViewDayCardsSection.swift`): title "N children need a lesson", subtitle "No
  presentation in 7+ school days.", buttons **Plan lessons** (the current chevron route
  `navigateToLessonsAndWork(.toSchedule)`) and **Hide until tomorrow** (the current × behavior, now named).

## Phase 3 — Lesson and meeting rows

- `LessonListRow` (`TodayViewListRows.swift:99`): the lesson title first (semibold), then the children as chips in
  short-name format. Absent children are struck through, gray, and labeled "absent". Trailing "6 of 7 here"
  ("all 4 here" when everyone is). No count badges.
- **The Next card:** the first unfinished agenda item is drawn highlighted (accent border and tint), with a
  **Present** button and **⌘↩**. It opens the same thing the old Next Up play button opened
  (`TodayViewRightNowSection.swift:182` logic). If no lesson is pending, it falls back to the first due check-in,
  as now.
- **Move absent children to tomorrow:** per lesson (row menu + an inline link when that lesson has absent
  children) and once in the Lessons header ("N children on today's lessons are absent · Move them to tomorrow").
  Implementation: `PresentationRecorder.keepOnPlan` (absent children → their own assignment), then that
  assignment's `schedule(onDay: tomorrow)` (see `bumpLessonToTomorrow`, `TodayViewAgendaSection.swift:219`).
  One save, a toast with Undo. Never automatic.
- The header reads "Lessons · 0 of 4 given".
- **Meetings section:** the agenda's scheduled meetings move into their own small "Meetings" section after
  Lessons, hidden when empty.
- Keep drag-to-reorder, the right-click menu (Mark Presented, Bump to Tomorrow, Add Note) and click-to-open.

## Phase 4 — Gone quiet, and linking todos to work

- The section header is "Gone quiet", with the subtitle "open work nobody has touched in 10+ days" and a trailing
  "See all N" (the true count from phase 1) that opens Lessons & Work.
- Rows (`GroupedFollowUpWorkListRow`, `FollowUpWorkListRow`): the work title first, then the children as chips
  (absent struck through). The age chip reads "19d quiet", orange from 18 days. A **Schedule check-in** button
  (the existing check-in scheduling, defaulting to the next school day). Flexible-style groups still expand.
- **Linked todos:** a work row shows its open linked todos ("3 todos · Sep 18", red when overdue). Recording a
  check-in, or marking the work touched, completes its linked todos. Linked todos whose work is on screen leave
  the Todos list (no duplicates).
- **MCP:** `add_follow_up` (`MCPNotebookTools+FollowUps.swift`) and `update_todo` gain an optional `work_id`
  that sets `linkedWorkItemID` after validating that the work exists. Reads (`list_todos`) return
  `linked_work_id`. Update the tool descriptions.
- **Todo tag chips** (`AgendaItemRows.swift:117`, `TodoTagHelper.tagName`): a `Students/<Full Name>` tag shows
  the canonical short name ("Naomi F"). Other tags are unchanged.

## Phase 5 — Header, toolbar, attendance band

- **Title and date:** the Mac window subtitle shows "Wednesday, September 23" (`navigationSubtitle`). The stepper is
  ‹ Today ›, with the middle button always visible and disabled when already on today.
  `TodayViewHeader.swift:15–70`.
- **School-year picker hidden on Today** (`RootView.swift:449`, `ToolbarItem(id: "schoolYear")`): conditional on
  the selected nav item.
- **Sync dot only when it says something** (`RootView.swift:461`, `CompactSyncStatusIndicator`): hidden while
  synced and idle; shown for syncing, pending, error and offline. App-wide.
- **Day Pad** toolbar button gets a text label.
- **Attendance band** (`TodayViewHeader.swift:81`): one line, "19 here" (large) · "2 late" (amber dot; the names
  in a hover popover / `.help`) · "3 absent" (gray dot) with the absent children as neutral gray chips, then
  "Attendance ›". No red fills. Keep the right-click "Mark Tardy" on chips and click-to-expand.

## Phase 6 — Floating button

- Keep `QuickNoteGlassButton` and its long-press pie menu (Danny wants it). Give Today's scrolling lists a bottom
  `safeAreaInset`/content margin so the button never covers a row. Today only; the Checklist session handles its
  own grid.
- **File ▸ New** commands for the button's five create actions, with ⌘ shortcuts that don't clash with existing
  commands (grep `keyboardShortcut` app-wide first). The Checklist session adds no ⌘ shortcuts.

## Phase 7 — iPhone and iPad

- The shared rows bring phases 3 and 4 along automatically. Check the phone order (`phoneSections`,
  `TodayViewSectionOrder.swift:48`): the Next card first, then Lessons, Meetings, Gone quiet, Todos. The iOS
  toolbar keeps its + menu. The attendance strip stays hidden on compact iPhone.
- Render iPad and iPhone screens with the hosting-window test technique (see memory
  mac-attendance-redesign-2026-10-01) or the scratchpad XCUITest walker on the Sample Class. Never launch a Debug
  Mac build (it opens the live store).

## Data steps after landing (only with Danny's OK)

- Link the five "Check in with … on …" todos to their work over MCP (`update_todo` `work_id`).
- Mark the two "[Moved to Tide]" todos done.

## Verification

- Unit tests (Swift Testing) for: absent-on-lesson marking and "N of M here"; linked-todo folding (on-screen work
  hides the todo; check-in completes it); the true quiet-work count; the visibility and order rules; the tag
  short name; MCP `work_id` validation.
- `-only-testing:` per phase; the macOS build each phase; the full iOS suite once at the end.
- The Mac UI is checked by Danny (Tide: Check on a device).

## Status

| Phase | State | Commit |
|---|---|---|
| 1 Engine | Done. Fetches per reload 18–20 → 13; refresh after edits in other windows | d0318a33 (merged) |
| 2 Mac layout | Done: plan on the left, 340-pt right column, todo inspector, Needs-a-lesson card with named buttons; Mac UI unseen | 587a77bb |
| 3 Lesson & meeting rows | Done: chips + "N of M here", Next card (Present ⌘↩, off while the attendance grid is open), `TodayAbsentMover` with Undo, Meetings section; Mac UI unseen | 217fa50c |
| 4 Gone quiet + linking | Done: Gone quiet section (title + chips, "19d quiet", Schedule check-in on the next school day, "See all N"), linked todos on work rows and out of Todos, completion on check-in and work log (with Undo), roster tag names; non-UI a8a69769; Mac UI unseen | a8a69769 + e2bb4428 |
| 5 Header/toolbar/band | Done; Mac UI unseen | e21a337d |
| 6 Floating button | Done (File ▸ New already had all five; New Work now targets the front window); Mac UI unseen | e21a337d |
| 7 iPhone/iPad | Done: Right Now retired everywhere (view, `.rightNow`, dead `todaysSchedule`/`overdueSchedule` deleted; the check-in Next card now draws on iOS too); phone order Lessons (Next card first) · Meetings · Gone quiet · Needs-a-lesson · Todos · rest; iPad uses the same list under the band. iOS toolbar is ‹ Today › · Go to Date · + with the day as the large title's subtitle (the date field had pushed Today and + into •••); linked-todo date printed "M10 1" on AppCalendar (empty root locale), fixed. iPhone + iPad mini rendered | 8e44d18a |

## Handoff notes for phases 2–4 UI

- **What the view model already has:** `staleTotalCount`, `absentStudentIDs` and `TodayLessonsLoader.lessonIDsWithPlan`.
  `TodayLinkedTodos` (Today/Support) is the pure folding helper.
- **Wire `TodoCompletionService.completeTodosLinked(toWork:in:)`** at `WorkLogService.log`
  (Work/Completion/WorkLogService.swift:98, where `lastTouchedAt` is set; this needs undo-token support) and at
  `WorkCheckInService.markCompleted` (:38, used by Today's `completeCheckInFollowUp`).
- When the view model starts reading linked todos, **add `"TodoItem"` to the refresh trigger** in
  `TodayViewModel+Refresh.swift`.
- **`AgendaItemRows.swift:118`** now calls `TagHelper.displayName(_:contextOf:)`, which does one small student fetch per
  render. Replace it with `RosterStore.shortNamesByFullName` when the rows are rebuilt.
- The header agent added a **calendar popover button** next to ‹ Today › for jumping to far-off days (not in the
  mockup; Danny may drop it).
- **Agents:** a session guard blocks writes outside the session's own worktree. Run UI agents in this worktree
  (one at a time) or with `isolation: "worktree"` (then `git merge --ff-only claude/today-view-analysis-275c3c` first).
- The `today-engine`, `today-header` and `today-mcp` worktrees and branches are merged or abandoned; remove them.

## Handoff notes for phase 7 (after phase 4 UI)

- The completion wiring, the `"TodoItem"` refresh trigger and the roster tag names above are done.
- Gone quiet is in `phoneOrder` after Meetings, so the phone already draws it. iPhone's Right Now still shows "Open
  work to check" (`openWorkToCheckCount`, scheduled + quiet), which now repeats Gone quiet's header; decide there.
- Gone quiet rows are no longer reorderable (sorted most quiet first). Schedule check-in opens `WorkCheckDayPicker`
  (popover on the Mac, sheet on iOS, `DayPickerPresentation`) on the next school day.
- Work with a scheduled check-in still ahead is no longer counted as quiet (`TodayScheduleBuilder`), so scheduling
  one takes the row off; `staleTotalCount` follows.
