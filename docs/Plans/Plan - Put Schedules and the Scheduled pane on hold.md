# Put Schedules and the Scheduled pane on hold: out of both apps, kept in git

> **Not started.** Written 2026-11-01 from Danny's request (branch `claude/scheduled-section-hold-531dbc`).
> In short: take the Schedules page (with Today's Schedule section, the Assistant's Schedule tab and the timetable MCP tools) and the Scheduled pane under Lessons & Work out of the code, keep both at a git tag so they can be brought back or read, and leave the saved data's shape alone.

## What Danny wants
- "I want to put the scheduled section on hold." Asked which one, he said **both**: the Schedules page built from [Plan - Schedules](<Plan - Schedules.md>) and the Scheduled pane (the week strip) at the bottom of Lessons & Work.
- On what "on hold" means: "I'd like to remove the code but keep it somewhere so I can bring it back one day, or refer to it."
- No timetable has been entered in the live notebook (checked over MCP on 2026-11-01), so nothing he typed is lost.

## Where the code is kept
- Before anything is removed, the last commit that has both features gets two tags: `on-hold/schedules` and `on-hold/scheduled-pane`. Tags never move and aren't swept up by branch tidying. They go to GitHub with the merge, so the code isn't only on this Mac.
- Each feature comes out in **its own commit**. Bringing one back is `git revert <that commit>` on top of whatever main is then (with conflicts to sort if the code around it has moved), or copying files from the tag.
- Reading the code without bringing it back: browse the tag on GitHub, or `git show on-hold/schedules:"Cosmic Daybook/Schedules/Views/SchedulesView.swift"`.
- This plan's Progress section records both removal commits and the file lists, and [Plan - Schedules](<Plan - Schedules.md>) gets the status line `Won't do. 2026-11-01. On hold:` with a link here.

## 1. Schedules (both apps)

About 10,800 lines in 63 files, code and tests.

**Goes:**
- The notebook's Schedules page: `Cosmic Daybook/Schedules/Views/` (14 files), `Schedules/Services/` (7 files: the timetable service, the day resolver, the booking publisher that copies planned lessons into the share, the lesson plan reader), `Schedules/Model/ScheduleDay.swift` and any of `TimetableValues.swift` the data classes don't need.
- The sidebar row (`RootView+NavigationItem.swift` `.schedules`, `RootView+NavigationGroup.swift`, `RootDetailContent.swift`). A window that was left on Schedules opens on Today, the existing fallback for retired rows (keep the case's raw value as an alias if that's the pattern there).
- Today's Schedule section (`TodayScheduleRows.swift`, `TodayViewScheduleSection.swift`, and its entries in `TodaySectionVisibility`, `TodayViewSectionOrder`, `TodayViewModel` and `+Refresh`).
- The three MCP tools `weekly_schedules`, `set_timetable` and `change_schedule_day` (`MCPNotebookTools+Timetable.swift`, `+TimetableWrites.swift`); the tool count goes from 97 to 94.
- The booking publisher's start-up (`AppBootstrapper+Schedules.swift`, `AppBootstrapper.swift:103-107`) and the Sample Class timetable (`SampleClassroomSeeder+Timetable.swift`).
- `Parsha/Services/HebrewDateText.swift`, which only Schedules used.
- Daybook Assistant's Schedule tab (`Daybook Assistant/Schedule/`, 5 files, and its entry in `AssistantTabs.swift` and `AssistantSampleClass.swift`), and the 16 notebook files that were added to the Assistant target by hand for it (`project.pbxproj`). Those files stay in the notebook where other code uses them (`Weekday`, `HebrewParshaService*`, `TodayHeaderText`, `CloudKitUUID`).
- The tests for all of the above (about 21 files). The Community Topics tests in `ScheduleAndTopicTests+Fix1010F.swift` (lines 102-166) move to a file of their own first.

**Stays, deliberately:**
- **The saved data's shape.** The four timetable types (CD_TimetableLane, CD_TimetableBlock, CD_TimetableChange, CD_TimetableBooking) stay in the Core Data model, in the classroom share and in backups, with their small data classes (`Schedules/Model/Timetable*Entity.swift`).
- Why: they are already in CloudKit Production, which can't delete record types. Taking them out of the model or the share is a schema change (schema 23): every device and the Assistant would have to update together, and a schema-22 copy would refuse to open the store. Dropping them from backups is a backup format change. Leaving them costs about 400 lines and nothing at run time, since nothing reads or writes them. And bringing Schedules back then needs no CloudKit step at all.
- The older per-child Schedule and ScheduleSlot types from March, already unused apart from backup, stay as they are. Not part of this.
- `TodayAbsentMover`'s `receipt.schedules`, which is about lessons' planned dates for Undo, not this feature.

## 2. The Scheduled pane (Lessons & Work)

About 25 strip files plus about 12 test files.

**What you lose.** The pane is the only place for these, and none of them will have another home:
- **Dragging a lesson or a check-in onto a day.** It's the app's only day drop target, so reordering within a day and moving a lesson between morning and afternoon go too.
- **Move All Forward and Clear All to Inbox.** Each lesson or check-in can still be moved or cleared one at a time from its own detail.
- **Balance AM/PM.** The morning/afternoon picker in a lesson's detail stays.
- **Seeing the next three days of lessons and check-ins together.** Today shows one day. Scheduled lessons don't appear in the Lessons & Work list at all (apart from Missed), so in Lessons & Work they'll be out of sight.
- **The strip's "check today" for work to show first.** Before You Start in the lesson's detail and the Before a Lesson chip stay.

**What still puts things on a day:**
- **Lessons:** the date and AM/PM pickers in the lesson's detail, Schedule Today on a selection in the Inbox, Bump on Today, the Parsha sheet, and the MCP tools.
- **Check-ins:** Schedule ▸ Today / next school day / Pick a Day… on the work card and the student page, Schedule Today and Another Day… on a selection, the work detail's Scheduled Check-Ins, Reschedule and Bump on Today, Record Practice, and the MCP tools.

**Goes:**
- From `Presentations/Planning/`: `WeekPlanSection` and its extensions, `WeekPlanHeader`, `WeekPlanDayWindow`, `WeekDayColumn` and its extensions, `WeekDayColumnDropDelegate`, `PresentationPlannerCard`, `WorkToShowFirstPopover`, `WorkCheckPillMenu` and `CalendarKindFilter`.
- The services only the strip calls: `CalendarForwardShiftService`, `CalendarClearAllService`, `DayBalanceService` and `DayHalfBalancer`.
- From `Work/CheckIns/`: `CalendarCheckInGroup`, `GroupedCheckInViews`, `WorkCheckInPill` and `WorkLogSheet`.
- `Planning/PresentationDropHandling.swift`.
- `WorksAgendaView+Split.swift` and the pane in `+Chrome.swift`, so the list fills the screen. Also the pane's stored settings (open/closed, height, which kinds show), with their entries in `BackupPreferencesService`, and the iOS lesson sheet only the strip opened.
- The drags that could only ever land on the strip: work cards, Inbox lines and multi-selections. The Year Plan's and the Consolidate sheet's drags stay.
- The strip-only parts of shared files: `WorkToShowFirst`'s check-today members, and `DayHalfPlanner`'s `keptTime`, `inheritedPeriod`, `movingToEndOfHalf` and `times`. `moment`, `DayPeriod(scheduledFor:)` and `applied(to:)` stay.
- Its tests (`Tests/Planning/` CalendarPaneSizing, CalendarClearAll, CalendarWorkShift×3 and DayBalance; `Tests/Presentations/` WeekPlanLayout, WeekPlanCheckInMenu, WeekPlanDayWindow and WeekStripFix1012Pr; `WorkCheckInPillNamesTests`), plus the strip lines in about eight mixed test files.
- A route that names a scheduled lesson (nothing in the app sends one today) opens that lesson's detail instead of revealing it on the strip.

## Docs and to-dos
- The user manual's lines on both features, `MCP_SERVER.md`'s tool counts and the three tools, `Cosmic Daybook/CLAUDE.md`, `DATA_MODELS.md`, `BACKUP_SYSTEM.md` and `DeveloperManual.md` say the features are on hold, with a link here. The data types' notes say why they stay.
- [Plan - Schedules](<Plan - Schedules.md>) becomes Won't do (on hold), and `docs-index` rebuilds the map.
- Tide: drop the ten open rows that only check these two features (To do.md lines 129, 317, 411, 545, 599, 607, 727, 731, 733 and 905 on 2026-11-01). The four mixed rows (405, 627, 699, 751) stay as written; the strip or Schedules part of each can just be skipped.

## How it's built
- Tag first, then two agents at once, each in its own worktree from this branch:
  - **Schedules:** `feature-phase-deep`, because it touches sharing, sync, backup and the model's fingerprint test.
  - **Scheduled pane:** `feature-phase`, a screen.
- The two touch different files apart from the docs, which this session writes after both land.
- Each agent builds only its smallest target and runs only its own `-only-testing:` suites. The Schedules agent also builds Daybook Assistant.
- This session puts the two branches together as two commits, then runs the one iOS app build, the macOS build, the Assistant build and the whole suite once.
- **Stop-and-ask rule for the Schedules agent:** if keeping the four types needs any change to the schema number, the model's fingerprint, `sharedEntityNames` or the backup format version, it stops and reports instead of making it.

## Checks
- Builds clean on iOS, macOS and Daybook Assistant, and the whole suite passes (fewer tests than the 2026-10-30 count, by the removed files).
- `CoreDataSchemaVersionTests` and the backup golden files pass **unchanged**. That's the proof the data's shape didn't move.
- Lessons & Work and Today drawn once on the iPhone 17 simulator with the Sample Class: no pane, the list full height, no Schedule section, and no Schedules row in the sidebar.

## Questions for Danny
1. Are you happy to lose the pane's jobs listed under "What you lose", with nothing in their place for now?
2. May the two tags go to GitHub with the merge?
3. May I drop the ten Tide rows?

## Progress
- [ ] Tag `on-hold/schedules` and `on-hold/scheduled-pane`
- [ ] Remove Schedules (commit: )
- [ ] Remove the Scheduled pane (commit: )
- [ ] Docs, Plan - Schedules status, Tide rows
- [ ] Full builds and the whole suite
- [ ] Merge to main and push, with the tags
