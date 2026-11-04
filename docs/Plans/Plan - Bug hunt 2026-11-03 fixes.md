# Bug hunt 2026-11-03 fixes

> **Done 2026-11-04** (1c9a0299). Written 2026-11-03 from the read-only hunt in <../Reviews/Bug hunt 2026-11-03.md> (60 findings in the oldest daily-use code). Squashed onto main as 1c9a0299; the unsquashed history is on local branch `bug-hunt-2026-11-03-fixes-unsquashed`. Not rolled out.
> In short: fix every finding with nine fix agents in rolling slots of at most three, each owning its own files and writing a failing test first, then a cold review of the combined work, a fix round with fresh small agents, both whole suites, and land it on main without rolling out.

The report has, for every finding, the scenario, the `file:line` places and a suggested fix. This plan says who fixes what, the decisions where the report left a choice, and how it lands; it doesn't repeat the findings. "#N" is finding N in the report. Paths are under `Cosmic Daybook/`.

**Runs autonomously** once Danny says go, as the October runs did: every phase through landing on main and pushing, without stopping. Decisions that come up are made by the main session from the project's rules, the earlier fix plans and the defaults below, and listed under "Decided during the run" for Danny to read afterward. Nothing touches the live store, needs a CloudKit schema change (none of the 60 does), or deletes synced records beyond what a finding's fix needs; anything of that kind goes under Open questions.

## Goal

Every finding is fixed, the "Smaller" items included. When it's done:
- No delete takes notes or mastery marks with it without asking: the presentation history's Delete, Checklist Unmark Presented and Remove Plan, Remove in Merge Groups, the work page's note, check-in and step trash buttons, Clear Completed and batch Delete in Todos, Readjust on the year plan all ask first, name what goes, and keep the notes on the children.
- The presentation sheet can mark the lesson just given as mastered for one child; Unlock Next Lesson unlocks only her and never makes a second draft; Save on an open work page never undoes a status set elsewhere.
- The Checklist's marks do what the presentation sheet's do: release her from the plan her year plan put her on, count as confirmation for Presentations, attach an undated presentation when she had none, and mark the latest history row.
- The year plan draws each lesson once, at the day it was really given or planned, numbers entries by the lesson's own order, and never plans a lesson she already had.
- Ready and Brewing, the Overview's Next Lessons, Insights, the Checklist's columns, the Lesson Journey, Today's reminders, the Todos sidebar and the work cards all redraw when what they show changes, midnight included.
- Children who left and hidden test students are out of every picker, count and list named in the report.
- Subtasks can be ticked and edited again and survive a repeat; Today's to-dos follow the real day on weekends; the Mac template editor's tag sheet closes.

Everything ends on main, built and tested for iOS, Mac and the Assistant, pushed. Not rolled out (the Hebrew birthdays roll-out row in Tide comes first). Device checks become Tide rows.

