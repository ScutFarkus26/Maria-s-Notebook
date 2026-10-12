# Bug hunt 2026-10-12 fixes

> **Done 2026-10-12** (ba5c5e15). Not rolled out. Written 2026-10-12 from the read-only hunt in <../Reviews/Bug hunt 2026-10-12.md> (60 findings in the code last changed Sep 1–19).
> In short: fix every finding with nine fix agents in rolling waves of at most four, each owning its own files, then three reviews, fix what they find with fresh small agents, and land it on main without rolling out.

**Runs autonomously** (Danny, 2026-10-12): approved in advance to run every phase through landing on main without stopping. Decisions that come up are made by the main session from the project's rules, the 10-10 and 10-11 plans and sensible defaults, and listed under "Decided during the run" for Danny to read afterward. Anything that would lose data, touch the live store or need a CloudKit schema change is not done; it goes under Open questions.

## Goal

Every finding in the report is fixed, and the dead code it found is gone. When it's done:
- The launch cleanup never deletes a lesson or its track steps because of a restore, and no edit can make two lessons with one name in one sub-area.
- Claude's attendance marks keep what the assistants already marked, and every MCP tool does what its description says, through the service the app uses, and reports "nothing changed" honestly.
- One child's Re-present, a classmate's copy of linked work, or a check-in note on one copy stays that child's — on the Three-Year View, Today, Who Else Has This Work and the Notes tabs.
- Closing work writes one note; a pill logged for a later day doesn't finish the work in the future; reopening brings back the check-ins; Tomorrow on a Friday means Monday.
- Failed saves say so (carried-over plans, Bulk Add, the Overview's log, the work grid's delete).
- The rollover's landing date, the year plan's closed-day warning, the curriculum map's dates and columns are right.

Everything ends on main, built and tested for iOS, Mac and the Assistant. It is not rolled out. Device checks become Tide rows.

