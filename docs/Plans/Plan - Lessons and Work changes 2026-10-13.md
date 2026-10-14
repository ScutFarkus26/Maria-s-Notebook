# Lessons and Work changes (2026-10-13)

> **Working on it.** Written 2026-10-13 from Danny's inventory of seven changes (session on branch `claude/changes-inventory-8960e5`).
> In short: a tidier student picker, a three-day Scheduled strip, a Finished work status, a steady sync dot, moving children between groups, "work to show first" before a lesson, and Move All Forward / Clear All that handle every open check-in.

Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (milestones 18–21).

## Goal

Lessons & Work gets easier to run a day from, on Mac and iPad.
- The present-a-lesson picker lists only children in the class now, with the selected children first, then the ones ready for the lesson.
- The Scheduled strip shows three wider days, starting today.
- Work can be closed as Finished when mastery doesn't apply.
- The sync dot stops shoving the toolbar around.
- A child can be moved between a lesson's groups from a right-click menu.
- Before a lesson, Danny can see which children have work from earlier in that sequence to show first: on the strip, in the present sheet, and as a Work-tab filter.
- Move All Forward and Clear All to Inbox handle every open check-in, including overdue ones, and every child's linked copy.

## Progress
- [x] Phase 1: Student picker (#1) (session: agent, Phases 1–5 started at 78%) ‖ 2 ‖ 3 ‖ 4 ‖ 5 · est. ~1–2% weekly · branch `worktree-agent-a7064b2f8b1ddd661` 8d9fbac7, 38 tests pass. Differed: still passes the whole roster but a rule drops anyone who has left unless already on the presentation; the Selected run is fixed when the picker opens (rows don't jump under a tap); the Level row hides entirely when fewer than two levels have enrolled children.
- [x] Phase 2: Three-day strip + Move forward / Clear all (#2, #7) (agent) · est. ~2–4% · branch `worktree-agent-abde1e2d307e245a5` b4aae71d, 106 tests in 12 suites pass. The reproduction found Move All Forward left behind: earlier-day open checks (and their linked copies), check-ins linked only by relationship (no `workID`), and every check when Show was set to Presentations. Differed: a check landing on a day that already has one for that work is marked Skipped (not deleted) so Undo and notes survive; Clear All covers every planned presentation and open check on any day, whatever Show says, and asks with counts; the `LessonsAgenda.startDate` key is gone.
- [x] Phase 3: Finished work status (#3) (agent) · est. ~1–2% · branch `worktree-agent-ab9072863d914b1ac` 5508a48e, 103 tests in 13 suites pass. Differed: kept the gray checkmark; meeting-card outcome buttons don't offer Finished; the six-pill wrap in the work sheet wasn't rendered; `Documentation/Manuals/UserManual.md:359` still lists the old statuses (fix in Phase 7).
- [x] Phase 4: Steady sync dot (#4) (agent) · est. <1% · branch `worktree-agent-a1c8f458819d45ef1` 4caa975b. Differed: the no-shift check renders a stand-in toolbar (`SyncDotSlotTests`); the real Mac and iPad toolbars are a by-hand check. `SyncStatusSignalsTests` doesn't exist.
- [x] Phase 5: Move a child between groups (#5) (agent) · est. ~1–2% · branch `worktree-agent-a036c4342cee3b4dc` 9bfa40fa, 38 tests in 4 suites pass; iPad simulator long-press opened the menu without starting a drag. Differed: Undo included (rebuilds an emptied group with its notes); a new group copies Unlock Lesson; menu on ready lessons only; dragging a chip uses the same move code; Mac right-click not seen.
- [ ] Phase 6: Work to show first, A + D + E (#6) (agent, after 1–5 are combined; started at 80%) · est. ~2–3%
- [x] Phase 7 (for Phases 1–5): combined, reviewed, fixed, landed (main session) · est. ~3–5% · weekly 78% → 81% for Phases 1–5 and this landing. Five clean merges; Mac, iOS and Assistant builds clean; whole suites 3,799 + 349 pass. One Opus review found 9 issues (mastery marks lost on group moves; Clear All left noted checks scheduled; departed children's checks moved; stale checks pinned the strip; raw-ID lesson names on 5 screens; unchecked Undo saves; 3 small); a fix agent fixed 8 test-first (a503cca8); the 9th (the sync-dot test is a stand-in) is a device check. Differed: the strip now hides pills for closed work and departed children.
- [ ] Phase 7 again, for Phase 6
  - [x] Review fixes, Phases 1–5 (agent, 2026-10-14): 8 findings fixed with failing-first tests; 103 tests in 13 suites pass; iOS and macOS builds clean. Group moves keep mastery marks; Clear All marks a check with its own note Skipped (Undo restores it); Move All Forward, Clear All, their counts and the strip all leave out closed work and departed children's checks (the strip now hides those pills too); no raw lesson-id names on screen; Undo saves roll back with a plain message on failure. Not checked by hand: the Undo failure toast.

## Cost

About 11–19% of the weekly all-models limit (Max plan). At planning time 77% was used, so 23% is left until Sat 18 Oct, 4 pm. That's tight. Phases 1–5 and 7 for them (about 8–14%) fit. Run Phase 6 and a second Phase 7 pass for it after the reset unless Phases 1–5 come in under estimate. Check usage before starting Phase 6. **Danny's stop line (2026-10-14): stop at a good point once weekly use reaches 87%.** Finish or park the step in hand, commit, and leave a note here and in Tide. Phases 1–5 run at once. They queue for the one build line, so the 5-hour window (9% used) won't be strained.

## Decisions

**#1 Student picker** (`Students/Selection/StudentPickerPopover.swift`, `StudentPickerModel.swift`, caller `Students/Presentations/PresentationDetailView+PlanningSections.swift:208`)
- Only the present-a-lesson caller changes from `formerStudents: .shownBlocked` to hidden. Its list becomes `dependencies.roster.enrolled` (minus test students), not `.all`.
- A withdrawn child who is already on this presentation stays listed under Selected, so they can still be removed.
- **Ready** means the ready-queue meaning Danny confirmed: confirmed or mastered on the lesson before this one in the sequence, and not yet had or planned this one. The rules are those of `ReadyGroups` (`Planning/Services/ReadyGroups.swift:172`), ready children only.
- Add a helper that computes ready children for **one** lesson. Don't build all of `ReadyGroups` for a popover. It reuses the same engine rules, so the two can't drift. Test that it skips children already planned for the lesson and matches `ReadyGroups` for the same input.
- Ready children get a highlight (a small "Ready" tag or tint in the row) plus their place in the order.
- **Order in this caller:** Selected, then Ready, then everyone else, each group A–Z by display name. The Age sort menu is hidden in this caller. The other callers keep their sort menu and the remembered `studentPickerSortOrder`.
- **Level row:** a level with no enrolled children isn't offered, in every caller. That removes Lower today without hard-coding it, and it comes back if Lower children are ever enrolled again. "Select All <level>" follows the visible levels.
- Ruled out: removing `.lower` from `CDStudent.Level`. It's stored data and still used by history.

**#2 Scheduled strip** (`Presentations/Planning/WeekPlanSection*.swift`, `WeekPlanDayWindow.swift`; Mac and iPad share it)
- `visibleDayCount` goes from 5 to 3. The narrow-pane fallback in `WeekPlanSection+Layout.swift` still drops below 3 when it must.
- It opens at today, with today in the leading column, every time. `UserDefaultsKeys.lessonsAgendaStartDate` is no longer used to restore the start date. Delete the key's reads, and leave the key name in `UserDefaultsKeys` only if something else reads it.
- `settleStrip` stops writing `startDateRaw`. Take the key out of `BackupPreferencesService:77` only if nothing else reads it.
- **Earliest day:** you can't scroll before the earliest day holding an unpresented scheduled presentation (the strip's `@FetchRequest`, first with `scheduledFor != nil && !isGiven`) or a `.scheduled` `CDWorkCheckIn`. When there's nothing earlier, that limit is today.
- Enforce it by never building columns before that day, in both places columns are made: the first window in `WeekPlanSection+Data.swift` (initial days and `windowMargins`) and `WeekPlanDayWindow.grown`. A custom `ScrollTargetBehavior` is ruled out, because Apple has no clamp API (Apple guidance 1).
- The arrows page by the visible count (3 days). The header range shows the three visible days.
- Keep `.viewAligned(limitBehavior: .never)`. Free scrolling with day snapping was chosen on purpose (TestFlight 300000000009).

**#3 Finished status** (`Work/Models/WorkTypes.swift:37`)
- Finished reuses the existing `WorkStatus.done` (raw `"complete"`, "closed with no verdict"). Don't add a new raw value. Every build already knows `"complete"`. A new value would read as Working on older builds, and an older build's backup importer (`BackupEntityImporter+Work.swift:31`, `mergedStatus ?? .active`) would silently reopen Finished work.
- `displayName` changes from "Done" to "Finished". `.done` joins `pickable` for every work type, between Mastered and Keep Practicing. Update the "never offered in a picker" doc comments in `WorkTypes.swift`.
- Rows closed as legacy Done before 2026-09-15 will show as Finished too. That's correct, because both mean closed with no verdict.
- Give it an icon and color clearly distinct from Mastered. The legacy gray `checkmark.circle.fill` is fine if it reads well next to Mastered's star.
- `WorkStatusMigration` only rewrites `"complete"` rows that carry an outcome. New Finished rows have none, so they stay put. Add a test that shows this.
- No schema change and no backup format bump. Closing goes through `WorkLogService.log` only. That stamps `completedAt`, writes the completion record, finishes that day's check-in, skips later ones and completes linked todos, exactly as Mastered does.
- **Not mastery anywhere:**
  - It never sets `masteredAt` (work never did).
  - The "Unlock" logic in `WorkDetailView.swift:50` treats it like any closed, non-mastered status.
  - `MCPNotebookTools+MasteryCandidates.swift:209` counts it as practice evidence, like `done`. It shows the child did the work, not that they mastered it.
  - Parent reports (`MonthlyReportContextBuilder.closedWorkPhrase`) say "finished".
- Check every place that handles `.done` and gives a user-facing word. The compiler already covers exhaustive switches, so the misses would be in `default:` branches, `== .mastered || …` checks and string predicates. Those places are:
  - `WorkDetailViewModel:343` `sortKey`.
  - `SequenceRecapBlocks:397`.
  - `MonthlyReportContextBuilder:369`.
  - `WorkDecisionCard:38`.
  - `ChatContextAssembler`.
- Wherever a person or Claude reads the word, it changes from "Done" to "Finished".
- The MCP `update_work` text (`MCPNotebookTools+WorkWrites.swift:223/248/250`, `+WorkCompletion.swift:84`) already offers `complete`. Its description changes to call it Finished. Keep the accepted value `complete`, and accept `finished` as an alias.
- The Assistant never reads `WorkStatus`. No device-order constraint.
- Tide row already added: "Review whether the new Finished work status should appear for every work type".

**#4 Steady sync dot** (`Components/Shared/SyncStatusIndicator.swift`, `AppCore/RootView/RootView.swift:340-363`, `RootView+Chrome.swift:12-82`)
- The Mac toolbar item always keeps its slot. Replace `.hidden(!isShown)` with opacity 0 to 1, and have the view always lay out its `Circle` at a fixed size, changing only opacity and color.
- Keep `.hidden(isSampleClass)`, since that doesn't flip during a session.
- Give the item its own group with `.sharedBackgroundVisibility(.hidden)`, so its appearance can't resize the neighboring glass capsule (Apple guidance 3).
- Apply the same fixed slot in the iPad `searchAndSyncOverlay` and the iPhone `mobileContextBar` (opacity, not `if`).
- **Quiet:** a soft fade in and out, with no pulsing. Under Reduce Motion it appears without animating. Never use a flag-keyed `repeatForever`, which burns CPU on an idle Mac (memory: repeatforever-flag-spinner). The plain-English `.accessibilityLabel` stays.
- `SyncDotVisibility` rules are unchanged.

**#5 Move a child between groups** (`Presentations/Overview/ReadyToPresentSection*.swift`, `ReadyBacklogRowViews.swift:31` `BacklogStudentChip`)
- A group is its own unscheduled `CDLessonAssignment` for the lesson. Moving a child removes their ID from one assignment and adds it to the other.
- "Move to a New Group" creates a new unscheduled `CDLessonAssignment` for the same lesson, copying the source's lesson-level fields. Copy only those fields, and no presentation records or notes.
- If the source group is left empty, it's deleted.
- **The write:** reuse the existing student-move path, `PillDropDelegate.move(_:from:to:)` with `PresentationRecordCleanup.moveStudents`. The child's own records (notes, promoted year-plan entries) move with them, and the new group copies nothing.
- When the source group empties, run `prepareToMerge` before deleting it, so its notes aren't cascaded away. Call `updateDenormalizedKeys()` on both groups.
- `ConsolidatePresentationsSheet` does its work by hand, so don't copy from it. Put the move in one small service function with tests.
- It offers Undo the way the line menu's other actions do, if that's cheap. Otherwise it saves without Undo, matching Merge Groups.
- **Menu:** `.contextMenu` on `BacklogStudentChip` (right-click on Mac, long-press on iPad) with:
  - "Move to Group N" for each other group, in a `Menu` submenu when there are more than three.
  - "Move to a New Group".
- It's offered on any ready lesson where the child's group has two or more children (Danny chose this for single-group lessons too). A lone child in a multi-group lesson still gets "Move to Group N".
- **Dragging:** the whole line stays draggable. The chip's long-press menu versus the line's drag is undocumented by Apple (Apple guidance 2), so it needs a by-hand iPad check.

**#6 Work to show first** (A strip card, D present sheet, E Work tab)
- **Definition (Danny):** a child's open work whose `lessonID` is a lesson earlier in the same sequence as the scheduled lesson (`LessonSequenceOrder`, `BlockingAlgorithmEngine+SequenceOrder.swift`), using `WorkStatus.openPredicate`.
- One service, `WorkToShowFirst` (new, in `Presentations/Planning/`), answers "lesson + children → [child: [work]]" with a single batched fetch. It reuses `BlockingAlgorithmEngine.gatingWork(for:among:)` if it matches the definition, otherwise `LessonSequenceOrder` IDs plus `lessonID IN …`. A, D and E all read it, and it's unit-tested.
- **A:**
  - The strip already has a ring for blocking work that it turns off by passing `blockingWork: [:]` (`WeekDayColumn+Bands.swift:120`). Feed it from `WorkToShowFirst` for each visible day.
  - The chip shows the amber mark from the mockup, and the card adds a "N to check first" line.
  - Clicking or tapping a marked chip opens a popover listing the work, with Open Work and Check Today. Hovering on Mac adds a `.help` tooltip naming the work.
  - The popover opens on click or tap, never only on hover (Apple guidance 5).
- **D:**
  - In `PresentationDetailView+PlanningSections.swift`, a "Before you start" section goes above `PresentationWhoWasThereSection` (line 158).
  - It shows only when there's something to list.
  - Each row has Finished, Mastered and Keep Practicing, all through `WorkLogService.log`.
- **E:**
  - A new "Before a lesson" chip in the `WorkFilterChip` row, backed by a new `TriageBucket` case.
  - It lists open work for children in presentations scheduled on the next 3 school days, today included (`SchoolCalendarService`).
  - The list is grouped under each lesson, soonest first, and the chip shows its count.
- Mac and iPad.

**#7 Move All Forward / Clear All to Inbox** (`Presentations/Planning/CalendarForwardShiftService.swift`, `WeekPlanSection.swift:182-220`, `+Prompts.swift`)
- **Investigate first.** Reproduce on the simulator what Danny saw left behind, and fix whatever is really skipped.
- **Known gap:** open `.scheduled` check-ins dated before today are skipped.
- **This reverses part of bug hunt 2026-10-12 #49** (see the comment at `CalendarForwardShiftService.swift:10`). That fix stopped moving weeks-old overdue items because the move used to happen with no question and no way back. The strip now asks first with counts and offers Undo, so Danny's choice stands. Move All Forward now:
  - moves overdue open check-ins to today;
  - moves today-and-later ones by one school day.
- Update that comment, the comment at line 125, and the `CalendarWorkShiftTests` that assert the old rule. The confirmation counts include the overdue checks.
- Presentations keep #49's rule: today or later, Show-filtered.
- Check-ins move whatever the Show menu is showing.
- **Collisions:** never put two check-ins for the same work on one day, and never move a check-in twice. Dedupe the moved set by check-in ID. When a check would land on a day that already has a check for that work, fold it into that check, the same guard as `applyCheckInMove`. Test both cases.
- **Linked copies:** every child's copy moves together. Use `WorkGrouping.group(containing:in:).siblings` so a sibling check-in outside the moved set still comes along.
- Lift the sibling-move core from `MCPNotebookTools+WorkCheckIns.swift` (`moveSiblingCheckIn`) into `WorkCheckInService` and have both call it. Edit only `+WorkCheckIns.swift`; don't touch `+WorkWrites.swift`, because Phase 3 edits it.
- **Clear All to Inbox** also clears open scheduled check-ins, with linked copies. `WorkCheckInService` has no unschedule function yet, so add one.
  - It **skips** a check-in that carries a note (its note is kept) and deletes a check-in with no note. Check-ins can carry notes (`setLegacyNoteText`), and deleting those would lose them.
  - The work returns to To Schedule, and each work's `dueAt` is reset the way `moveForwardOneDay` does it.
  - Clear All has no Undo today (`clearAllScheduledLessonsToInbox` saves at once). Give it a receipt and an Undo toast like Move All Forward's, covering presentations and check-ins.

**Ruled out**
- Dragging a child between groups (Danny: it would be confused with dragging the whole lesson).
- Idea B (a "check first" line on every card) and idea C (scheduling checks automatically).
- A pulsing sync dot.

## Apple guidance

Checked 2026-10-13 against Xcode 27.0 (27A266a), Swift 6.4, iOS/macOS 27.0 SDKs. Xcode 27.1 RC and 27.2 beta 2 exist; their notes change nothing here, so stay on 27.0.

1. **Day strip:**
   - Use `ScrollView(.horizontal)` + `LazyHStack.scrollTargetLayout()`, with `containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: s)` (spacing must equal the stack's).
   - `.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))`. Plain `.viewAligned` only limits a fling in a compact width.
   - `scrollPosition(id:)` / `ScrollPosition.scrollTo(id:)` work on off-screen targets.
   - Prefer `onScrollTargetVisibilityChange` over offsets (WWDC26 321).
   - There's no API to limit how far back you can scroll, so don't build those columns.
   - [scrollTargetBehavior](https://developer.apple.com/documentation/swiftui/view/scrolltargetbehavior(_:)), [ViewAligned](https://developer.apple.com/documentation/swiftui/viewalignedscrolltargetbehavior), [containerRelativeFrame](https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:count:span:spacing:alignment:)) (all 2026-10-08).
2. **Context menus:**
   - `contextMenu(menuItems:)`, with `Menu` for one level of submenu.
   - HIG: hide unavailable items, keep submenus to one level, and make sure every item also exists elsewhere in the UI. Here, Merge Groups… is the existing route.
   - Apple documents nothing on a long-press menu inside a draggable view on iPad. Check it on a device.
   - [contextMenu](https://developer.apple.com/documentation/swiftui/view/contextmenu(menuitems:)) (2026-10-08), [HIG context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus) (2026-08-06).
3. **Toolbar indicator:**
   - Keep the item present and change opacity. Apple is silent on opacity versus insertion, so this is inference; verify the toolbar doesn't shift.
   - `sharedBackgroundVisibility(.hidden)` gives the item its own group without glass. `ToolbarSpacer(.fixed)` separates groups.
   - HIG progress indicators: keep it in a consistent location and unlabeled, and don't rely on color or motion alone.
   - Honor `accessibilityReduceMotion`.
   - [toolbar placement](https://developer.apple.com/documentation/swiftui/toolbaritemplacement), [sharedBackgroundVisibility](https://developer.apple.com/documentation/swiftui/toolbarcontent/sharedbackgroundvisibility(_:)) (2026-10-08, thin), [HIG progress indicators](https://developer.apple.com/design/human-interface-guidelines/progress-indicators) (2026-08-06).
4. **Picker popover:** the existing popover with a plain `TextField` search is correct, because `.searchable` needs a navigation container. Use `Section` headers for Selected, Ready and Everyone else. [HIG popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) (2026-08-06).
5. **Chip details:**
   - Click or tap opens `.popover` (popovers are click/tap, not hover).
   - `.help` gives a tooltip on Mac only, 60–75 characters, without repeating the name.
   - [help](https://developer.apple.com/documentation/swiftui/view/help(_:)) (2026-10-08), [HIG offering help](https://developer.apple.com/design/human-interface-guidelines/offering-help) (2026-08-06).

## How agents work (every phase 1–6)

- Each agent works in its own worktree (`isolation: worktree`, which starts at the last-pushed main, `b184c579` at planning).
- It builds once before editing, through `Scripts/locked_xcodebuild.sh` with the three prefix-mapping settings (`Cosmic Daybook/CLAUDE.md` › Build & Run).
- Build only the "Cosmic Daybook" scheme for the iOS Simulator (`build-for-testing`). Phases 4, 5 and 6 also build it once for macOS (`-destination 'platform=macOS'`), because their Mac code sits in `#if os(macOS)` (the toolbar dot, right-click menus, `.help`).
- Run only the phase's `-only-testing:"Cosmic Daybook Tests/<Suite>"` suites, through `~/.claude/bin/build-turn`, on `$(~/.claude/bin/sim-lease)` with `-parallel-testing-enabled NO` (1 simulator).
- Run `~/.claude/bin/sim-lease --done` before replying.
- No full Mac build and no whole-suite run.
- Commit on the worktree's branch with the attribution line.
- Reply in at most 15 lines: files changed, build and test results with counts, anything decided differently from this plan.

## Phase 1: Student picker (#1)
- Who: `feature-phase` (Opus, high). It's a screen change on existing data, and the ready lookup must be right.
- Steps: as in Decisions › #1. Model logic (ordering, ready, level visibility) goes in `StudentPickerModel` as value-type rules, with new cases in `StudentPickerModelTests`. Add the ready helper in `ReadyGroups` with a test in `ReadyGroupsTests`.
- Cost: ~1–2% (Opus high, a screen on existing data, one file shared with five callers).
- Done when:
  - The iOS build is clean with zero new warnings.
  - `StudentPickerModelTests`, `ReadyGroupsTests` and `ReadyForNextEngineTests` pass.
  - A rendered iPad screenshot of the present sheet's picker shows no withdrawn children, no Lower tab, and Selected → Ready → A–Z.
- Hand off: no (agent).

## Phase 2: Three-day strip + Move All Forward / Clear All (#2, #7)
- Who: `feature-phase` (Opus, high). The strip and the shift service share files, and check-in moves touch linked work.
- Steps: as in Decisions › #2 and #7. Start #7 with a reproduction on the simulator (or a failing test in `CalendarWorkShiftTests`) for an overdue check-in and for a linked sibling. Add window-clamp cases to `WeekPlanDayWindowTests`.
- Cost: ~2–4% (a reproduction, two features, both platforms' layout, seven suites).
- Done when:
  - The iOS build is clean.
  - `WeekPlanDayWindowTests`, `WeekPlanLayoutTests`, `CalendarWorkShiftTests`, `WeekPlanCheckInMenuTests`, `WorkGroupingTests`, `MCPWorkCheckInToolsTests` and `MCPWorkCheckInGuardsTests` pass.
  - New tests cover: an overdue open check-in moves to today; a linked sibling's check-in moves with it; Clear All unschedules check-ins and resets `dueAt`; Undo restores all of it; the window never starts before the earliest scheduled day.
  - An iPad screenshot shows three columns starting today.
- Hand off: no (agent).

## Phase 3: Finished work status (#3)
- Who: `feature-phase` (Opus, high). Many switches, plus MCP, reports and backup paths. A miss shows up as a wrong word in a parent report or a mastery count, which is easy to overlook.
- Steps: as in Decisions › #3. Add tests:
  - `WorkLogServiceTests`: logging `.done` closes the work, with no mastery.
  - `WorkStatusMigrationTests`: a `"complete"` row with no outcome stays put.
  - `MCPWorkAndAttendanceToolsTests`: `update_work` accepts `finished` and `complete`.
  - The report phrase tests: they say "finished".
  - A `ChatContextAssembler` closed-work test.
- Cost: ~1–2%.
- Done when:
  - The iOS build is clean.
  - `WorkLogServiceTests`, `WorkStatusMigrationTests`, `ProgressStatusFix1010GTests`, `ReportGeneratorFix1010GTests`, `MCPWorkAndAttendanceToolsTests` and `MCPToolRegistryTests` pass.
  - A grep of `\.done`, `default:` near `WorkStatus` switches, and `closedRawValues` users finds no user-facing "Done" left for work status.
- Hand off: no (agent).

## Phase 4: Steady sync dot (#4)
- Who: `feature-phase-light` (Sonnet, medium). It's one component and three placements in an established pattern.
- Steps: as in Decisions › #4.
- Cost: <1% (Sonnet).
- Done when:
  - The iOS build is clean.
  - `SyncStatusTruthTests` and `SyncStatusSignalsTests` pass.
  - The macOS build is clean.
  - Two Mac toolbar screenshots, one with the dot shown and one hidden, have identical item positions. Force the state with a debug flag or a rendered `ImageRenderer` test, never a Debug app on the live notebook.
  - The same check on iPad.
- Hand off: no (agent).

## Phase 5: Move a child between groups (#5)
- Who: `feature-phase` (Opus, high). It writes to stored `CDLessonAssignment`s, so emptied groups and Undo must be right.
- Steps: as in Decisions › #5. Model tests go in `ReadyBacklogTests` (or a new `ReadyGroupMoveTests`): move to an existing group, move to a new group, empty source deleted, Undo.
- Cost: ~1–2%.
- Done when:
  - The iOS build is clean.
  - `ReadyBacklogTests`, `PresentationsBacklogTests` and the new move tests pass.
  - The macOS build is clean.
  - An iPad screenshot shows the chip's menu.
- Hand off: no (agent).

## Phase 6: Work to show first, A + D + E (#6)
- Runs after Phases 1–5 are combined on one branch, because it needs Finished (Phase 3) and edits files Phases 1 and 2 changed (`PresentationDetailView+PlanningSections.swift`, the strip).
- Who: `feature-phase` (Opus, high). Three surfaces read one new service.
- Steps: as in Decisions › #6. `WorkToShowFirst` gets its own test suite (same-sequence only; closed work excluded; a child not on the lesson excluded; one fetch per call). The E bucket gets `LessonsAndWorkTriageTests` cases (the 3-school-day window skips non-school days).
- Cost: ~2–3% (three surfaces, both platforms).
- Done when:
  - The iOS build is clean.
  - The new `WorkToShowFirstTests`, `LessonsAndWorkTriageTests`, `LessonsAndWorkPartitionTests`, `DayBalanceTests` and `BlockingOwnWorkTests` pass.
  - The macOS build is clean.
  - iPad screenshots show A's marked chip and popover, D's section, and E's chip.
- Hand off: no (agent).

## Phase 7: Combine, full builds, whole suite, review
- Who: main session (Opus 5.5).
- Steps:
  1. Merge the Phase 1–5 branches into this branch one at a time, building after any conflict. Run steps 2–5 for them and land them on main. If usage allows (check `get_usage`), launch Phase 6 on the result; otherwise wait for the Sat 18 Oct reset. When Phase 6 is done, repeat steps 2–5 for it.
  2. Run full builds: Cosmic Daybook for iOS Simulator and macOS, and Daybook Assistant (it compiles about 90 notebook files by path).
  3. Run the whole Cosmic Daybook suite once, then the Daybook Assistant suite.
  4. Run one Opus `Plan` review agent over the combined diff (correctness and data-safety only), then fix what it finds.
  5. Land on main using update-ref if the main checkout is on another branch (memory: merge-when-checkout-shared). Push.
- Cost: ~2–4%.
- Done when:
  - All three builds are clean with zero warnings.
  - Both whole suites pass, or any failures are shown to be pre-existing on main.
  - The review findings are fixed.
  - It's on main and pushed.
  - The Tide rows below are added.
- Tide rows to add (`Check on a device`):
  - Try the new picker on the Mac.
  - Scroll the three-day strip on the Mac and iPad.
  - Right-click and long-press a child chip to move them between groups (check that long-press doesn't start a drag on iPad).
  - Watch the sync dot during a sync.
  - Close work as Finished.
  - Use Move All Forward with an overdue check.
  - (`Release`) Roll out to the Mac, iPhone and iPad.

## Danny's steps (in Tide)

Phases 1–5 are on main as a361c2e4. Danny's rows in Tide:
- [Roll out to the Mac, iPhone and iPad](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Roll%20out%20the%20Lessons%20%26%20Work%20changes%20%28main%20a361c2e4%29%20to%20the%20Mac%2C%20iPhone%20and%20iPad)
- [Try the picker on the Mac](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20roll-out%2C%20try%20Add%20or%20Remove%20Children%20on%20the%20Mac%3A%20only%20your%20class%2C%20selected%20then%20ready%20then%20A%20to%20Z)
- [Scroll the three-day strip](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20roll-out%2C%20scroll%20the%20three-day%20Scheduled%20strip%20on%20the%20Mac%20and%20iPad)
- [Move a child between groups](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20roll-out%2C%20move%20a%20child%20between%20a%20lesson%27s%20groups%3A%20right-click%20on%20the%20Mac%2C%20long-press%20on%20the%20iPad)
- [Watch the sync dot](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20roll-out%2C%20watch%20the%20toolbar%20during%20a%20sync%20on%20the%20Mac%20and%20iPad%3A%20the%20dot%20fades%2C%20nothing%20moves)
- [Close work as Finished](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20roll-out%2C%20close%20a%20piece%20of%20work%20as%20Finished%20and%20check%20the%20work%20sheet%27s%20status%20row)
- [Move All Forward and Clear All](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20roll-out%2C%20try%20Move%20All%20Forward%20with%20an%20overdue%20check%2C%20then%20Clear%20All%20to%20Inbox%2C%20and%20Undo%20each)
- [Confirm two strip choices](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Confirm%20two%20Scheduled-strip%20choices%20made%20overnight%20in%20Cosmic%20Daybook)

The user manual's PDF (`Documentation/Generated/UserManual.pdf`) still lists the old statuses; the Markdown is updated.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board, if the plan lists one.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in `Areas/App Development/Cosmic Daybook/To do.md` (`add_action`), skipping ones already there. The repo keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets the status line and runs `docs-index`.
7. If the next phase is a fresh session, print its starter prompt.

## Open questions
None. Settled by default and open to change:
- Overdue check-ins move to today rather than tomorrow (from Danny's pick). This reverses part of the 10-12 bug hunt's #49, which is safe now that the move asks first and can be undone.
- Finished is the existing legacy Done status renamed and made pickable, not a new value. Old Done rows show as Finished.
- Other pickers keep their Age sort.
- Finished counts as practice evidence for mastery candidates.
