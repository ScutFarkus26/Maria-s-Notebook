# ParentLocker bug check fixes

> **Done 2026-10-13** (main, see the parent plan's Phase 8). Written 2026-10-13 from <../Reviews/ParentLocker bug check 2026-10-13.md> (19 findings in the ParentLocker work on main 55117e19); Phase 8 of <Plan - ParentLocker attendance.md>.
> In short: three agents in their own worktrees fix the 19 findings, each with a test that fails first. Then one review, full builds and both whole suites, and it lands on main. Then the parent plan's Phase 9: Production schema, close-out, TestFlight.

**Runs autonomously** (Danny, 2026-10-12): "After this is pushed to main I'd like a final bug check on the latest changes. /plan-efficiently to fix the bugs. then push to main, close out, and send to testflight. do this all autonomously." No approval stop. The parent plan's "Never" list applies: no data loss, the live notebook is never opened by a schema-18 build, no passwords typed, and the notebook's build goes to no TestFlight group.

## Goal

Every finding in the report is fixed or answered. Close Arrival & Send always sends, even when a child arrives during Undo. A wrong saved password is never retried by itself. A past day saves under its own report. One ParentLocker child is never matched to two notebook children. The screen and the sync always agree on the method. The Assistant's Siri Close Arrival leaves the class waiting to send. On main, built, with both whole suites passing.

## Progress
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (milestone 15).
- [x] Phase 1: Fix agents S ‖ M ‖ U, each in its own worktree from main 55117e19 (session: here) · est. ~6–9% weekly · started at 62% · cost ~2% (62→64). All three merged cleanly (261d2ebe, 6a8aa90c, cbd8a69b), then joined up by the main session (52943638): the Assistant's `undoEnds(for:)` reads the sync's `undoEndsAt`; `makeReport` uses M's `childByStudentID`; Settings says "Sign in again" when the saved password was refused; PARENTLOCKER.md gained the `?date=` class list, the refused-password rule, "none" and the future-day rule.
  - **S** (e31ad473, tests first in 2a4250a3: 21 failed before): B1–B7, D3, C2, A1, C3, A3, A4, D1, D4. 109 notebook tests in 13 suites and 34 Assistant tests pass. Three earlier tests were changed for B4 and B5. It took 4.7 hours, mostly in the build queue.
  - **M** (a3fa128d): A2/C4 and A5. 100 + 9 tests pass. Differed: a ParentLocker child claimed twice goes to neither child; Match Names gained "Choose a child" and a "Not sent" section.
  - **U** (bedc8875): C1, C2's screen side and D2. 22 + 12 tests pass. Differed: the site field is written on a pause, on Return and when Settings closes, not on every keystroke; a new `stopsSend` lets Undo cancel a queued send on a phone that isn't signed in.
- [x] Phase 2: Combine, one review, full builds, whole suites, land on main (session: here) · est. ~2–3% weekly · started at 64% · cost ~1% (64→65). The review answered all 19 fixed (A4 partly: the id goes back exactly as given when the roster's equals the class's) and found 5 new bugs, none high. A fix agent fixed all 5 with tests (2090388a):
  - each child's class lists are read once a day, never alongside a run
  - the Assistant's Undo ends on sign-in, on a recorded send, or after 2 minutes
  - Reset Day stops a waiting Close Arrival & Send
  - Settings puts the shared method right when it opens
  - a refused password asks to sign in

  **The Assistant's whole suite then hung** in "Assistant share attacher", every time. A debugging agent found the cause (e52991b0): Siri's name suggestions opened the simulator's real iCloud store during tests, and with no iCloud account its filing hold stuck "on". It was latent since 50562549. This work only changed its timing: the simulator's store had moved to schema 18, so the pre-ParentLocker build refused that store and never hit the hold. Fixed by refusing that store in hosted test runs, with a test.

  Final results: five builds clean; notebook whole suite 3,694 tests in 609 suites pass; Assistant whole suite 331 in 50 pass three runs in a row.

## Cost

About **8–12%** of the weekly all-models limit (Max), sized from the cost log: Opus feature agents ran ~1–1.5% each tonight; the deep xhigh agents ran 2–4%; the final phase ~1–2%. At writing, 62% was used and 38% is left until **Sun Oct 18, 4 PM EDT**. **Fits.** Three agents at once is the cap the log recommends, and the 5-hour window is at 10%.

## Decisions

- **Three agents, split by files so none share one:**
  - **S** gets the engine's sending.
  - **M** gets matching.
  - **U** gets the screens.

  Each works in its own worktree (`isolation: worktree`). That starts at the last pushed main, which is 55117e19, this work's base. The main session merges the three branches. Why not one checkout: three agents building one tree would compile each other's half-edited files.
- **"After" no longer comes only from the automatic absences (B1).** A lasting per-day "arrival closed" mark, kept in `ParentLockerUnsent`, also counts; it's set by Close Arrival & Send and cleared only by its Undo. A started or recorded ParentLocker send counts too. So a child marked Late inside the Undo window, or during a retry, no longer cancels the send.
- **A refused password is remembered (B2).** The app stops signing in by itself until a new password is saved, keyed by the password item's modification date. The line says "ParentLocker didn't take your saved password. Sign in again."
- **"Not matched" is a stored value (A2/C4).** `parentLockerID = "none"`, which name matching never overrides. Two children holding one stored id are both ambiguous, and a pick in Match Names clears it from whoever held it. Why a value and not a new field: no schema change.
- **Future days are refused in the engine (C2),** so Send Now, Mark as Sent, MCP and Shortcuts all inherit it. The screen also hides those items on a future day.
- **A past day loads its own class list (A1):** `newattendance.php?date=YYYY-M-D`, checked live and read-only on 2026-10-13. A future date shows today's, so it's refused anyway.
- **Only today's jobs set `status` (C3).** Other days report through the toast and the MCP reply.
- **Record a send only when none is recorded yet (D3/B6).** A day sent on time stays "on time".
- **The method comes from the shared row everywhere (C1).** Settings writes a change to the method or the site at once, in a task that outlives the view, and again when the screen closes.

## Apple guidance

Not applicable beyond the parent plan's (checked 2026-10-12 against Xcode 27.0). The only Apple API these fixes touch is `beginBackgroundTask` / `endBackgroundTask` (B7), which is covered there, item 5.

## Phase 1: Fix agents S ‖ M ‖ U

Each agent: a failing test first where one can be written, then the fix; builds of its own scheme(s) only; `-only-testing:` its suites only, on a leased simulator, `-parallel-testing-enabled NO`, then `sim-lease --done`; commits on its own worktree branch; replies in at most 15 lines. No board writes, and no edits to the plan files.

- **S, engine sending.** `feature-phase-deep`, Opus xhigh: races, retries, privacy, background.
  - **Files:**
    - In `Cosmic Daybook/Attendance/ParentLocker/`: `ParentLockerSync*.swift`, `ParentLockerStore.swift` (except the `writeMatches` section, which is M's), `ParentLockerSyncSupport.swift`, `ParentLockerWatcher.swift`, `ParentLockerHTTP.swift`, `ParentLockerTransport.swift`, `ParentLockerWire.swift`, `ParentLockerKeychain.swift` and `ParentLockerSignInSheet.swift`.
    - `Daybook Assistant/FrontDesk/AssistantParentLocker.swift` and the fake in `AssistantParentLockerTests.swift`.
    - `ParentLockerSyncFakes.swift` (except the fake's `writeMatches`, which is M's), and its own tests.
  - **Findings:** B1–B7, D3, A1, A3, A4, D1, D4, and C2's and C3's engine side.
  - **Must keep:**
    - `closeArrivalSend(on:after:)` and `cancelCloseArrivalSend()` keep their signatures; B1's mark is cleared inside `cancelCloseArrivalSend`.
    - `sync.loadRosters(day:)` keeps its signature, and `sendAfterClose` keeps its own, so `AssistantAttendanceIntents.swift` needs no edit.
    - B4 fills `lastSeen` in `+Changes.swift` only; `changedElsewhere` (M's file) stays as is.
  - **Must add:**
    - A read-only "Undo ends at" on the sync, for D2.
    - B2 reads the password item's modification date in `ParentLockerKeychain`.
    - B1's new field in `ParentLockerUnsent` decodes when it's missing (data saved by 55117e19 builds) and counts in `isEmpty`.
    - A test that an MCP send for tomorrow is refused (C2).
  - **Builds:** notebook iOS and macOS, and the Assistant.
- **M, matching.** `feature-phase`, Opus high.
  - **Files:**
    - In `Cosmic Daybook/Attendance/ParentLocker/`: `ParentLockerPlanner.swift`, `ParentLockerPlanner+Matching.swift`, `ParentLockerPlanner+Store.swift`, `ParentLockerMatchView.swift` and `ParentLockerWire+Roster.swift`.
    - In `ParentLockerStatus.swift`, the unmatched line only.
    - The `writeMatches` section of `ParentLockerStore.swift`, and the fake's `writeMatches` in `ParentLockerSyncFakes.swift`.
    - Its own tests.
  - **Findings:** A2 / C4 and A5.
    - "None" is skipped quietly. It isn't in the "aren't matched yet" line and doesn't need attention in Match Names.
    - The two-children-one-id rule skips "none".
    - A pick clears that child from whoever held it, through `writeMatches`.
  - **Builds:** notebook iOS and macOS, and the Assistant.
- **U, screens.** `feature-phase`, Opus high.
  - **Files:**
    - In `Cosmic Daybook/Today/Views/Attendance/`: `AttendanceExpandedView.swift`, `+ParentLocker.swift`, `+Controls.swift`, `+ActionBars.swift` and `+FrontDesk.swift`.
    - In `Cosmic Daybook/Attendance/Email/`: `AttendanceEmail.swift` (and `+Prefs` if needed) and `AttendanceParentLockerSettings.swift`.
    - `Daybook Assistant/Attendance/AssistantArrivalBar.swift`, and its own tests.
  - **Findings:**
    - C1: no engine change needed; `refreshSignIn` and `refreshStatus` exist.
    - C2's screen side: hide the items on a future day. `recordFrontDeskSend` refuses a future day **for ParentLocker only**; email's Mark as Sent is unchanged.
    - D2: the Undo hides once S's "Undo ends at" has passed. A phone that isn't signed in keeps it until then.
  - **Builds:** notebook iOS and macOS, and the Assistant.
- **Every agent's reply** includes a table: finding → test name (or "no test" and why) → commit. The Phase 2 reviewer checks that every finding has a row.
- **Cost:** S ~4–6%, M ~1–1.5%, U ~1.5–2%.
- **Done when:** each agent reports its findings fixed, with tests that failed first, its builds clean with no new warnings, and its suites passing.
- **Hand off:** no.

## Phase 2: Combine, review, builds, suites, land

- **Who:** main session.
- **Steps:**
  1. Merge S, M and U into this branch. On a conflict, the files name the agent.
  2. One Opus `Plan` reviewer reads the fix diff against the report and says, for each finding, whether it's fixed. It looks for new bugs especially in B1, B2, A2 and C1. Fix what holds up, here or with a small agent.
  3. Full builds: notebook iOS, macOS and Release; the Assistant, Debug and Release.
  4. Whole suites: notebook, then the Assistant, on the leased simulator with one simulator.
  5. Squash onto main and push; the unsquashed history goes on `parentlocker-bug-check-fixes-unsquashed`. Mark the report's findings fixed with the commit.
- **Cost:** ~2–3%.
- **Done when:**
  - The review answers every finding as fixed.
  - All five builds are clean (the existing `AssistantSampleClass.swift:177` warning aside).
  - Both whole suites pass.
  - It is on main and pushed.
- **Hand off:** no. Then the parent plan's Phase 9.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed. Read the plan usage again and note the actual cost.
3. Add a row to `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board.
5. Make any "check on a device" item a row in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`).
6. Set this plan's status line (Done with main's commit after Phase 2) and run `docs-index`.

## Plan review (2026-10-13)

An Opus reviewer made 15 points, all taken: file ownership (`writeMatches` and its fake to M; `Keychain` to S; `AttendanceExpandedView.swift` and `AttendanceParentLockerSettings.swift` to U; A5 moved to M); the Undo-ends-at value shared by S and U; B1's field decoding and `isEmpty`; signatures S must keep; macOS builds for S and M; the finding → test table; email's Mark as Sent unchanged; a higher cost for S.

## Open questions

None.
