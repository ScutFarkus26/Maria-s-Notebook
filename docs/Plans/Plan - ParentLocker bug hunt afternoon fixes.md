# ParentLocker bug hunt afternoon fixes

> **Working on it.** Written 2026-10-13 from <../Reviews/ParentLocker bug hunt 2026-10-13 afternoon.md> (23 findings in the ParentLocker work on main 3ba3c2f8). Danny: "Fix all 23."
> In short: the main session adds the shared hooks as placeholders, then four agents in their own worktrees fix the 23 findings, each with a test that fails first. Then a review, full builds and both whole suites, and it lands on main. TestFlight stays on hold until Danny says go.

## Goal

Every finding in the afternoon report is fixed or answered:
- Settings never switches the class back to email on a device that's behind.
- Siri's undo of a close also stops ParentLocker.
- The guide's backstop survives a new day.
- No mark is lost or overwritten by a device that's behind or was offline.
- The office's notes are kept.
- The screens say what to do and offer it.

On main, built, both whole suites passing.

## Progress
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (milestone 16).
- [x] Phase 0: Shared hooks as placeholders, so the agents never wait on each other (session: here) · est. ~0.5% weekly · started at 67% · `awaitsSignIn`, a working `cancelOwedCloseArrivalSend(on:in:)` and an empty `unmarkedNames(on:)`; notebook iOS and the Assistant build
- [ ] Phase 1: Agents E ‖ H ‖ A, then N as soon as one finishes; each in its own worktree with Phase 0 merged (session: here) · est. ~5–7% weekly · started at 67%
- [x] Phase 1 (recorded with Phase 2): E 923ea6d2, H 78f0002a, A d43f4776, N f9657110, all merged with no conflicts and joined up (f538bd94: the sign-in sheet's dismissal hooks, and the sheet shows its fields whenever a sign-in is needed). Each agent's table covered its findings; most tests were seen failing first (E: all against the placeholders; H: 8 of 10; A: the L5 and H2-dialog tests; N: tests that won't compile on the old code).
- [ ] Phase 2: Combine, check every test fails on the old code, review, five builds, whole suites (the Assistant's three times), land on main (session: here) · est. ~1–2% weekly. **Review (Opus):** 18 of 23 fixed. Three only partly: H2 (Siri's Undo when signed in and the send failed), H4 (a race when the Mac reads before the phone's send lands, and early marks not saved) and M8 (the "not expected" mark is per device). It also found join gaps: Siri and the Shortcut on a not-expected day, the Assistant line repeating beside Send, two sign-in sheets not calling `signInDismissed`, the Shortcut's reply, and an edit over the launch seed. And 6 new bugs: the Assistant reopening sign-in after every mark, the M9 flag sticking, "Not matched" counted as unmarked, and M5's fallback lost on a new day. A deep fix agent fixed all of them (7168d95a, merged 268e3914), each with a test that failed on the old code first (22 notebook and 31 Assistant tests). M8's mark is a `CDAttendanceEmailSend` row with `channelRaw = "notExpected"` that every reader but the reminder and the status line leaves out, so there is no schema change. Not unit-tested: 8c (the Settings and Classroom sheets call `signInDismissed`, view wiring).

## Cost

About **6–9%** of the weekly all-models limit (Max). The morning's equivalent round cost ~3% against an 8–12% estimate, but this one has a fourth, xhigh agent. 65% used at writing, 35% left until **Sun Oct 18, 4 PM EDT**. **Fits.** **Stop and report if weekly use reaches 75%.** At most three Opus agents run at once.

## Decisions

- **Four agents, split by files, none sharing one.** Each runs in its own worktree. The worktree starts at this branch's head or at pushed main; either way the agent first merges `claude/parentlocker-attendance-integration-36de87` (a local branch, which the worktrees share) to pick up Phase 0. The main session merges the four.
- **Phase 0 hooks.** The main session commits these as placeholders that compile; the owners fill them in.
  - **E fills:** `ParentLockerSync.unmarkedNames(on:) -> [String]`, from the store, which the screens and the Shortcut call before sending (M4).
  - **E fills:** an observed `awaitsSignIn: Bool`, true while a whole-class send waits for a sign-in (L2, L6).
  - **E fills:** a static `ParentLockerSync.cancelOwedCloseArrivalSend(on:in:)` that clears the send saved for launch and "arrival closed here", for Siri's Undo with no sync running (H2).
- **No `noteMatched`:** `noteChanges(_:imported:on:)` is already internal. Match Names calls `sync.noteChanges([picked, displaced], imported: false, on: sync.today)` (M7).
- **M4:**
  - `sendNow` and `send(day:preview:)` (Shortcuts, MCP) send the marked children. They record the day only when nobody is unmarked.
  - The screens ask first and name the unmarked. Shortcuts uses `requestConfirmation` with the count.
  - MCP's reply lists the unmarked; E updates `MCPSendAttendanceToolTests`.
- **L6:** a send waiting for sign-in is for **today only**, and it's cleared when the sheet closes without a sign-in. For a past day, the screen just opens the sheet.
- **H1, the method and site on one shared row:**
  - **Settings reads the row.** The method picker and site field show the shared row, not the preference.
  - **One field at a time.** An edit changes only that field on the current row (`AttendanceEmailLog.settings(in:)`), then copies it to the preference; a deadline edit on a lagging device keeps the method.
  - **Only the person's own actions write:** the picker's setter, the site's `onSubmit`, and closing with an unsaved edit. Never `.task(id:)`, so a sync arriving while Settings is open is never treated as an edit.
  - **Repair is narrow.** It writes only a pending write this device recorded: the field values plus the row's `modifiedAt` when the write was skipped (first download). It writes only if the row hasn't changed since.
  - **The launch seed can't win.** `saveSettingsIfMissing` seeds with `modifiedAt = .distantPast`, so a new device's defaults never outrank a ParentLocker row arriving later.
  - **The Sample Class never writes** the preference or the pending flag.
  - **`+FrontDesk` reads the deadline from the row** (N does this one line).
- **M6:** the automatic absence sends `comment: nil`, so the office's or a parent's words are never wiped; the app's own notes are still cleared. This reverses the plan's "empty Notes box" for that case.
- **M8:** when every class is "not expected", E saves a "not expected on <day>" mark, which the reminder's scheduling reads to withdraw that day's reminder. The line says "ParentLocker isn't expecting attendance today", and nothing is recorded as sent.
- **Test fakes and the project file:** only E edits `ParentLockerSyncFakes.swift` and `project.pbxproj`. The other agents read the fakes and put their own helpers in their own new test files.

## Phase 0: Shared hooks (main session)
- **Steps:** add the three placeholders to `ParentLockerSync*.swift`, build notebook iOS and the Assistant, and commit.
- **Done when:** both build, and the commit is on this branch.

## Phase 1: Agents
Each agent:
- Merges this branch first (for Phase 0).
- Writes a failing test first.
- Builds notebook iOS and macOS and the Assistant.
- Runs `-only-testing:` its suites on a leased simulator with `-parallel-testing-enabled NO`, then `sim-lease --done`.
- Commits on its worktree branch; no doc or board edits.
- Replies with a table: finding → test → commit.

- **E, engine.** `feature-phase-deep`, Opus xhigh.
  - **Files:** in `Cosmic Daybook/Attendance/ParentLocker/`, `ParentLockerSync*.swift`, `ParentLockerWatcher.swift`, `ParentLockerStatus.swift`, `ParentLockerStore.swift`, `ParentLockerSyncSupport.swift`, `ParentLockerSignIn.swift` and `ParentLockerPlanner*.swift`; also `Attendance/Email/FrontDeskEmailReminder.swift`, `ParentLockerSyncFakes.swift`, `MCPSendAttendanceToolTests.swift`, `project.pbxproj` and the engine tests.
  - **Findings:**
    - H3: roll first; `.NSCalendarDayChanged` rolls and refreshes the line; a test that spans a day, the Mac's line included.
    - H4: taking a backstop never clears imported or local work; changes from before "after" are kept unscheduled and sent through lastSeen once the day is "after". A test at 8:44:50.
    - H5: a pending whole-class retry becomes an owed send released by the catch-up on return or launch; retries get lastSeen. A test of returning before the import.
    - M5, M6, M8 (with the reminder), M9 (an observed flag, no automatic sign-in while it's set), L8 and L9.
    - Phase 0's three hooks.
    - The engine side of M2 (the line's words and the reminder's "due" text), M3 (problems on an idle run), M4 and L6.
- **H, the shared method and site (H1).** `feature-phase-deep`, Opus xhigh (the riskiest finding, caused by the morning's C1 fix).
  - **Files:** in `Cosmic Daybook/Attendance/Email/`, `AttendanceEmail.swift`, `AttendanceEmail+Prefs.swift`, `AttendanceEmailLog.swift` and `AttendanceParentLockerSettings.swift`; also `Cosmic Daybook/AppCore/AppBootstrapper.swift` and its own tests.
  - **Findings:** H1 as decided, with tests for:
    - a lagging device (the row says ParentLocker, the preference says email): nothing is written
    - a deadline edit keeping the method
    - a sync arriving while Settings is open
    - the launch seed against a later row
    - the Sample Class

    Also M9's screen side in `signInRow` (`needsSignIn`, "Sign in again"), L3 (the site only on Return or close, and committed before the sheet opens) and L7 (the label above the control at accessibility sizes).
- **A, Assistant and Siri.** `feature-phase`, Opus high.
  - **Files:**
    - In `Daybook Assistant/`: `FrontDesk/AssistantParentLocker.swift`, `AssistantParentLockerRow.swift`, `AssistantFrontDeskRow.swift`, `Attendance/AssistantArrivalBar*.swift`, `AssistantAttendanceView.swift`, `Sync/AssistantParentLockerSection.swift`, `Siri/AssistantSiriHost.swift`, `AssistantSiriCommands.swift` and `AssistantAttendanceIntents.swift`.
    - `Cosmic Daybook/Siri/SiriAttendance.swift` and `SiriAttendanceChange.swift`.
    - Assistant tests: `AssistantParentLockerTests.swift` (with its fake), `AssistantSiriCloseArrivalTests.swift`, `AssistantSiriTests.swift` and new ones.
  - **Findings:**
    - H2: Siri's undo of a close calls the sync's `cancelCloseArrivalSend()`, or, with no sync, the static `cancelOwedCloseArrivalSend`, through `SiriHost.closeArrivalUndone`. "Already gone" comes from `latestSend(on:)`, and then Siri says ParentLocker keeps those absences.
    - `cancelCloseArrivalSend` and `needsSignIn` are added to `AssistantParentLockerSending`.
    - M2 and M4 on the Assistant.
    - L1; L2, with the prompt following `awaitsSignIn`; L4; L5; L6.
- **N, notebook screens.** `feature-phase`, Opus high. It starts when the first of E, H or A finishes.
  - **Files:** in `Cosmic Daybook/Today/Views/Attendance/`, `AttendanceExpandedView+ParentLocker.swift` and `+FrontDesk.swift`; in `Cosmic Daybook/Attendance/ParentLocker/`, `ParentLockerStatusLine.swift` and `ParentLockerMatchView.swift`; `Cosmic Daybook/Siri/SendAttendanceIntent.swift`; and its own tests.
  - **Findings:**
    - M1: open the sheet after `undoEndsAt`.
    - M2: the iPhone row gets the Send button; the reminder tap (`.frontDeskEmailRequested`) offers it.
    - M3: problems are drawn without a line, and Send Now toasts the first problem.
    - M4: a confirm that names the unmarked, and the Shortcut's `requestConfirmation`.
    - M7: Match Names calls `noteChanges`.
    - L6 on the notebook.
    - The `+FrontDesk` deadline is read from the row.
- **Cost:** E ~3%, H ~1.5%, A ~1%, N ~1%.
- **Done when:** the agents' tables add up to exactly 23 findings (plus the hooks), each with a test or a reason why there isn't one, and their builds and suites are clean.

## Phase 2: Combine and land (main session)
- **Steps:**
  1. Merge E, H, A and N.
  2. Run every named test on the merged tree, where it must pass, and on 3ba3c2f8 where possible, where it must fail.
  3. An Opus review of the fix diff against the report. It also checks the joins: Siri's Undo with no sync, the Shortcut's confirm, and H1 across two devices.
  4. Fix what holds up.
  5. Five builds.
  6. The notebook's whole suite once, and the Assistant's three times.
  7. Squash onto main and push, with the unsquashed history on `parentlocker-afternoon-fixes-unsquashed`.
- **Done when:** the review answers all 23 as fixed, the builds are clean, the suites pass, and it is on main and pushed. TestFlight still waits for Danny.

## Plan review (2026-10-13)
An Opus reviewer made 14 points, all taken:
- the Phase 0 hooks, and no `noteMatched`
- H2's static cancel and the Siri files
- `FrontDeskEmailReminder` to E
- M4 covering `send(day:preview:)` and MCP
- H1's design (one field at a time, actions only, a narrow repair, the launch seed, the Sample Class) and its own xhigh agent
- M9's screen side to H
- L6 for today only
- the test fakes and `project.pbxproj` to E
- the 23-row proof and the fail-on-old check
- the 75% stop

## Open questions
None.