Finding numbers (#n) are the report's.

## Progress
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (m4 = the hunt, m5 = this plan, m6 = fix waves, m7 = review and land).
- [x] Phase 1: Wave 1 — L Lessons & cleanup ‖ W Work & projects ‖ Pr Presentations ‖ MR MCP reads (session: here, agents in worktrees) · est. ~3–4% weekly · started at 21%. As planned: L (12 new tests failed first; 202 pass) and MR (19 of 21 failed first; 214 pass) finished on their own. Differed: the 5-hour usage limit stopped every running agent at ~06:50 UTC for four hours; W and Pr had committed all their fixes, so the main session merged them and ran their tests (251 in 34 suites pass). W didn't fix #39 (Open questions).
- [x] Phase 2: Wave 2 — T Today & attendance ‖ S Students & year plan ‖ CM Curriculum map & albums ‖ MW MCP writes ‖ MC MCP curriculum & todos (session: here; each starts as a slot frees, at most four agents at once) · est. ~2–3% weekly. As planned: T (6 failed first; 119 pass), CM (7 of 9 failed first), MW (13 of 14 failed first; 207 pass). Differed: S and T were restarted after the usage limit; an app restart then stopped S and MC after they had committed their fixes, so the main session merged and tested them (805 tests in 118 suites pass with all nine merged). Weekly use went 21% → 49% across Phases 1–2 (other sessions also ran).
- [x] Phase 3: Combine, three reviews, fix round, full builds and suites, land on main, wrap up (session: here) · est. ~4–5% weekly · started at 49%. As planned: nine merges with no conflicts; three Opus reviews found 27 problems ((a) records 10, (b) MCP 12, (c) curriculum map 5; Today clean); three fresh agents fixed them (fix-a 148 tests, fix-b 459, fix-c 43, each with failing tests first) and the main session fixed the Ready list's delete and the album test's use of dead code. Full builds clean (notebook iOS, macOS, Release; Assistant) with no warnings; whole suites: notebook 3,551 tests in 590 suites, Assistant 309 in 47, all passing. Squashed to main ba5c5e15 and pushed; unsquashed history on `bug-hunt-2026-10-12-fixes-unsquashed`. Differed: another app restart interrupted the first whole-suite run (843 passed before it), rerun whole.

## Cost

About **9–12%** of the weekly all-models limit on Max (the hunt and planning cost ~5% before this, 16→21%). 79% is left (21% used at the start of Phase 1) until **Sun Oct 18, 4 PM EDT**. **Fits** with plenty of room.

Sizes come from the cost log, re-based on the 10-11 run (16–28% estimated, ~9% actual):
- **Fix agents:** feature-phase at high ~0.5% each, feature-phase-deep at xhigh ~1% each. Two deep + seven high = ~5.5%.
- **Reviews:** three Opus Plan reviewers ~2%.
- **Fix round:** fresh small agents or the main session ~1–2%. Resuming the agent that wrote the code reloads its whole transcript (the 10-10 lesson, ~19% there), so never.
- **Final phase:** combining, the full builds, both whole suites, Tide rows and wrap-up ~1–2%.

The 5-hour window was 17% used at writing; four agents at once is the cap for that reason.

## Decisions

**Settled from the code, the rules or by default (Danny is away; these are the run's calls):**
- **Lesson merges (#1):** both name merges skip any group in which two members share an `id` (the ID pass owns those, with its restore guard); a group is folded only when `DedupSyncState.tieStillSettling` is false for the whole group; `repointLessonReferences` returns at once when `old == new`. Nothing already deleted can be brought back by code; the fix stops future deletes.
- **One name per sub-area (#2):** the lesson editor's Save, the drag to another sub-area and MCP `update_lesson`'s move all call `LessonRepository.existingLesson(named:area:sequence:excluding:)` and refuse with Add Lesson's wording (`CreationError.duplicateName`). The merge itself is unchanged (it is the repair for twins already made); with the three paths closed, no new twins reach it.
- **Merge coverage (#3):** `repointLessonReferences` also rewrites `CDGoingOut.curriculumLinkIDs` and the keys of `CDStory.relatedLessonReasonsJSON`.
- **Failed saves (#4, #44, #55, #59):** the inserts or changes are undone (`ContextMutationTransaction` / `SaveCoordinator`), a plain message says it didn't save, and nothing is marked done. No new blanket save anywhere (10-10's rule: per-path saves only).
- **MCP attendance (#5, #6):** named marks first, then `CDAttendanceStore.markUnmarkedPresent` for the rest (passing the attendance roll), keeping today's refusal when the role can't mark attendance (`markUnmarkedPresent` returns nothing silently there); the reply names who kept an earlier mark. A top-level `student_name` / `status` given with `mark_all_present` or `students` is folded into the batch (it is what the guide meant), and a top-level `absence_reason` / `note` still refuses as today.
- **Mastery candidates (#7):** only `.mastered` (3) and legacy `.done` (2) count; MCP_SERVER.md follows.
- **Linked copies vs shared rows (#8, #15, #30, #38, #40, #46):** the 10-11 rule — a set of linked copies counts only for each copy's owner; a genuinely shared row (one row, several participants) counts for every participant. Use `WorkGrouping.visibleWork` / `owner(of:)` / `gatingWork` as the 10-11 fixes did; don't write a new rule.
  - **`completed_by` on a linked copy (#15):** refused, with the named child's own copy's id in the message so Claude can log that one with `status`. Shared rows keep per-child completion.
  - **Check-in notes (#40):** scoped like `WorkLogService.studentsLogged` (the owner for a linked copy). Forward only: existing notes keep their links (see Open questions).
  - **Today's due check-ins (#46):** each linked copy's row is titled by its owner ("Maya S · with Eli R, Ana T"), and level and "left" are judged by the owner. No folding: Gone quiet's `groupFollowUpWork` folds only group/flexible styles keyed by lesson alone, which would merge separate groups and due days (plan review).
- **Record batches (#9):** filings resolve one at a time; a plan or record claimed by an earlier filing in the same call is not reused, and written filings join the record index before the next resolves.
- **Monthly report over `record_parent_communication` (#10):** refused when that child and month already has a report, naming it and pointing to `draft_parent_report`; `month` parsed with `reportMonthArgument`.
- **`sent_date` (#11):** means sent; with any other status it's refused.
- **Work notes (#36):** one note per log: the dated work note `WorkLogService.addNote` writes. `close` passes an empty note to `WorkCompletionService.markCompleted`.
- **Log day (#37):** `WorkLogService.log` clamps a future day to today (past days stay valid; only the strip passes `on:`). And the strip doesn't offer status logging on a pill dated after today (Pr): it can still be rescheduled or opened, so nothing reads "Logged" while the pill stays put.
- **Reopen (#39):** reopening restores only the check-ins that the close itself skipped, dated after `completedAt` and today or later. A guide can Mark Skipped by hand, and nothing yet records which skips closing made, so W first finds a reliable marker (e.g. the skip's own `modifiedAt` equal to the closing save's stamp, or a marker the close writes into an existing field); if there is none without a schema change, W leaves #39 unfixed and says so, and it goes to Open questions. A test proves a guide-skipped check-in stays skipped.
- **Re-present (#45):** both paths call `MeetingLessonDecisions.flagForAnotherPresentation(_:studentID:context:)` per child (shared flag only when she had it alone, otherwise her own `CDLessonPresentation` row), the 10-09 #12 / 10-11 #26 rule. "Plan a second pass" therefore also resolves her follow-up row as Re-present.
- **Removing a child from a presentation (#47):** the existing "Also Remove From Work?" alert also lists her own single-child row that this presentation generated, offered for deletion through W's existing `WorkDeletionService` API (S, who owns the alert; plan review). That alert's binding clears `pendingWorkRetraction` that `onRemove` reads — the #58 shape — so it moves to `presenting:` too (G1).
- **Next school day (#48):** Reschedule › Tomorrow on the strip and the work card's menu use the next school day and name it ("Monday"), as `TodayBumpDay` does.
- **Move All Forward (#49):** asks first, naming the counts; respects the Show filter; moves only items dated today or later; sets `dueAt` to the earliest moved check-in. An Undo toast only if the shift can return a receipt cheaply (the agent's call, said in its reply).
- **Rollover landing (#52):** defaults to the later of the incoming year's start and the next school day after today; the picker can't go earlier.
- **Year N (#34):** counts school years from the configured school-year start, the app's unit everywhere else, not anniversaries of the start date.
- **Departure alert (#58):** the data travels with the alert (`presenting:`), and the binding never clears what the button reads (see Apple guidance).
- **Roster "next lesson" (#58 note):** reads her earliest scheduled presentation's lesson instead of `CDStudent.nextLessons`, which only a restore writes; the attribute stays in the model.
- **Curriculum map dates (#31):** engine only: the mastery record's `presentedAt` counts as a presentation date only when the cell has no presentation rows at all, dated or not. The checklist's write is left alone, because backup export writes `presentedAt ?? Date()` and a nil there would come back dated after a restore (fixing that needs a backup format change, out of scope).
- **Search snippet (#60):** `WorkStatus.displayName`, and `SearchIndexSnapshot.currentVersion` bumps so old snapshots rebuild once (a local cache, not synced data).
- **Dead code:** removed by the agent owning its file. Rollover's `appliedCarryOver` is used instead: the Done screen reports the carry-over (needed by #54's carry-over-only runs); whatever is still unread after that goes. `DeadlinesSectionView` goes although a comment says it was kept: nothing places it, and Danny asked for dead code removed. Stored Core Data attributes stay (no schema change).
- **Wording:** new messages go in the existing catalogs (`SettingsCopy.swift`, `AppErrorMessages.swift`), appended at the end of the relevant section, plain English, American spelling. MCP replies stay in their tool files.
- **Shared test file:** `MCPToolRegistryTests.swift` belongs to the main session; MR, MW and MC report what it needs.
- **Signatures CM keeps:** `CurriculumTimeline.make` and the `CurriculumMapEngine` entry points MC's `+CurriculumMap.swift` calls keep their signatures, so MC's branch builds on its own.
- **MCP_SERVER.md:** the main session edits it in Phase 3 from the lines agents report (#7, #17, #21 and any other tool whose behavior changed), so no two agents edit it.

**Ruled out:**
- A launch repair that unlinks classmates from check-in notes already written (#40): it rewrites synced records; listed under Open questions.
- Any repair that would bring back lessons or track steps an earlier merge deleted: there's no record of them on the device to restore from.
- A schema change. Nothing here needs one.
- Rolling out.

## File ownership

Every source file is owned by one agent. An agent edits only its own files. If a fix needs a change elsewhere, the agent says so in its reply, and the main session does it in Phase 3. Calling another owner's existing API is fine; changing it isn't.

The catalogs (`SettingsCopy.swift`, `AppErrorMessages.swift`) are shared and append-only. New tests go in **new test files** named `…Fix1012<agent>.swift`. Existing test files that need edits belong to the agent owning the code they test; anyone else asks in the reply.

**Assistant-compiled files:** `AppErrorMessages.swift`, `SaveCoordinator.swift`, `CDAttendanceStore.swift`, `TestStudentsFilter.swift`, `Students/Models/StudentEntity.swift`, `Work/Support/SchoolDayChecker*.swift` and the other by-path files in `project.pbxproj` are also built into the Daybook Assistant. An agent touching one also builds the `Daybook Assistant` scheme. No agent here should need to edit any of them except the catalog.

| Agent | Findings | Owns (under `Cosmic Daybook/` unless noted) |
|---|---|---|
| **L Lessons & cleanup** | #1–#4, #60; dead `EnergyPolicy.waitingTaskCount` | `Services/Migrations/`, `Repositories/LessonRepository.swift`, `Lessons/` except `Lessons/Checklist/` (CM's), `Services/Search/`, `Utils/Diagnostics/EnergyPolicy.swift` |
| **W Work & projects** | #36–#44, #48's work-card menu, #55; Work and Projects dead code | `Work/`, `Projects/`, `Models/CDUnifiedNotes+Helpers.swift`, `Students/Detail/StudentOverviewTab.swift` |
| **Pr Presentations** | #45, #37's future-pill logging, #48's strip pill, #49, #50, #32, #51's caption year and duplicate flagged note | `Presentations/` except `Presentations/FollowUp/PresentationWorkRetraction.swift` (S's), top-level `Planning/`, `Services/MCPServer/MCPNotebookTools+RepeatGuard.swift`, `CurriculumMap/ClassCurriculumMapView.swift` |
| **MR MCP reads & attendance** | #5–#14, #20's `draft_parent_report` lines | `Services/MCPServer/MCPNotebookTools+` `Attendance`, `MasteryCandidates`, `Schedule`, `Presentations`, `PresentationResolution`, `Communications`, `Families`, `PresentationHistory`, `Reads`, `Classroom`, `AppServices` (`.swift`) |
| **T Today & attendance** | #46, #51 except Pr's two items; Today dead code | `Today/`, `Attendance/` (notebook-only files) |
| **S Students & year plan** | #47, #52–#54, #56–#59, the test-student half of #51 for `WatchList+CoreData`, the roster's next lesson; rollover and Watching dead code | `Students/` except W's `StudentOverviewTab.swift`, `Presentations/FollowUp/PresentationWorkRetraction.swift`, `Settings/Classroom/CarriedOverPlanSweepViewModel.swift`, `SchoolYear/`, `Siri/` |
| **CM Curriculum map & albums** | #30, #31, #33, #34 (#35 is not a bug: G3) | `CurriculumMap/` except `ClassCurriculumMapView.swift` (Pr's), `Lessons/Checklist/` |
| **MW MCP writes** | #15–#22 except #20's lines in MR's and MC's files | `Services/MCPServer/MCPNotebookTools+` `WorkWrites`, `WorkCheckIns`, `FollowUps`, `PresentationEdits`, `ObservationBatch`, `YearPlanWrites`, `YearPlanClearing`, `Practice`, `MeetingScheduling` (`.swift`) |
| **MC MCP curriculum & todos** | #23–#29, #2's `update_lesson` move, #20's `adjust_supply` / `assign_job` lines | `Services/MCPServer/MCPNotebookTools+` `Todos`, `CurriculumMap`, `CurriculumWrites`, `CurriculumSupport`, `Supplies`, `Jobs`, `Library` (`.swift`) |

The folders above don't overlap; where a path sits inside another agent's folder, it is named as an exception on both rows. `docs/Technical notes/MCP_SERVER.md` belongs to the main session.

## Apple guidance

Checked 2026-10-12 against Xcode 27.0 (27A266a; iOS/macOS 27.0 SDKs, Swift 6.4). Deployment targets: iOS 18.0 / 27.0 by target, macOS 27.0. Xcode 27.1 RC and 27.2 beta 2 exist; their notes (2026-10-03) touch none of these APIs, so no update first. Doc pages modified Aug 6 – Oct 12, 2026.

- **G1. Alerts carrying data (agent S, #58).** `alert(_:isPresented:presenting:actions:message:)` and `confirmationDialog(…presenting:…)` (iOS 15 / macOS 12): "All actions in an alert dismiss the alert after the action runs", and the data "should not change after the presentation occurs". **When the `isPresented` binding is set to false relative to the action is not documented.** So never clear state in the binding's setter that the action reads: pass it as `presenting:` and read the closure's `(T)` parameter, and clear it explicitly in the actions (Apple's sample clears its detail in Cancel). HIG: destructive alerts get Cancel. ([alert](https://developer.apple.com/documentation/swiftui/view/alert(_:ispresented:presenting:actions:message:)), [confirmationDialog](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:presenting:actions:message:)), [HIG Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts))
- **G2. Confirming a discard (W #41, and any sheet holding typed text).** `dismissalConfirmationDialog(_:shouldPresent:actions:)` (+ `message:`), iOS 27 / macOS 15. iOS: only a user swipe or tap outside; **macOS: also a programmatic `dismiss`, so set `shouldPresent` false before calling `dismiss()` after a deliberate action** (log, open work). Cancel blocks the dismiss. `interactiveDismissDisabled` has no effect on programmatic dismissal; using both together isn't documented, so don't stack them. A Cancel button that closes the sheet should ask the same question itself. ([dismissalConfirmationDialog](https://developer.apple.com/documentation/swiftui/view/dismissalconfirmationdialog(_:shouldpresent:actions:)), [interactiveDismissDisabled](https://developer.apple.com/documentation/swiftui/view/interactivedismissdisabled(_:)))
- **G3. `@State` holding an object (agent CM, #35).** Built with Xcode 27, `@State` is the `State()` macro, which "instantiates its default value the first time SwiftUI instantiates the view" (back-ported to iOS 17 / macOS 14 for apps built with Xcode 27; WWDC26 "What's new in SwiftUI", TN3211). So `@State private var intelligence = AlbumIntelligence()` makes one instance per view, and **#35 is not a bug on this toolchain**: no code change. (The older State wrapper page still says otherwise; it predates the macro.) ([State()](https://developer.apple.com/documentation/swiftui/state()), [TN3211](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder))
- **G4. `SystemLanguageModel.availability`.** No documented cost; the model is `Observable` and Apple's samples read `availability` in `body`. Nothing to change here beyond #35.
- **G5. Dates.** Day steps use `Calendar.date(byAdding: .day, …)` (or the app's `AppCalendar` helpers), never `+ 86_400`, so a step across the November clock change lands on the next day (#14). The next school day comes from `SchoolCalendarService` / `TodayBumpDay` (#48).

## Agent brief (every fix agent)

- **Worktree:** your own (`isolation: worktree`, starting at the last-pushed main, 98bc0919). This plan and the report are not on main. Read them at these absolute paths:
  - `/Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/assistant-app-efficiency-4ef244/docs/Plans/Plan - Bug hunt 2026-10-12 fixes.md` (Decisions, File ownership, Apple guidance, your section)
  - `/Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/assistant-app-efficiency-4ef244/docs/Reviews/Bug hunt 2026-10-12.md` (your findings)
- **Rules:** read `Cosmic Daybook/CLAUDE.md` first. Edit only the files your row owns. Don't edit this plan or the board's milestones.
- **Tests:** for each data or logic fix, write a failing test first, in a new test file, and **commit the test before its fix**, so a reviewer can check it out and see it fail. View-only fixes need no test; name them in your reply as "not tested (view code)".
- **Build:** build only the `Cosmic Daybook` scheme, for `-destination "generic/platform=iOS Simulator"` (the plain "iPhone 17" simulator no longer exists), through `Scripts/locked_xcodebuild.sh` with the three prefix-mapping settings from CLAUDE.md, built once before editing. Build macOS too (`-destination "platform=macOS"`, build only) when you touch Mac-only code (`#if os(macOS)`, Mac windows, menus, the MCP server), and the `Daybook Assistant` scheme when you touch an Assistant-compiled file.
- **Test runs:**
  - Run only `-only-testing:` suites: the existing suites covering your files (find them by grep in `Cosmic Daybook Tests/`, and name them exactly in your reply) plus your new ones.
  - Always on your leased **iOS** simulator (`-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`, `-parallel-testing-enabled NO`), through `~/.claude/bin/build-turn`.
  - **Never run tests on macOS:** the Mac test host opens Danny's live notebook.
  - Run `~/.claude/bin/sim-lease --done` before replying.
- **Builds wait in the shared queue; never give up your turn.** Run long builds in the background or with the longest timeout (`BUILD_LOCK_WAIT=86400`).
- **Board:** load `ArtifactData` (ToolSearch `select:ArtifactData`). Your step is `tasks/<your slug>` on https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM. When you start, `get` it and `update` it to `status: active`, `startedAt` (from `date -u +%Y-%m-%dT%H:%M:%SZ`), `by: "<your agent name>"`, pinned with `if_version`. When your checks pass, `done`, `doneAt` and a one-line `note` of evidence (tests passed); if stuck, `blocked` with why. On a version conflict, `get` again and redo. Touch no other document. After each write, run `~/.claude/bin/board-touch https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM`.
- **Commits:** commit on your branch with clear messages ending in the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` line.
- **Reply in at most 15 lines:** what changed (files), build and test results with counts, which new tests failed on the old code, anything unresolved or decided differently from the plan, lines MCP_SERVER.md needs, cross-owner changes needed, and any device check worth doing. No narrative.

## Phase 1: Wave 1 — L ‖ W ‖ Pr ‖ MR

Four agents at once, each per the Agent brief, with its row of File ownership and its findings.

### L Lessons & cleanup (#1–#4, #60) — board `tasks/f-L`
- Who: `feature-phase-deep` (Opus 5.5, xhigh). Launch cleanup that deletes synced records.
- Steps: per Decisions. The merges skip same-id groups, check the settling guard per group, and `repointLessonReferences` returns on `old == new` (#1), in both `+LessonNameMerge` and `+TrackTitleMerge`; the twin check in the lesson editor's Save and the drag-move (#2; MC does the MCP move); Going Out links and story reasons repointed (#3); Bulk Add and Add Lesson undo unsaved inserts on a failed save (#4); search snippet `displayName` and the snapshot version bump (#60). Dead: `EnergyPolicy.waitingTaskCount` and its test use.
- Done when: iOS build clean; its suites pass (the `DataCleanupService` / dedup / lesson-merge / `LessonRepository` / search suites, named in the reply); new tests fail on the old code for #1 (a same-id pair under a settling restore keeps both and loses no track step; `old == new` repoints nothing; `tieStillSettling` is false without a container, so the test sets `recordNameOverride` / `recordChangedOverride`), #2 (the editor's apply and the drag refuse a twin), #3 and #4.

### W Work & projects (#36–#44, #48 card menu, #55) — board `tasks/f-W`
- Who: `feature-phase-deep` (Opus 5.5, xhigh). It changes `WorkLogService`, the one writer of work status.
- Steps: per Decisions. One note on a closing log (#36); the log day clamped to today (#37); Who Else Has This Work claims finished owners first, in `WorkPeers` and the Ready list's `LessonWorkPeersMenu` if it's W's (#38); reopen restores the check-ins the close skipped, per Decisions (#39); check-in note scope (#40); the Log Check sheet asks before discarding typed notes (#41, G2; set `shouldPresent` false before the Open-work and Log callbacks, since the week strip's parent dismisses the sheet and macOS asks on a programmatic dismiss); practice cards reload on session changes (#42); open projects stay listed under the current lens so Dormant shows (#43); the delete message counts check-in and completion notes, and the grid's delete says when it failed (#44); the card menu's Tomorrow is the next school day (#48); the Overview's log shows the failure (#55). Dead: `ProjectSidebarRow.isSelected` / `.lastSessionDate` and their computation; `WorkDeletionService.remove(studentID:from:persist:)` and `WorkCompletionService.records(for:studentID:in:)` with their test-only callers.
- Done when: iOS build clean; its suites pass, plus every suite in `Cosmic Daybook Tests/` that mentions `WorkLogService` or `markCompleted` (grep; the strip, MCP `update_work`, meetings and the checklist read what #36/#37 change); new tests fail on the old code for #36, #37, #38, #39 (including a guide-skipped check-in staying skipped), #40 and #43.

### Pr Presentations (#45, #48–#50, #32, #37 pill, #51 two items) — board `tasks/f-Pr`
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. Re-present per child in `CaptureFollowUpPersistence` and `recordRepeatIntent` (#45); no status logging on pills dated after today (#37); the strip pill's Tomorrow (#48); Move All Forward (#49); the strip refreshes on student saves and the test-students setting (#50); one shared "existing draft for these children" check used by the class map's Plan and the Plan Presentation sheet's Today and Presentations paths (#32; the Lessons path in L's `LessonsRootViewReordering.swift` switches to it in Phase 3; the sheet's "N selected" counts only children who can be planned); the caption year by school year and the duplicate flagged note (#51).
- Done when: iOS build clean; its suites pass (the engine's unchanged); new tests fail on the old code for #45 (both paths; group: the shared flag stays off **and** her own row is resolved Re-present; alone: the shared flag is set), #48, #49 and #32; the future pill offers no status log (view, say how checked).

### MR MCP reads & attendance (#5–#14) — board `tasks/f-MR`
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. Attendance batch (#5, #6; keep the refusal for a role that can't mark); mastery evidence (#7); `schedule_for_range` by owner (#8); record batches resolve in order (#9); monthly report refusal and month parsing (#10); `sent_date` (#11); enrolled families (#12); history ordinals from the index (#13); #14's smaller items; `draft_parent_report`'s two no-op replies mark nothing written (#20).
- Done when: iOS and macOS build clean (the MCP server is Mac-only); its suites pass (report what `MCPToolRegistryTests` needs; the main session edits it); new tests fail on the old code for #5 (including a refused role still refusing), #6, #7, #8, #9, #10, #11 and #12.

## Phase 2: Wave 2 — T ‖ S ‖ CM ‖ MW ‖ MC

Each starts as a Wave 1 slot frees, in this order, at most four agents at once.

### T Today & attendance (#46, #51) — board `tasks/f-T`
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. Due check-ins titled by owner, level and "left" by owner (#46); the departed name as `shortName`, "Mark checked in" settles every overdue check-in of the row and stamps `lastTouchedAt` (through `WorkLogService`'s seen-unchanged entry if that's what the strip uses), shared project row names loaded, test students out of Today's Watching and the Absence/Tardy reports, the Reminders warning shown when sync failed with nothing synced (#51). Dead: `deadlinesListSection` / `DeadlinesSectionView`; `TodayViewModel`'s `Equatable` if a build shows nothing needs it.
- Done when: iOS build clean; its suites pass; new tests fail on the old code for #46 and the test-student and "Mark checked in" items.

### S Students & year plan (#52–#54, #56–#59) — board `tasks/f-S`
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. Her own generated single-child row offered in the "Also Remove From Work?" alert, and that alert's data through `presenting:` (#47); rollover landing (#52); closed-day count from planned entries only (#53); carry-over-only rollovers can be reviewed and applied, and the Done screen reports carry-over (#54); a selected departed child can be unticked (#56); re-dating counts school days from the day after (#57); the departure alert carries its data (#58); the roster's next lesson from her next scheduled presentation; carried-over sweep through `SaveCoordinator` with a message on failure (#59); test students out of `WatchList+CoreData.enrolledIDs` (MCP `watching_only`). Dead: whatever of `RolloverSummary.carriedOverEntries` / `carriedOverByStudent` stays unread, `WatchListFetcher.fetch(for:in:)`.
- Done when: iOS build clean; its suites pass; new tests fail on the old code for #47, #52, #53, #54, #57, #59 and the Watching filter.

### CM Curriculum map & albums (#30, #31, #33, #34) — board `tasks/f-CM`
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. Work filed by owner in the engine, loader and cell sheet (#30); the mastery date used only when the cell has no presentation rows, and the undated-only wording (#31; the checklist's write stays); column ends from the anchor (#33); Year N by school year (#34). #35 needs no change (G3). Keep `CurriculumTimeline.make`'s and the engine's public signatures (MC calls them).
- Done when: iOS build clean; its suites pass (curriculum map, checklist); new tests fail on the old code for #30, #31, #33 and #34.

### MW MCP writes (#15–#22) — board `tasks/f-MW`
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. `completed_by` on a linked copy refused with her copy's id (#15); `complete_check_in_on` through `WorkCheckInService.markCompleted` (#16); `resolve_follow_up` through `TodoCompletionService.complete` / `WatchListActions.clear`'s logic, repeating todos allowed (#17); the roster add's repeat check (#18, calling `repeatConflicts` without editing `+RepeatGuard`); `assign_work`'s check-in day (#19); `markNothingWritten()` on its files' no-op paths (#20); the `practice_sessions` description (#21); #22's three.
- Done when: iOS and macOS build clean; its suites pass (report what `MCPToolRegistryTests` needs); new tests fail on the old code for #15, #16, #17, #18, #19 and #20.

### MC MCP curriculum & todos (#23–#29, #2 MCP move) — board `tasks/f-MC`
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. Someday and dates (#23); tag filter by name, tag names printed (#24); exact area first (#25); "Ungrouped" maps to "" (#26); album order (#27); unfiled lessons keep their place (#28); #29's three; `update_lesson`'s move refuses a twin (#2); `adjust_supply` / `assign_job` no-ops (#20).
- Done when: iOS and macOS build clean; its suites pass (report what `MCPToolRegistryTests` needs); new tests fail on the old code for #23, #24, #25, #26 and #2.

## Phase 3: Combine, review, fix round, full builds and suites, land, wrap up (main session)

1. Bring this branch up to date with main if it moved.
2. Merge the nine branches as they finish (the merge can start while later agents still run). Resolve catalog merges and any `project.pbxproj` lines. Make the cross-owner changes agents asked for, update `docs/Technical notes/MCP_SERVER.md` and `MCPToolRegistryTests.swift` from their reported lines, and switch the Lessons path's draft check (`LessonsRootViewReordering.swift`) to Pr's shared helper (#32).
3. Build `Cosmic Daybook` for iOS Simulator once, to catch merge breaks.
4. Three `Plan` reviewers (Opus 5.5), read-only, on the combined diff against main, each given this file and the report, each returning at most 15 real problems. Start each as soon as its agents are merged:
   - (a) records and writers: L, W, Pr, S.
   - (b) MCP: MR, MW, MC.
   - (c) Today, curriculum map, albums: T, CM.
5. **Fix round:** the main session fixes small problems itself. Larger ones go to a **fresh** agent (`feature-phase-light` on Sonnet, or `feature-phase` for anything touching records), given just the problem, the files and the Decisions it rests on, based on this branch's tip (`isolation: worktree`, then `git checkout -B <name> <tip>`). Never resume the agent that wrote the code.
6. **Full builds:** notebook iOS Simulator (build-for-testing) and macOS, a Release build of the notebook (CLAUDE.md: dead-code removals are confirmed on both platforms plus Release, for `#if !DEBUG` paths), and the Assistant iOS Simulator, with no new warnings.
7. **Whole suites once:** the notebook (one leased iPhone simulator, `-parallel-testing-enabled NO`) and the Assistant (its SE on iOS 26.5). Uninstall the app from the test simulator first (memory: a manual Release copy breaks restore tests). Then `sim-lease --done`.
8. Squash to main with one message listing the areas, and push. Keep the unsquashed history on the local branch `bug-hunt-2026-10-12-fixes-unsquashed`. (If the main checkout is on another branch, land with `update-ref` as memory "merge-when-checkout-shared" says.)
9. Tide: a row for every device check (`add_action` under Check on a device in `Areas/App Development/Cosmic Daybook/To do.md`), linked from Device checks below; update the roll-out row to name the new commit.
10. The report's status line becomes `> **All fixed** on main in <commit> (<date>). Not rolled out.`; this plan's `> **Done <date>** (<commit>).` Run `docs-index`. Save the memory note. Clean up the agent worktrees and the simulators. Then /close-out.
- Done when: all three builds are clean; both whole suites pass, with counts recorded here; main is pushed; the Tide rows are made; the report and plan status lines are set; `docs-index` reports the map current.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Tide holds the row; the repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out after the last phase. It sets the plan's status line and runs `docs-index` so the map follows.
7. Every phase here runs in this session, so there's no starter prompt between phases. If the session has to end early, the next session's prompt is: "Model: Opus 5.5, effort: high. In /Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/assistant-app-efficiency-4ef244, read docs/Plans/Plan - Bug hunt 2026-10-12 fixes.md and continue from the first unticked phase. Follow its Starting a phase and Ending a phase steps."

## Decided during the run

Danny was away; these were the run's calls (the Decisions above say how each is done):
- **Scope:** lines last changed 2026-09-01..09-19 at main 98bc0919, leaving out `Backup/`, `Models/`, `Sharing/`, `Services/Sync/` and `AppCore/Persistence/` (as 10-11 did) and the Daybook Assistant. `Services/Migrations/` (the launch cleanups) stayed in: it wasn't one of the excluded hunts, and it held the worst finding.
- **#35 (Albums availability probe) isn't fixed:** with Xcode 27 `@State` makes its object once (G3), so it isn't a bug on this toolchain.
- **#46 (Today's due check-ins)** takes the smaller fix (title, level and "left" by owner) rather than folding rows like Gone quiet, which would merge separate groups (plan review).
- **#31 (dates on the curriculum map)** is fixed in the engine only; the checklist keeps stamping the mark, because backups can't carry an empty date.
- **#37:** future pills keep reschedule and open but lose status logging, and the service clamps a future day to today.
- **#39 (reopen):** only check-ins the close itself skipped come back, and only if that can be told apart without a schema change.
- **#15 (`completed_by` on a linked copy)** is refused with her own copy's id, not quietly redirected.
- **#10 (a second monthly report over MCP)** is refused rather than merged into the existing one, so Claude can't overwrite text Danny edited.
- **#34 (Year N)** counts school years.
- **`DeadlinesSectionView`** is removed though a comment said it was kept on purpose.
- **#39 (reopen) isn't fixed:** the check-in record has no change date or spare field to tell a close's skip from the guide's own Mark Skipped, so it would need a schema change (Open questions).
- **#34 grace:** a child whose start date is within 30 days before a school-year start counts that school year as her first (review (c): two children started Aug 24 with the year starting Aug 25).
- **Shared project rows** count for every participant on the curriculum map, beside her own linked copies (review (c)).
- **MCP review (b):** a second monthly report is refused only for a new row or a changed month, type or child, so existing duplicates can still be edited; a monthly report needs a month; `completed_by` with a closing status, or naming the copy's own owner, is refused (use `status`); a lone `status: present` beside `mark_all_present` is ignored; a child named twice with different statuses is refused.
- **Removing a child from a presentation (#47, review (a)):** her own generated row is still offered, with its notes and check-ins counted in the line, and the edit, the deletes and the save undo together if the save fails.
- **Builds use `generic/platform=iOS Simulator`:** the shared "iPhone 17" simulator named in CLAUDE.md no longer exists; tests run on each checkout's leased simulator as before.

## Open questions

- **Reopening closed work doesn't bring back its skipped check-ins (#39).** Closing skips the later check-ins; nothing records which skips it made, so reopening can't tell them from ones you skipped by hand. Fixing it needs a new field (a schema change), so it wasn't done. Until then, re-add a check-in by hand after reopening.

- **Check-in notes already linked to classmates (#40).** The fix scopes new check-in notes to the copy's owner. Notes written before it keep their links, so they still show on classmates' Notes tabs. A launch repair could unlink them, but it rewrites synced records, so it wasn't done. Say if you want it.

## Device checks

In Tide under Cosmic Daybook's To do (Release and Check on a device). None tried yet; all wait for the roll-out.

- Roll out to the Mac, iPhone and iPad together. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Roll%20out%20main%20%28ba5c5e15%20or%20later%29%20to%20the%20Mac%2C%20iPhone%20and%20iPad%20together)
- A lesson can't be dragged or renamed into a twin. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20drag%20a%20lesson%20into%20a%20sub-area%20that%20already%20has%20one%20by%20that%20name%2C%20and%20rename%20a%20lesson%20into%20a%20twin%20in%20its%20editor%2C%20and%20check%20both%20refuse%20and%20change%20nothing)
- Claude's "everyone else is here" keeps an absence the Assistant marked. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20mark%20a%20child%20absent%20on%20the%20Assistant%2C%20then%20have%20Claude%20mark%20everyone%20else%20present%2C%20and%20check%20her%20absence%20stays)
- The Three-Year View's Year numbers and first columns. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20open%20the%20Three-Year%20View%20for%20a%20child%20who%20joined%20mid-year%20and%20one%20whose%20start%20date%20is%20the%20day%20before%20school%20began%2C%20and%20check%20their%20Year%20numbers%20and%20first%20columns%20look%20right)
- Today's due row for linked work, and the Reminders warning. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20give%20linked%20work%20with%20a%20check-in%20to%20three%20children%20and%20check%20Today%27s%20due%20row%20reads%20%22Maya%20S%20%C2%B7%20with%20%E2%80%A6%22%20and%20Mark%20checked%20in%20settles%20only%20hers)
- Move All Forward asks and undoes; Tomorrow on a Friday is Monday; later pills and the Log Check sheet. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20the%20Mac%20use%20Move%20All%20Forward%2C%20Undo%20it%2C%20and%20on%20a%20Friday%20pick%20Tomorrow%20on%20a%20strip%20pill%2C%20and%20check%20it%20asks%20first%2C%20undoes%2C%20and%20lands%20on%20Monday)
- Remove From Plans on a withdrawal, and her own row offered when she comes off a presentation. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20withdraw%20a%20test%20child%20who%20is%20on%20a%20planned%20lesson%2C%20pick%20Remove%20From%20Plans%2C%20and%20check%20she%20is%20off%20the%20lesson%20and%20her%20year%20plan%20is%20skipped)
