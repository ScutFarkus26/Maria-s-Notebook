# Scheduled pane on hold, and a schedule switcher in the Assistant

> **Working on it.** Written 2026-11-01 from Danny's talk-through (branch `claude/scheduled-section-hold-531dbc`). Approved the same day ("Yes, that's it").
> In short: take the Scheduled pane under Lessons & Work out of the code and keep it at a git tag so it can be brought back or read, and give Daybook Assistant's Schedule tab a switcher between the four schedules in place of the mixed list.

## What Danny wants
- He started with "I want to put the scheduled section on hold." Asked which one, he said both: the Scheduled pane in Lessons & Work and [Schedules](<Plan - Schedules.md>).
- What "on hold" means to him: "remove the code but keep it somewhere so I can bring it back one day, or refer to it."
- Then he saw two mockups of the Assistant with and without its Schedule tab, and changed his mind about Schedules: "maybe I want the schedule. I would like to see daily schedule. Adolescent schedule. Mr. Danny's Schedule. and Morah Devorah's schedule. I'd like to switch between them."
- A third mockup had a four-way switcher at the top of the tab. He said "Yes, that's it" to keeping Schedules with that switcher and putting only the Scheduled pane on hold.
- So **Schedules stays** in both apps, and [Plan - Schedules](<Plan - Schedules.md>) carries on as it was. Its timetables still need entering (Tide row "set up Schedules on the Mac").

## 1. The Scheduled pane goes on hold

### Where its code is kept
- Before anything is removed, the last commit with the pane gets the tag `on-hold/scheduled-pane`. Tags never move and aren't swept up by branch tidying. It goes to GitHub with the merge.
- The pane comes out in **one commit**. To bring it back, `git revert` that commit on top of main, sorting out any conflicts where the code around it has moved. Or copy files from the tag.
- To read it without bringing it back, browse the tag on GitHub, or run `git show on-hold/scheduled-pane:"Cosmic Daybook/Presentations/Planning/WeekPlanSection.swift"`.
- The Progress section below records the commit.

### What Danny loses (no other home for these)
- Dragging a lesson or check-in onto a day. The pane is the app's only day drop target, so reordering within a day and moving a lesson between morning and afternoon go too.
- Move All Forward and Clear All to Inbox. Each item can still be moved or cleared from its own detail.
- Balance AM/PM. The morning/afternoon picker in a lesson's detail stays.
- Seeing the next three days of lessons and check-ins together. Today shows one day. Scheduled lessons don't appear in the Lessons & Work list (apart from Missed).
- The strip's "check today" for work to show first. Before You Start and the Before a Lesson chip stay.

### What still puts things on a day
- **Lessons:** the date and AM/PM pickers in the lesson's detail, Schedule Today on an Inbox selection, Bump on Today, the Parsha sheet, and the MCP tools.
- **Check-ins:** Schedule ▸ Today / next school day / Pick a Day… on the work card and the student page, Schedule Today and Another Day… on a selection, the work detail's Scheduled Check-Ins, Reschedule and Bump on Today, Record Practice, and the MCP tools.

### What goes
- From `Presentations/Planning/`: `WeekPlanSection` and its extensions, `WeekPlanHeader`, `WeekPlanDayWindow`, `WeekDayColumn` and its extensions, `WeekDayColumnDropDelegate`, `PresentationPlannerCard` (and `+ShowFirst`), `WorkToShowFirstPopover`, `WorkCheckPillMenu`, `CalendarKindFilter`.
- The services only the strip calls: `CalendarForwardShiftService` (and `+OnPlan`), `CalendarClearAllService`, `DayBalanceService`, `DayHalfBalancer`.
- From `Work/CheckIns/`: `CalendarCheckInGroup`, `GroupedCheckInViews`, `WorkCheckInPill`, `WorkLogSheet`.
- `Planning/PresentationDropHandling.swift`.
- `WorksAgendaView+Split.swift` and the pane in `+Chrome.swift`, so the list fills the screen.
- The pane's stored settings: open or closed, height, and which kinds show (`UserDefaultsKeys` 119, 174, 176), with their entries in `BackupPreferencesService`. Old preference backups that carry those keys must still restore.
- The iOS lesson sheet that only the strip opened (`WorksAgendaView.swift` `selectedLessonAssignment`).
- The drags that could only ever land on the strip: work cards (`WorkCard+Grid.swift`), Inbox lines (`ReadyToPresentSection+Line.swift`) and multi-selections (`WorkspaceMultiSelection.swift`). The Year Plan's and the Consolidate sheet's drags stay, with `UnifiedCalendarDragPayload`.
- The strip-only parts of shared files:
  - From `WorkToShowFirst`: `todayCheck`, `checkToday`, `checkTodayTitle`, `checkDay`, `message(for:day:)`, `countLine` and `helpText`.
  - From `DayHalfPlanner`: `keptTime`, `inheritedPeriod`, `movingToEndOfHalf` and `times`.
  - Schedules and the MCP tools still use `DayHalfPlanner.moment`, `DayPeriod(scheduledFor:)` and `applied(to:)`, so those stay.
- A route that names a scheduled lesson opens that lesson's detail instead of revealing it on the strip. Nothing in the app sends one today.
- Its tests:
  - `Tests/Planning/`: CalendarPaneSizing, CalendarClearAll, CalendarWorkShift (+Folding, +OnPlan), DayBalance.
  - `Tests/Presentations/`: WeekPlanLayout, WeekPlanCheckInMenu, WeekPlanDayWindow, WeekStripFix1012Pr.
  - `Tests/Work/WorkCheckInPillNamesTests`.
  - The strip lines in the mixed files: WithinDayOrdering, PresentationsEnergyPass, PresentationsTests+Fix1011Pr, ReviewFixes1012A, LessonsWorkFix1017LW, LessonsWorkFix1017ReviewCLW, WorkCheckInIntegrity, and WorkToShowFirstActionTests' check-today cases.