## Progress
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (if this session's organization can't reach it, use Daybook Bug Fixes, https://claude.ai/artifact/EqECVJ38VbFq3sWJ7gE7VR, as the 10-17 run did).
- [x] Phase 1: Nine fix agents in rolling slots of three — P ‖ C ‖ W1 first, then S1, S2, T, D, W2, L as slots free (session: fresh, Opus 5.5 high; agents in worktrees) · est. ~9–13% weekly · started 2026-11-03 at 97% (before the reset, at Danny's say-so) · done 2026-11-04, all nine merged into `claude/bug-hunt-phase-1-2bf78c` at 95e3e0a7. Cost not measurable: the weekly meter reset early during W1's run (97% → 26%), then rose 26 → 63% by the end, shared with other sessions (the Simplify round-two phases and Tide Phase 200 ran alongside). The agents used about 2.0M tokens. Each agent's tests passed on its own branch; nothing has been built or tested combined yet (Phase 2 step 2). Differences: see Decided during the run.
- [x] Phase 2: Combine, full builds and suites, cold review, fix round, docs, Tide rows, land on main (session: same as Phase 1) · est. ~3–5% weekly · started 2026-11-04 at 69% · done 2026-11-04 at 71%, about 2% (shared with other sessions). On main as 1c9a0299.

## Cost

About **12–18%** of the weekly all-models limit on Ultra. At writing the week is at **96%** (the hunt cost about 4%, 92→96), resetting **Sunday 2026-11-08 at 3 pm** (20:00 UTC). **Doesn't fit this week**; start Phase 1 after the reset, when the whole limit is free.

Sizes come from the last five Cosmic Daybook fix runs (10-10, 10-11, 10-12, 10-17, 11-02: deep fix agents 0.5–2% each, light ones 0.5–1%):
- **Fix agents:** five `feature-phase-deep` at xhigh (P, C, W1, S1, S2) ~1.5% each (7.5%); four `feature-phase` at high (T, D, W2, L) ~0.7% each (3%). Phase 1 ≈ 9–13% with build-queue reruns.
- **Review and fix round:** one cold Opus reviewer ~1.5%; fresh small fix agents ~1–2%. Never resume the agent that wrote the code (the 10-10 lesson: a resumed agent reloads its whole transcript for a 10-line fix).
- **Final:** combining, three builds, both whole suites, Tide rows, docs ~1–2%.

The 10-12 run hit the 5-hour limit with four Opus agents plus main, so **at most three agents at once**; before starting each new agent, read `get_usage` and hold the start while the 5-hour window is above 80%.

## Decisions

Settled by Danny (2026-11-03): the four choices that were under Open questions stand as written in D3 (an undated presentation behind a Checklist mark), D12 (Clear Completed limited to the shown list; weekend to-dos shown on the real day) and D1 (Readjust asks with a count, no Undo).

Settled here from the code, the earlier fix plans and the app's rules:

- **D1. Deletes that take notes or marks (#1, #2, #3, #35, #50, #51, #31).** One pattern everywhere, the cell's Clear's: a confirmation naming the record and the count of notes ("Delete this presentation? Its 3 notes stay on the children. Mastery marks stay."), then `ChecklistRosterRemoval.keepMasteryMarks` and the note-keeping in `ChecklistCellRecords` (notes come off the record and become the child's, filed under the lesson) before `PresentationRecordCleanup.prepareToDelete` and the delete. A plan with no notes and no marks deletes without asking (as today), except in Todos, where Clear Completed and batch Delete always ask with a count. The work page's check-in Delete goes through `WorkCheckInService.unschedule` (the note stays, the check-in is skipped); the note trash button asks ("Delete this note? It also comes off Maya S's Notes tab."); Delete Step asks. Readjust (#31) asks with a count ("Move 14 lessons in 3 sequences?") and nothing else changes.
- **D2. One readiness rule (#5).** Both engines read the same inputs: `BlockingAlgorithmEngine` counts a mastery mark (any marked history row for her and the earlier lesson) as confirmation, and `ReadyForNextEngine+PreviousLesson` honors the lesson's own "Requires Confirmation" and "Requires Practice" overrides the way the blocking engine does. The split noted at `ClassGridEngine+Checklist.swift:181-185` is closed by both sides changing, not by one importing the other (P owns one file, C the other; Phase 2 checks they agree with a shared test fixture).
- **D3. Checklist marks (#4, #8, #15).** After every cell and batch mark that records a presentation, run `YearPlanReleaseService.releaseRedundantPlans` as `LifecycleService` does. A Mastered, Practicing or Reviewing on a lesson with no presentation attaches an undated one (`.undated`, the Previously Presented path), never one dated today. Mastered marks the latest history row by date given, as the detail view does since 10-10 #64.
- **D4. Unlock Next Lesson (#19, #34).** The service reuses an existing plan only when its roster is exactly her; when the only plans covering her are group plans, it makes her own unblocked draft (`PresentationFactory.makeDraft` for her alone) and leaves the group plan untouched. It looks for an existing draft with a fresh fetch, not the caller's list; the work page reloads `relatedLessonAssignments` after an unlock. Unlock keeps saving at once (it is an action, not an edit of the page).
- **D5. The work page's Save (#33).** The page remembers whether the teacher changed the status pill or the title in this sitting; Save logs a status or writes a title only when she did. When the stored row changes underneath an untouched field, the page reloads that field (the existing `onPresentationDataChange` hook, widened to the header). A touched field keeps her edit and Save writes it.
- **D6. The recap's current lesson (#18).** The status picker shows on the current lesson's row too; `updateProficiencyState`'s `guideChangedState` is driven by the recap's per-child edits (the row already writes every row for the child and lesson through `updateSiblingLessonProficiencyState`). The group-wide Mastery row stays gone.
- **D7. The year plan draws each lesson once (#20, #21, #24).** A promoted entry is drawn at its presentation's scheduled or given date (the entry's `plannedDate` is updated when the presentation's day changes, in `YearPlanPromotionService`, which the drop handler already calls); an entry whose lesson has an unlinked presented assignment for her is drawn once, at the presentation's date, and promoted into it. `orderInSequence` becomes the lesson's own order in its track; a one-time repair on load renumbers existing entries from their lessons.
- **D8. Add Sequence (#23, #32).** The start lesson and the preview use `YearPlanSatisfaction`, so a lesson satisfied by a presentation or a mastery mark is skipped; Add Sequence and the timeline's Plan Lesson are hidden for a child who isn't enrolled, with the same plain message `WorkRepository.createWork` gives if reached.
- **D9. Working With, Cohort and Group Meeting (#36).** "Working With" shows only for genuinely shared rows (`WorkGrouping.wereMadeTogether` says a linked copy isn't one); Lesson Cohort and Group Meeting list enrolled, visible children only, through `TestStudentsFilter.filterVisible`; the project fallback counts only children on the same shared project row.
- **D10. Rosters (#12, #16, #17, #38, #41, #55).** Every list named in the report goes through `TestStudentsFilter.filterVisible` and the enrolled roster, and shows short names ("Maya S"). A sheet pre-filled with ids that aren't on the visible roster drops them when it opens (#41). Brewing judges readiness over enrolled visible children only, and "N of M ready" counts the same set (#12).
- **D11. Today's reminders (#48).** "Reminder" and "CalendarEvent" join `reloadInputEntities`, and `toggleReminder` acts on the state the row showed (a row drawn open completes; a row drawn done reopens), so a sync that landed between draw and tap can't flip the wrong way.
- **D12. Todos (#49, #50, #51, #53, #54, #56, #57, #58).** EditTodoForm gets the checklist section back (tick, rename, delete, add; the old `subtasksSection` from before 934e90c7 is the model) and `nextOccurrence` copies subtasks unticked. Clear Completed deletes only the completed to-dos in the current list or filter, after a confirmation with the count. The batch selection is cleared on any sidebar, filter, Tide-list or search change; batch Delete asks with a count. On Today, when the shown day is the coerced school day, the to-do section fetches by the real calendar day and includes anything dated between the two, so a Saturday to-do shows on Saturday and Sunday's aren't overdue on Sunday; the + button's new to-do defaults to the day Today shows. The Todos screen hooks `onCalendarDayChange` as Today does. Someday keeps the deadline, and a passed deadline puts the to-do into Today as overdue; Add Deadline opens the picker and writes nothing until a date is chosen. A to-do in the Today filter is grouped by the earlier of its deadline and its scheduled date.
- **D13. Stale screens (#6, #14, #16, #25, #30, #39, #40).** Each uses the app's existing signals: `onPresentationDataChangeWhenVisible` for the Overview and the Lesson Journey, a refetch of the roster in `refreshMatrix`, a hash of the engine's inputs (area, sequence, order, both rule overrides) plus watches on `LessonSequenceSettings` and `WorkParticipantEntity` for Ready and Brewing, a reload of `snapshots` after Mark Reviewed, lookups rebuilt when a card's lesson or child is missing, the day in the `.task` id for card ages.
- **D14. Lesson moves (#7).** When the edit form changes a lesson's area or sequence, it is placed last with `nextOrderInSequence` (Add Lesson's rule), and a track is made for a new sub-area the way a drag makes one.
- **D15. Saves (#13).** The Checklist and Ready backlog save through `SaveCoordinator`; a failed save shows the "Couldn't Save" alert and the grid redraws from the stored rows.
- **D16. Merge Groups and the split (#3, #11).** `remove(studentID:)` calls `ChecklistRosterRemoval.remove` (D1 for the confirmation); `PresentationSplitService` calls `PresentationRecordCleanup.moveStudents` for the ready children so notes about only them, and their year-plan links, follow them.

Ruled out: a schema change (none is needed; #7's track and #24's renumbering are data repairs on existing fields); re-hunting the areas the report calls clean; touching the live store; rolling out.

## Apple guidance

Nothing here depends on an API the codebase doesn't already use correctly elsewhere, so no SDK check was run (the week's budget is spent). Two items touch platform behavior and the fix copies a pattern already in the app: the Mac template tag sheet (#52) gets the NavigationStack-with-Done wrapper the other TagPicker presenters use; Add Lesson's fixed frame (#17) becomes a `minWidth`/`minHeight` on the Mac and an ordinary scrolling sheet on iPhone, as the other add sheets are. If an agent meets an API question, it says so in its reply and Phase 2's main session runs `sdk-verifier` for that one point.

## File ownership

Every source file is owned by one agent. An agent edits only its own files. If a fix needs a change elsewhere, the agent says so in its reply and leaves it; the main session does it in Phase 2. Calling another owner's existing API is fine; changing it isn't.

The catalogs (`Settings/SettingsCopy.swift`, `Utils/Diagnostics/AppErrorMessages.swift`) are shared and append-only. New tests go in **new test files** named `…Fix1103<agent>.swift` in `Cosmic Daybook Tests/`. Existing test files that need edits belong to the agent owning the code they test; anyone else asks in the reply.

**Assistant-compiled files** among these owners: `Students/Roster/TestStudentsFilter.swift`, `Students/Models/StudentEntity.swift`, `Attendance/Store/*`, `SaveCoordinator.swift`. D (#60) touches `Today/Views/Attendance/`, which the Assistant doesn't compile, but it calls the store; D builds the Assistant scheme if it edits a store file, which it shouldn't need to. No agent adds a file the Assistant compiles.

| Agent | Findings | Owns (under `Cosmic Daybook/`) |
|---|---|---|
| **P Presentations & plans** | #1, #3, #5's blocking-engine side, #6, #9, #11, #12, #17's Merge Groups chips and Presentation Info reload | `Presentations/` (all), `Models/LessonAssignmentEntity.swift`, `Models/PresentationFactory.swift` |
| **C The Checklist** | #2, #4, #5's ready-engine side, #8, #10, #13, #14, #15 | `Lessons/Checklist/` (all), `Planning/Services/ReadyForNextEngine.swift`, `Planning/Services/ReadyForNextEngine+PreviousLesson.swift`, `ClassGrid/Engine/` |
| **L The lesson page** | #7, #16, #17's Pages Import/Remove and Add Lesson size | `Lessons/` except `Checklist/`, `Lessons/Library/LessonSequenceOrdering.swift` included |
| **S1 Year plan & recap** | #18, #20, #21, #22, #23, #24, #31, #32's Add Sequence, the recap's logged-only failures (Smaller) | `Students/YearPlan/` (all), `Students/Presentations/` (all, `PresentationDetailViewModel*.swift` included), `Planning/PresentationDropHandling.swift` |
| **S2 Progress, Overview, Children & Insights** | #25, #26, #27, #28, #29, #30, #32's Plan Lesson, the first-name toasts (Smaller) | `Students/Detail/`, `Students/Progress/`, `Students/Insights/`, `ClassGrid/Children/`, `Services/Progression/` except `UnlockNextLessonService.swift` |
| **W1 The work page** | #19, #33, #34, #35, #36, #37, #45, #46 | `Work/Detail/`, `Work/CheckIns/`, `Work/Steps/`, `Services/Progression/UnlockNextLessonService.swift` |
| **W2 Agenda, practice & Quick New Work** | #38, #39, #40, #41, #42, #43, #44, #47, Work's Smaller items (sample-work numbering, Practiced Before, draft wording, id normalization), the dead code | `Work/` except `Detail/`, `CheckIns/`, `Steps/`; `AppCore/RootView/QuickNewWorkItemSheet*.swift` |
| **T Todos** | #49, #50, #51, #52, #55's pickers and template list, #56, #57, #58 | `Todos/` (all), `Components/TagManagementViews.swift` |
| **D Today** | #48, #53, #54, #55's Today part, #59, #60 | `Today/` (all) |

The rows don't overlap. `Services/Progression/UnlockNextLessonService.swift` is W1's and named as an exception on S2's row; `Planning/PresentationDropHandling.swift` is S1's. `docs/Technical notes/` and `MCPToolRegistryTests.swift` belong to the main session.

## Agent brief (every fix agent)

- **Worktree:** your own (`isolation: worktree`), cut from the branch that holds this plan and the report (`claude/oldest-strategic-bug-hunt-ce06d0`), not from main: the main session cuts it and names the path. Read this plan (Decisions, File ownership, your row) and the report's findings for your numbers at that path.
- **Rules:** read `Cosmic Daybook/CLAUDE.md` first. Edit only the files your row owns. Don't edit this plan. User-visible text is plain English (CLAUDE.md › Plain English) and American spelling; children are "Maya S".
- **Tests:** for each data or logic fix, write a failing test first, in a new test file, and **commit the test before its fix**, so a reviewer can check it out and see it fail. View-only fixes need no test; name them in your reply as "not tested (view code)". Name nested suites by their enclosing type in `-only-testing:` (otherwise 0 tests run).
- **Build:** the `Cosmic Daybook` scheme for `-destination "generic/platform=iOS Simulator"` through `Scripts/locked_xcodebuild.sh` with the three prefix-mapping settings from CLAUDE.md, built once before editing. Build macOS too (`-destination "platform=macOS"`, build only) when you touch Mac-only code (`#if os(macOS)`, Mac windows, menus, sheets): P, L, T and W1 do. Build the `Daybook Assistant` scheme if you touch an Assistant-compiled file.
- **Test runs:** only `-only-testing:` suites, the existing ones covering your files plus your new ones, on your leased **iOS** simulator (`-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`, `-parallel-testing-enabled NO`), through `~/.claude/bin/build-turn`. **Never run tests on macOS** (the Mac test host opens Danny's live notebook). Run `~/.claude/bin/sim-lease --done` before replying.
- **Builds wait in the shared queue; never give up your turn.** Run long builds in the background or with the longest timeout (`BUILD_LOCK_WAIT=86400`).
- **Board:** none for agents; the main session keeps it.
- **Commits:** commit as you go on your branch, with clear messages ending in the `Co-Authored-By` line for your model.
- **Reply in at most 15 lines:** every assigned #N on one line as fixed with its test's name, or "not testable" and why; files changed; build and test results with counts; which new tests failed on the old code; anything unresolved or decided differently from the plan; cross-owner changes needed; any device check worth doing. No narrative.

## Phase 1: Fix agents in rolling slots

At most three agents at once, each per the Agent brief, with its row of File ownership and its findings. Start order: P, C, W1; then S1, S2, T, D, W2, L, each as a slot frees (and the 5-hour window is under 80%). The main session merges each branch into a combine branch as it finishes.

### P Presentations & plans (#1, #3, #5a, #6, #9, #11, #12, #17 part)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). It changes what a delete keeps and what Presentations calls ready.
- Steps: per D1, D2, D10, D13, D16.
- Done when: iOS and Mac builds clean; the presentations, blocking engine and history suites pass; new tests fail on the old code for #1 (notes kept as the children's, marks kept, nothing deleted on Cancel), #3, #5a (a mastery mark counts as confirmation), #6 (a rule change redraws), #11 (notes and entries follow the split children), #12.

### C The Checklist (#2, #4, #5b, #8, #10, #13, #14, #15)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). The Checklist writes presentations and history for many children at once.
- Steps: per D1, D2, D3, D15.
- Done when: iOS build clean; the Checklist and Class Grid engine suites pass; new tests fail on the old code for #2 (a one-child given presentation keeps its notes as hers), #4 (`releaseRedundantPlans` runs after a cell mark and a batch mark), #5b (the lesson's confirmation override is honored), #8 (an undated presentation, never today's), #10 (the batch only adds), #15 (the latest row is marked).

### W1 The work page (#19, #33, #34, #35, #36, #37, #45, #46)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). It changes what Save writes.
- Steps: per D1, D4, D5, D9.
- Done when: iOS and Mac builds clean; the work detail, check-in and unlock suites pass; new tests fail on the old code for #19 (a group plan is left alone; she gets her own draft), #33 (a Mastered set elsewhere survives a Save with a note), #34 (one draft after two unlocks), #35's check-in delete keeping the note, #36 (linked copies show no Working With; departed children out of Cohort), #45 (start of day, next school day, no second check-in on a taken day), #46.

### S1 Year plan & recap (#18, #20, #21, #22, #23, #24, #31, #32a)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). It renumbers and redraws year-plan entries and changes the recap's reading of mastery.
- Steps: per D6, D7, D8, D1 (Readjust).
- Done when: iOS build clean; the year plan, pacing, promotion and recap suites pass; new tests fail on the old code for #18 (the current row's picker writes the child's rows), #20 (a moved presentation moves the entry), #21 (drawn once), #22 (a regive keeps Mastered and the earliest dates), #23 (a mastered lesson is skipped), #24 (order by the lesson's own position, old entries repaired).

### S2 Progress, Overview, Children & Insights (#25, #26, #27, #28, #29, #30, #32b)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). The progression services feed the Checklist, Today and the student page.
- Steps: per D8, D13; #26 and #27 use the Children card's `WorkVisibility` rule and the recap's note predicate.
- Done when: iOS build clean; the progress, Children view and insights suites pass; new tests fail on the old code for #26 (shared project work shows in the sheet and the timeline), #27 (presentation- and work-linked notes show), #28 (a year-plan entry reads Planned in both views; a mastery mark counts as activity), #29.

### T Todos (#49, #50, #51, #52, #55 part, #56, #57, #58)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per D12, D10.
- Done when: iOS and Mac builds clean; the todo suites pass; new tests fail on the old code for #49 (subtasks copied unticked), #50 (only the current list's completed to-dos), #51 (selection cleared on a filter change), #57 (a passed deadline shows under Today), #58.

### D Today (#48, #53, #54, #55 part, #59, #60)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per D11, D12, D10.
- Done when: iOS build clean; the Today suites pass; new tests fail on the old code for #48 (a reminder changed by the sync redraws; toggle follows the drawn state), #53 (a Saturday to-do shows on Saturday's Today), #54.

### W2 Agenda, practice & Quick New Work (#38–#44, #47, Smaller, dead code)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per D10, D13; the dead `LifecycleService` helpers and their test file go.
- Done when: iOS build clean; the agenda, practice and Quick New Work suites pass; new tests fail on the old code for #38, #41 (pre-filled hidden ids dropped), #43, #44 (the sheet groups by the grid's age), #47.

### L The lesson page (#7, #16, #17 part)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per D14, D13, and Apple guidance for the Add Lesson frame.
- Done when: iOS and Mac builds clean; the lesson suites pass; a new test fails on the old code for #7 (a moved lesson lands last and a track exists for the new sub-area).

## Phase 2: Combine, review, fix round, land (main session)

- **Who:** the main session (Opus 5.5, high), a cold `Plan` reviewer (Opus) on the combined diff, fresh small fix agents (`feature-phase-light` or the main session) for what the review finds, and a Sonnet `general-purpose` docs agent.
- **Steps:**
  1. Check the nine replies together cover #1–#60 and the Smaller items. Merge the nine branches into the combine branch by the ownership table; conflicts should be none, and any that appear name their agent. Then the cross-agent stitches: a shared test that runs the same readiness fixture through both engines (D2) and anything an agent asked for.
  2. Merge main in (whatever landed since 8c830a65). One notebook iOS build, one Mac build, one Assistant build, then the whole notebook suite and the whole Assistant suite once (one simulator each, `-parallel-testing-enabled NO`, `sim-lease --done` after). A failure names files; the files name the agent.
  3. The cold reviewer reads the combined diff against the report, not the agents' notes, and lists real problems (at most 15 lines). Past runs' cold reviews found the worst bugs in fixes whose tests passed; this step is not optional.
  4. Fresh small agents or the main session fix what holds up, with tests; rerun the suites the fixes touch, then both whole suites once more.
  5. Docs (Sonnet agent): the report's status line to "All fixed" with the commit and a "Where the findings stand" paragraph per agent; `docs/Technical notes/` where a behavior changed (Checklist marks and readiness, the year plan's drawing and numbering, Save on the work page, Todos' Clear Completed); `~/.claude/bin/docs-index .`.
  6. Tide rows (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`) for what only a device can show (Device checks below). The report keeps one plain line per row with its `tide://` link.
  7. Squash onto main and push; keep the unsquashed history on a local branch `bug-hunt-2026-11-03-fixes-unsquashed`. Don't run `Scripts/install_release.sh` or roll out.
- **Cost:** ~3–5%.
- **Done when:** all three builds are clean; both whole suites pass (record counts); the reviewer's findings are fixed or answered; the report says "All fixed" with the main commit; `docs-index --check` is clean; the Tide rows exist; main is pushed.
- **Hand off:** no.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%"). Phase 1 doesn't start before the Sunday 2026-11-08 reset.

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board with the `build-board` skill, then `~/.claude/bin/board-touch <url>`.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. The repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets this plan's status line (`> **Working on it.**` after Phase 1, `> **Done <date>** (<commit>).` after Phase 2, checked against main) and runs `docs-index`.
7. If the next phase is a fresh session, print its starter prompt: "Model: Opus 5.5 high" on the first line, then "In the Maria's Notebook folder, read `docs/Plans/Plan - Bug hunt 2026-11-03 fixes.md` and do Phase <N>. Follow its Starting a phase and Ending a phase steps."

## Decided during the run

**Phase 1 (2026-11-03 → 11-04).** Started at Danny's say-so before the reset. The Agent tool's own worktrees start from the last *pushed* main, so the main session cut each agent's worktree by hand: P, C, W1, S1 and S2 from 3933bd3f (the plan's commit); D, W2 and L from the combine branch as it stood, so D could call S1's new `YearPlanPromotionService.moveEntries` and W2 could match W1's check-in count. Every agent committed failing tests before its fixes; all nine reported their new fix tests failing on the old code (P's test commit needs one `nonisolated` removed to compile alone). The merges had no conflicts.

What the agents decided differently from the plan:
- **C, D2/#5b:** the ready engine honors only "Requires Confirmation", not "Requires Practice"; the 10-18 test `ReadyForNextEngineTests.openWorkCountsWithoutThePracticeSetting` says open work never holds a child back. **P** went past D2 the other way: with no presentation on record, a mastery mark also counts as practice done. Phase 2's shared readiness fixture must check that the two engines now agree.
- **P, D1:** the note-keeping on delete is P's own `Presentations/Workflow/PresentationDeletion.swift`, because C's helper is private. Two note-keeping paths now exist; the review should check that they behave the same. P also removed the blocking-work cache and `BlockingCacheBuilder.swift`.
- **W1, D4:** she stays on the group plan *and* gets her own unlocked draft. The project-group fallback in Working With is removed rather than narrowed. #46 counts overdue check-ins too, and W2 made the practice card follow the same rule.
- **S1, D7/#24:** the renumbering repair (`YearPlanEntryRepair`) runs on every load, not once. It writes only values that differ and doesn't save over another screen's unsaved edit. The review should weigh its cost and safety.
- **S2:** a year-plan entry alone doesn't put a sequence on the Children card; only a mastery mark does.
- **T, D12:** a Someday to-do joins Today when its deadline is today or earlier. Clear Completed is greyed out in Inbox, Today and Upcoming, which never list completed to-dos.
- **D, D12:** on a weekend, a new to-do defaults to the later of the shown day and the real day.
- **L, D14:** a drag makes no track, so the edit form copies Add Lesson's track code.
- **W2:** `WorkRepository.updateWorkStatus` and `markWorkCompleted` now throw (they have no callers).

Left for Phase 2 (cross-owner, step 1's stitches):
- `ReadyGroupsFixture.requirePractice` sets `requiresTeacherConfirmation = false`, which the engine now honors. `SequenceLadderTests.tiersOnTheFrontier` and `ReadyGroupsTests.oneLessonMatchesTheCards` fail until it is `true` (C, untried).
- `ReadyGroups+OneLesson`'s `marked` filter should admit any child given the previous lesson, and `ReadyGroups+Build.unconfirmed()` should skip lessons that don't require confirmation (`ProgressionRulesLookup`). Also check whether `ReadyQueueLoader` refreshes after lesson or sequence-setting edits (C).
- #54: `NewTodoForm` needs `init(initialTitle: String = "", initialScheduledDate: Date? = nil)`, and `TodayView+Sheets.swift`'s `newTodoSheet(defaultDate:)` should pass it (D). Until then, Today's + starts a to-do with no date.
- `Today/Views/Sections/TodayViewTodoSection.swift`'s `isShown` should use T's `TodoListFilter.isDue(_:by:)` for Someday to-dos (T).
- `ClassGridChildrenView.reloadEntityNames` should add "YearPlanEntry" and "WorkParticipantEntity", and update the pinned list in `LessonsWorkFix1017LW.swift` (S2).
- MCP `reschedule_presentation` should call `YearPlanPromotionService.moveEntries(promotedInto:to:)` (S1). `Services/MCPServer/MCPNotebookTools+Practice.swift:146` still reports the session's own check-in date (W1, #46).
- `Work/Detail/WorkDetailView+CompletionSection.swift` shows "Also presented to:" on draft and scheduled presentations (W2). `Documentation/Manuals/DeveloperManual.md:806` lists the removed `fetchAllWorkModels`.
- L: a lesson page closed mid-edit after Import… leaves an unused imported copy.
- Existing test files edited outside their owners' rows, each for its own finding: `WorkScreensTests+Fix1010C.swift` (W1), `StudentProgressTabLoadScopeTests.swift` (S2), `TodoListTests+Fix1010F.swift` (T), `PresentationRecordsTests+Fix1010I.swift` (W2, one test of the removed helpers), `BlockingOwnWorkTests` (P, rewritten against the engine).

Device checks the agents named, beyond the plan's list, for Phase 2 step 6 (rows only after landing, since none of this is on a device yet): Checklist Unmark/Remove Plan question and Couldn't Save alert; a new child's Checklist column after a sync; Merge Groups Remove of the last child; Brewing's holding-up marker and "N of M ready"; Presentation Info Re-present after Edit; check-in Delete question; Unlock on a group draft; dragging a presentation on the calendar moves its year-plan entry; Readjust's question; the student Overview updating after closing a work item; Insights Mark Reviewed; the template Edit Tags sheet closing on the Mac; a checklist tick updating "1/3"; card ages moving overnight on the Mac; printed Open Work by Age; Add Practice showing "Not rated"; Add Lesson's Add button on iPhone; Import… then Cancel on the Mac; a lesson moved to a new sub-area showing last.

**Phase 2 (2026-11-04).** Step 1's stitches went in as 8e68c71d: the fixture now requires confirmation; the ready list's picker admits any child given the previous lesson and a group card offers no one for confirming when that lesson doesn't require it (`ReadyQueueSnapshot.confirmationNotRequired`); `ReadyQueueLoader` also rebuilds on sequence-setting edits; Today's + starts the to-do on the shown day; a Someday to-do joins Today's section when due; the Children card reloads on year-plan and work-participant changes; MCP `reschedule_presentation` moves the promoted year-plan entries and `practice_sessions` reports the work's real next check-in; "Also planned for:" on a presentation not yet given; two stale rows out of the Developer Manual. The shared readiness test is `ReadinessAgreementFix1103Tests` (six records through both engines, plus the ready list). Not done: L's Import… leftover copy when the page closes mid-edit (left as it is; the copy is unused and harmless). Main's track retirement (Phases 1 and 2) was merged in at 48c153a7: the fixes' remaining track calls came out, and S2's #29 next-lesson fix was ported onto `SequenceStanding`. A cold review of the combined diff found eight points; six were fixed in 9052f6ed (the recap's current row waits for Record on a plan; a shared undated record releases only the child marked; Merge Groups' Remove keeps a row's text once; both note-keeping paths stamp and normalize alike; Readjust says when there's nothing to move; deleting a presentation detaches its work). Two were answered rather than changed: Unlock keeps the group plan (D4), and open work holds a child in Presentations but is only "check first" in the Checklist and Today, by design since 10-18. iOS, Mac and Assistant builds clean; the whole notebook suite (4,743 tests in 774 suites) and the Assistant suite (585 tests in 84 suites) pass, one simulator each.

Main had moved 14 commits, with Phases 1 and 2 of retiring the track entities. Nine files conflicted. Main's side won wherever it removed track code: the Checklist's and the presentation sheet's track calls are gone, L's track refresh after a lesson move (and its two tests) was dropped since nothing writes a track any more, and S2's #29 (the card's Next Lesson is the timeline's Next) was ported onto main's `SequenceStanding` cards as `StudentProgressTabViewModel.nextLessonByStanding`.

## Open questions
None. The four the plan was written with were settled by Danny on 2026-11-03 (see Decisions).

## Device checks
In Tide under Check on a device (added 2026-11-04):
- Mac: delete a given presentation from History; the notes are on the children's pages and the marks stand. ([row](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20the%20Mac%3A%20delete%20a%20given%20presentation%20from%20History%20and%20check%20the%20notes%20are%20on%20the%20children%27s%20pages%20and%20the%20marks%20stand>))
- iPad: record a lesson for two children and mark one of them Mastered from the recap's current row on the sheet. ([row](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20the%20iPad%3A%20record%20a%20lesson%20for%20two%20children%20and%20mark%20one%20Mastered%20from%20the%20recap%27s%20current%20row>))
- Mac: open Maya S's work in a window, mark it Mastered from the grid, add a note in the window and Save; it stays Mastered. ([row](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20the%20Mac%3A%20open%20a%20child%27s%20work%20in%20a%20window%2C%20mark%20it%20Mastered%20from%20the%20grid%2C%20add%20a%20note%20in%20the%20window%20and%20Save%2C%20and%20check%20it%20stays%20Mastered>))
- iPhone: tick a reminder in Apple Reminders; Today shows it done without a relaunch, and tapping it doesn't reopen it. ([row](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20my%20iPhone%3A%20tick%20a%20notebook%20reminder%20in%20Apple%20Reminders%20and%20check%20Today%20shows%20it%20done%20without%20a%20relaunch>))
- iPhone: Todos › Clear Completed asks with a count and removes only the shown list's. ([row](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20my%20iPhone%3A%20try%20Todos%20%E2%80%BA%20Clear%20Completed%20and%20check%20it%20asks%20with%20a%20count%20and%20clears%20only%20the%20list%20shown>))
- Mac: a Saturday to-do shows on Saturday's Today. ([row](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20the%20Mac%3A%20check%20a%20Saturday%20to-do%20shows%20on%20Saturday%27s%20Today%2C%20and%20that%20Today%27s%20%2B%20starts%20a%20to-do%20on%20the%20day%20shown>))
- The agents' extra checks, in one row with the list in its note ([row](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20try%20the%20rest%20of%20the%202026-11-03%20bug-hunt%20fixes%20on%20the%20Mac%20and%20iPhone%20%28list%20in%20the%20note%29>)).
- Under Review choices: whether open practice work should hold a child back in the Checklist and Today as it does in Presentations ([row](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Decide%20whether%20open%20practice%20work%20should%20hold%20a%20child%20back%20in%20the%20Checklist%20and%20Today%20the%20way%20it%20does%20in%20Presentations>)).
