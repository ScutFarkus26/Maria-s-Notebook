# Groups page: replacing the Group Planner

Status checklist at the bottom. This file is the handoff: a fresh session reads it and continues from the first unticked box.

## Why

Danny asked (2026-10-02) whether the Group Planner (sidebar → Planning, `SmallSequencePlanner/`, ~1,240 lines) is needed. Verdict: not as built. Its question, "which children can I put together for a lesson?", is right. But Today's "Ready for a next lesson" and the Lessons & Work backlog already answer it through the shared `PresentationRecordIndex` + `ReadyForNextEngine`. The planner has a private engine that:

- ignores drafts and scheduled plans, so it re-suggests planned children, and tapping Create twice makes duplicate undated drafts;
- counts every child who hasn't had lesson 1 of a sequence as Ready;
- applies a practice gate that disagrees with Today ("needs practice, no work yet" is Almost there, Ready on Today);
- re-fetches four whole tables on the main thread per picker or level change, loads twice on an Area change, and misses work completion and confirmations (it uses a row-count change token);
- opens on "Area: Select…" and shows one sequence at a time, with initials instead of names.

Canvas with before/after: https://claude.ai/artifact/4h5CGGJXB4VLZbttvbHGUY (After boards: Groups page, Sequence ladder, iPhone, Today's front door).

## Decisions (Danny, 2026-10-02)

- Build the recommendation: replace the planner and delete its engine.
- Sidebar title **"Groups"**. The `NavigationItem` raw value stays `smallSequencePlanner` (persisted, pinned by `NavigationGroupTests`). Only the title and description change.
- Work in this order: plan → approve → build, with agents where they help and fresh sessions at the handoff points below.

Defaults taken (Danny can overturn them; none is hard to change later):

1. **Unconfirmed children** (had lesson L, neither confirmed nor mastered, successor not given or planned) appear only on cards that already have a group, as a "Confirm" line. They are never counted toward a group. Everywhere else they would flood the page.
2. **Catch-up** is derived, not stored: a child ready for N appears as a dashed "could join after N" ghost on the card for next(N), but only when that card exists.
3. **Sort:** ready count descending, then longest wait descending, then lesson name. Today's top five use the same order (today it is ready count, then name).
4. **A group means 2+ ready children.** Lessons with one ready child fold into one "N lessons with one child ready" row that expands in place.
5. **Wait** = school days since `ReadyForNextItem.basisDate` (the day the evidence lesson was given), shown orange past the Lesson Age overdue setting (default 8), the same threshold the backlog uses.
6. **Planning** goes through `SchedulePresentationSheet` + `PresentationPlanner.planDraft`, as Today's row does, with the ready children preselected. No alert. The draft is undated, as Today's always was; a planned child leaves the card, so it can't be planned twice (Danny kept this 2026-10-03; a day picker would be a separate change).
7. **Today's link** reads "See all in Groups ›" with no number, so it can never disagree with the page's count.