- Comments that describe the list-over-calendar layout (`+History.swift`, `LessonsAndWorkWorkView.swift`, `LessonsAndWorkPresentationsView.swift`, `PresentationsView.swift`, `WorkCard+GridMenu.swift`) get reworded so they don't describe a pane that isn't there.

## 2. The Assistant's Schedule tab gets a switcher

What's there now: `Daybook Assistant/Schedule/AssistantScheduleView.swift` shows every lane in one list. A "Show" menu in the toolbar (`laneMenu`) narrows it to one lane, with an "Only …" line and "Show Everyone" in the header.

Becomes, as in the mockup:
- **A row of buttons at the top of the tab, one per lane**, in the lanes' order. Each button carries the lane's name as Danny set it in the notebook, with the guide's lane under his name. With his four lanes that reads Daily (or whatever he names our class), Adolescent, Mr. Danny and Morah Devorah.
  - Each button is as wide as its name, with a dot in the lane's color. The chosen one is filled.
  - The row slides sideways when the names don't fit, and a chosen lane past the edge is scrolled into view.
  - Changed while building: the mockup's equal-width segmented control cut "Adolescent room" to "Adolescen…" on the iPhone SE, the smallest phone the assistants carry. Buttons sized to their names also cover any number of lanes, so no menu is needed past four.
  - With one lane there is no switcher.
- **One schedule at a time.** "Everyone", the toolbar's Show menu, the "Only …" line and "Show Everyone" go.
- The first time, the tab opens on the first lane. After that it opens on the lane last chosen on that phone. If the guide removes that lane, it goes back to the first.
- The Now card on today shows only what's on now in the chosen schedule.
- The empty-day line already names the lane ("Nothing for Morah Devorah this day.").
- Unchanged: the day arrows and date picker, the header line with the Hebrew date, "1 change today", who is out, the Classroom button, and children only (never a lesson's name) on the guide's schedule.
- The navigation title stays "Schedule". The selected segment shows whose schedule it is.
- The notebook's Schedules page stays as it is, with the four lanes side by side.
- No change to the shared data, the share or backups. The model already filters by lane (`AssistantScheduleModel.laneFilter`, `AssistantScheduleRows.rows(for:lane:names:)`). The Debug screenshot argument `-AssistantScheduleLane` keeps working.
- Tests in `Daybook Assistant Tests/AssistantScheduleTests.swift`:
  - The tab picks the first lane when none is remembered.
  - It keeps a remembered lane.
  - It falls back when that lane is gone.
  - The Now card follows the lane.

## Docs and to-dos
- The user manual's Scheduled strip lines (`Documentation/Manuals/UserManual.md` 405-406) say the pane is on hold, with a link here. The Assistant's Schedule tab description gets the switcher.
- Tide: drop the six open rows that only check the pane (To do.md lines 317, 411, 545, 599, 607 and 905 on 2026-11-01). The two mixed rows (405, 627) stay as written; the strip part of each can just be skipped. The Schedules rows stay.

## How it's built
- Tag first. Then one `feature-phase` agent takes the pane out in its own worktree from this branch. It builds only the notebook's iOS scheme and runs only the suites it touches.
- At the same time, this session builds the switcher here. It touches only Assistant files, builds Daybook Assistant, and runs `AssistantScheduleTests`.
- Then the pane's commit comes onto this branch. After that: one iOS app build, the macOS build, the Assistant build, and the whole suite once.

## Checks
- Builds clean on iOS, macOS and Daybook Assistant, and the whole suite passes.
- Lessons & Work drawn once on the iPhone 17 simulator with the Sample Class: no pane, and the list at full height.
- The Assistant's Schedule tab drawn with its practice class on each of the four schedules.

## Progress
- [x] Tag `on-hold/scheduled-pane`, on c446109a, the last commit with the pane.
- [x] Take the Scheduled pane out (6a6892a4, 2026-11-01). 82 files: 41 deleted (7,516 lines), 41 changed. iOS and macOS builds pass, and the 25 test suites it touches pass (175 tests).
  - Removed beyond the plan, because only the strip used them: `PlanningDropUtils`, `UnifiedCalendarDragPayload.joined` and `parseAll`, `BacklogDragPreview`, `WorkCheckInService`'s unscheduling, `SchoolDayChecker.nextSchoolDays`, `openWork(id:)` and two `UIConstants` paddings.
  - Kept against the plan: the iOS lesson sheet (`selectedLessonAssignment`). It's how `openPresentation` shows a lesson on iPhone and iPad, and the route to a scheduled lesson now uses it.
  - Old preference backups that carry the pane's three keys still restore, since a restore skips keys no longer listed. No format bump; a new test in `BackupPreferencesServiceTests` checks this.
  - Words changed: the Scheduled pill's empty line reads "To give work a day, choose Schedule from its menu." Missed lessons say "Open one to give it a new day." The selection bar's drag hint is gone.
  - Left as they were: about 15 code comments that compare a write to "the Scheduled strip's" (`WorkLogService`, `WorkTypes`, the Today rows, the MCP work-status tool). They change nothing; reword them when the code around them is next touched.
- [x] The Assistant's schedule switcher (f72f51fa, 2026-11-01). `AssistantScheduleTests` and `AssistantScheduleNowTests` pass (12 tests, 2 new). Checked on the iPhone SE (iOS 26.5) with the practice class on all four schedules. The first try, a segmented control, cut "Adolescent room" short, so the switcher became a row of buttons sized to their names.
- [ ] Full builds and the whole suite
- [ ] Docs, the build board and Tide rows
- [ ] Merge to main and push, with the tag