Ruled out: keeping the old page beside the new one; a feature flag; changing `ReadyForNextEngine.items` output (the MCP `students_ready` tool and Today's tests depend on it, so new tiers are layered on top instead).

## Architecture

All new logic is pure and tested; views stay thin. Paths are relative to `Cosmic Daybook/`, after the 2026-10-02 organization audit (main ae7982b0).

Key existing files: `Planning/Services/ReadyForNextEngine.swift`, `Presentations/Index/PresentationRecordIndex.swift`, `Presentations/Planning/{SchedulePresentationSheet,PresentationPlanner,BlockingAlgorithmEngine+SequenceOrder}.swift`, `Components/EnclosingNavigationStack.swift` (`PageNavigationStack`), `AppCore/RootView/{RootDetailContent,RootView+NavigationItem,RootAdaptiveTabs}.swift`. Tests that must stay green unchanged: `Cosmic Daybook Tests/Today/TodayReadyForNext{Cache,Background}Tests.swift`, `TodayViewModelReadyForNextTests.swift`, `Planning/ReadyForNextEngineTests.swift`, `Services/MCPServer/MCPReadyForNextToolTests.swift`. New suites go in `Cosmic Daybook Tests/Planning/` (builders, loader) and `Cosmic Daybook Tests/Groups/`.

- **`ReadyGroups`** (new, `Planning/Services/ReadyGroups.swift`, nonisolated, pure): input = `[ReadyForNextItem]`, `PresentationRecordIndex`, lessons, the next-lesson cache (`BlockingAlgorithmEngine.buildNextLessonCache`), roster level by student, and a school-day counter closure. Output = `[LessonGroup]`, each holding lesson ID, area, sequence, step "k of n", ready / almost (with reason) / catchUp / unconfirmed (with assignment ID for Confirm) / plannedWith (open plan on this lesson: date + student IDs), longest wait. Also exposes `groups` (2+ ready) and `singles`, area counts, and a level filter. Today's private `buildGroups()` in `Today/Views/Sections/TodayViewReadyForNextSection.swift` is replaced by it.
- **`SequenceLadder`** (new, `Planning/Services/SequenceLadder.swift`, pure): for one area + sequence, the ordered lessons and each enrolled child's frontier (highest step given, frontier = next step), with tier ready / practiceOpen / planned, plus "not started" count and "finished". It reads the same index; each child appears once, and catch-up ghosts come from `ReadyGroups`' rule.
- **`ReadyQueueLoader`** (new, `Planning/Services/ReadyQueueLoader.swift`, `@Observable @MainActor`): Today's rebuild orchestration, lifted out of `Today/ViewModels/TodayViewModel+ReadyForNext.swift`: generation counter, background `PresentationRecordIndex.readInBackground`, `readyForNextInputEntities` change gate, hidden-test-name check. Today keeps its public surface (`readyForNext`, `invalidateReadyForNext`, `refreshReadyForNextIfNeeded`, and the counters its tests read) by delegating. The Groups page owns its own loader, rebuilt only while visible (`onPresentationDataChangeWhenVisible` over `readyForNextInputEntities`).
- **Views** (new top-level feature folder `Groups/`, taking `SmallSequencePlanner/`'s place in `Cosmic Daybook/README.md`; `SequenceLadder`'s view lives there too): `GroupsView` (root, its own `PageNavigationStack`, toolbar level picker, area chips, adaptive grid: 3 columns on Mac/iPad regular, list on compact), `GroupCard`, `SinglesRow`, `SequenceLadderView` (pushed from a card's breadcrumb; ‹ › step through the area's sequences). Confirm calls `CDLessonAssignment.confirmStudent` (the index reads `confirmedStudentIDs`, verified 2026-10-02) through `SaveCoordinator`.
- **Removed:** `SmallSequencePlanner/` (5 files), `SmallSequencePlannerView.changeToken`, and its test block in `HiddenTabChangeCountsTests.swift`.

Names follow `student-short-name-format` ("Maya S"). The colors are the app's: success green = ready, warning = practice open, accent blue = planned, dashed = catch-up. Every reason line is real text (caption size or larger), never 9 pt, and tap targets are at least 44 pt on iOS.

## Phases and who does them

Each agent gets its own worktree, made by the orchestrator with `git worktree add` from this branch's current head, not `isolation: worktree`, which starts from the last pushed main (see the `agent-worktree-stale-base` memory). Each agent builds once before editing (cache replay), uses `Scripts/locked_xcodebuild.sh` with the worktree prefix-mapping flags, runs only its suites with `-only-testing:`, and commits with the Opus 5.5 trailer. The orchestrator merges each branch back, reading `git log main..branch`.

| Phase | Work | Who | Depends on |
|---|---|---|---|
| 1 | `ReadyGroups` + `SequenceLadder` pure builders + Swift Testing suites (fixtures in an in-memory store; cover: planned excluded, catch-up ghost only when the card exists, unconfirmed only on group cards, sort order, 2+ threshold, finished/not started, level filter, practice gate matching ReadyForNextEngine) | Agent A (opus) | — |
| 2 | `ReadyQueueLoader` extraction (Today delegates; Today's existing ReadyForNext tests stay green unchanged) + `GroupsView`/`GroupCard`/`SinglesRow`, nav title "Groups" + description, `RootDetailContent` wiring, Today switched to `ReadyGroups` + "See all in Groups ›" link (selects the nav item; on iPhone pushes in More) | Agent B (opus) | 1 |
| 3 | `SequenceLadderView` taking `(area, sequence)`, built on `SequenceLadder`; previews hoisted per the project rule | Agent C (sonnet is enough) | 1 (runs alongside 2: separate files; B leaves a `navigationDestination` that C's view fills) |
| 4 | Delete `SmallSequencePlanner/` + its tests; docs (`UserManual.md` Planning row, `Cosmic Daybook/README.md` folder map, `ARCHITECTURE.md`/`DeveloperManual.md` mention); `NavigationGroupTests` still pins the raw value | Orchestrator | 2, 3 |
| 5 | Verify: iOS + macOS builds; full iOS-sim suite once; iPad sim with Sample Class (Groups grid, ladder, plan sheet preselection, Confirm moves a child to Ready, Today link); iPhone sim More → Groups. Mac by eye is Danny's (a Debug Mac launch opens the live store) | Orchestrator | 4 |

## Handoff points (to save tokens)

- **H1, now:** this session wrote the plan on branch `claude/groups-view-analysis-9432b3` (worktree `.claude/worktrees/groups-view-analysis-9432b3`, based on main ae7982b0). A fresh session continues on that branch, in that worktree, from Phase 1: "Read Documentation/Implementation/GROUPS_PAGE_PLAN.md and run it." Agent worktrees branch from this branch's head, never from main. The orchestrator should stay light, letting agents do the reading and building and reading back only their summaries and `git log`.
- **H1 taken (2026-10-02):** the build session runs on branch `claude/groups-page-implementation-dab273` (worktree `.claude/worktrees/groups-page-implementation-dab273`), based on main 89474e75 with the plan commit cherry-picked; main's two commits since ae7982b0 moved no file this plan names. Agent worktrees branch from that branch's head.
- **H2, optional after Phase 3 merges:** if the orchestrating session is past about 60% of its context, start another fresh session for Phases 4–5 from this checklist.

## Phase 1 notes (for Phases 2–4)

- Public API: `ReadyQueueSnapshot` (items, index, order, roster; `filtered(levels:)`), `ReadyRoster`, `LessonSequenceOrder`, `ReadyGroups.build(from:schoolDaysSince:)` (`lessons`, `groups`, `singles`, `holding`, `areaCounts`, `inArea(_:)`, `group(for:)`), `LessonGroup` (`ready`/`almost` members with `waitSchoolDays` and `reason`, `catchUp`, `unconfirmed` with `assignmentID`, `plannedWith`, `longestWait`, `readyStudentUUIDs`), `SequenceLadder.build(area:sequence:from:schoolDaysSince:)`.
- `PresentationRecordIndex` gained `openPlansByLesson` (two more columns: `scheduledFor`, `plannedDate`); its earlier answers are unchanged.
- `holding` = lessons with no ready child, only practice-held ones: Today may show them, the Groups page leaves them out.
- School-day counter: `{ LessonAgeHelper.schoolDaysSinceCreation(createdAt: $0, using: context) }`; the orange color stays in the view (`StudentAgePalette.status(forDays:)`). Areas/sequences come back alphabetical; views apply `FilterOrderStore.loadAreaOrder` / `loadSequenceOrder`.
- Confirm: `context.object(with: assignmentID) as? CDLessonAssignment` → `confirmStudent(uuid)` → save through `SaveCoordinator`.
- **Phase 4:** `ReadinessTier` (used by `ReadyForNextItem`) lives in `SmallSequencePlanner/SmallSequencePlannerTypes.swift`; move it out before deleting that folder.

## Review notes (2026-10-03, after Phase 4)

A read-only review of the merged diff found the plan's rules intact and fixed or noted:
- Ladder Confirm keyed its "Confirmed" label by assignment alone, so classmates given the lesson together all read Confirmed: now keyed by assignment + child.
- The ladder never refreshed while open (the page under it stops refreshing once covered): `SequenceLadderHost` reads the loader itself and refreshes while on top.
- The Groups page rebuilt on every keystroke-level edit to its inputs: refreshes now wait 300 ms after the last change (`ReadyQueueRefresh`).
- Decision 6's "no undated draft" is not what happens: `PresentationPlanner.planDraft` makes an undated draft, as Today's row always did; the guard against duplicates is that a planned child leaves the queue. Comment corrected; Danny kept undated drafts (2026-10-03).
- Not changed: Today's loader now keeps the whole snapshot (record index included) between rebuilds, where Today used to drop the index after each build. Low cost; a later efficiency pass could have Today keep only the built `ReadyGroups`.

## Open questions

None blocking. Danny can overturn defaults 1–7 at any time.

## Status

- [x] Analysis + canvas (2026-10-02)
- [x] Plan written
- [x] Phase 1: ReadyGroups + SequenceLadder + tests (bd8c8254, ccb441b2; 54 tests green on the iOS sim)
- [x] Phase 2: ReadyQueueLoader + Groups page + Today link + nav title (8d5799c1..78b29856; 79 tests green)
- [x] Phase 3: Sequence ladder view (53247700)
- [x] Phase 4: old planner deleted, docs updated (d5c4a492)
- [ ] Phase 5: builds, full suite, sim checks
- [ ] Squash to main (close-out), memory updated
