# Daybook Assistant bug fixes (hunt of 2026-10-04)

> **Working on it.** Written 2026-10-04; all five fix phases started 2026-10-04 after the weekly reset.
> In short: Fixes for the ~50 findings of the 2026-10-04 Daybook Assistant bug hunt, in six phases.
> Build board: https://claude.ai/artifact/39K63NUK4t7kmwbsTn1C1c

## Goal
Every finding from the 2026-10-04 Daybook Assistant bug hunt (five code reviewers + a Sample Class simulator walk over main 44389d4d) is fixed, each behavior fix with a regression test that fails on the old code, the layout fixes checked on an SE and an iPhone 17 simulator, everything squashed onto main, pushed, and rolled out to TestFlight (notebook + Assistant), with the Assistant build added to the TestFlight group "Assistants".

## Progress
- [ ] Phase 1: Attendance grid, store and Siri attendance (agent, worktree) ‖ 2 ‖ 3 ‖ 4 ‖ 5
- [ ] Phase 2: Reminders and the front-desk email (agent, worktree)
- [ ] Phase 3: Restock (agent, worktree)
- [ ] Phase 4: Sync, joining and leaving (agent, worktree)
- [ ] Phase 5: Shell, layout and readability (agent, worktree)
- [ ] Phase 6: Combine, full builds, whole suites, SE check, ship (main session)

Session: all phases run from the planning session (branch `claude/assistants-app-bugs-3a5efa`, worktree `.claude/worktrees/groups-view-analysis-9432b3`). It launches Phases 1–5 as parallel agents with `isolation: "worktree"` (they start at origin/main 44389d4d, which equals local main), then does Phase 6 itself. No fresh-session handoff: the findings context is already loaded here and Phase 6 needs it.

## Decisions
- **SE fit (Danny, option A, after a to-scale mockup):** shrink the SE's tiles and gaps so all 22 children fit again: 46 pt tiles with 6 pt gaps ungrouped (8 rows = 410 pt of the ~413 pt grid area between the count row and the bottom bar); with Group by Level on, the existing 44 pt grouped minimum. Group by Level is off by default, so dropping level groups would not have fixed it. Ruled out: option B (Close Arrival moved into the count row and the sync line hidden, keeping 52 pt tiles), because it moves Close Arrival away from the thumb and drops the "1 absent · 21 not marked" line; accepting the scroll.
- **Late then left early in the email (Danny):** stay under Left Early with "(arrived late)" after the name, in both apps' emails. Not listed twice.
- **Ship (Danny):** after Phase 6, squash onto main, push, and run the `roll-out` skill for both apps. Danny named the group: the Assistant build goes to the TestFlight group "Assistants" (the group's exact name is checked in App Store Connect; the notebook build gets no group, since the assistants don't use it).
- **Close Arrival's tag (decided here):** fix at the root in `CDAttendanceStore.mark(_:as:at:)`: any status change clears `absenceReasonRaw` when it is `AttendanceDeduplication.automaticAbsenceRaw` (`markUnmarkedAbsent` sets it after `mark`, so it still works). This covers the grid's Undo, Siri's Undo, and the notebook's own paths at once. Undo also clears the tag on the day's other copies of that child's record (`arrivalClosed` scans every record, losing duplicates included).
- **Undo of Close Arrival (decided here):** Undo goes back to following the records (`AttendanceLatePhase.setLate(false, on:)`), not an on-purpose reopen. The menu's Reopen Arrival keeps `reopen`.
- **After Reopen Arrival (decided here):** the Late capsule / Close Arrival control stays available while any automatic absence stands that day, so she can go back to Late.
- **Restock reconcile repair (decided here, after review):** only one direction: open a need for a Low/Out staple that has none, and only on settled data (the staple's `levelChangedAt` older than 5 minutes), writing no History line. A Stocked staple with an open need is not auto-closed (another device's half-arrived import could make that wrong); its office-run tag shows the staple's name instead of "One-off".
- **Restock check-offs (decided here):** cleared when the tab reappears and when the app comes back to the foreground; keyed by the need's UUID `id`, not `objectID`.
- **Siri "add X to the office run" (decided here):** a staple is taken only on an exact normalized match or exactly one fuzzy match; otherwise X is added as a one-off.
- **Leave with unsent marks (decided here):** before purging, if `AssistantShareAttacher.shared.pending` is non-empty or `UnsentChangesKeepAlive.hasUnsentWork`, the confirm says how many marks haven't reached the guide and offers Wait (try sending first) / Leave Anyway.
- **History trim (decided here):** an Assistant-only launch trim using the notebook's rule (older than both the last export's start and 180 days), in an Assistant-owned file. Export starts are recorded **per store** from the container's event notifications at launch (not only while `AssistantSyncStatusView` is open, unlike today's `Assistant.lastSharedExportStart`); each delete is scoped to its own store (`affectedStores`); a store with no recorded export is not trimmed.
- **App name in copy (decided here):** on the assistant's phone, text that points at the Home Screen icon or Settings says "Assistant" (or "this app"), because `CFBundleDisplayName` is "Assistant". Text in the notebook that names the app to install from TestFlight keeps "Daybook Assistant" (that's its TestFlight name). Spoken Siri phrases must match how Siri knows the app: check `CFBundleSpokenName` / `INAlternativeAppNames` in `Daybook Assistant/Info.plist` and the App Shortcuts phrases (`\(.applicationName)`) before changing any.
- **SE tile size (decided here, after review):** an SE-only size in `AssistantAttendanceView` (e.g. `smallestGroupedTileHeight` / the `hidesStatusBar` cap), not a change to `AttendanceTile.phoneHeight`, which the notebook's iPhone grid also uses (`AttendanceTileGrid.swift:47`).
- **Ruled out:** moving or re-sharing records (CLAUDE.md: never `share(_:to:)` already-shared records); schema changes (none needed; if a phase thinks it needs one, stop and report).

## Estimated cost
Danny's Max plan was at 84% of the weekly limit on 2026-10-04 (resets Thu 2026-10-09 17:00 UTC), with about $10 of extra usage left. Rough estimates (±50%), calibrated from two usage readings around the bug hunt (six read-only reviewers ≈ 2–3% of a week):

| Phase | Estimate (weekly) |
|---|---|
| 1 Attendance | 2–3% |
| 2 Reminders and email | 1–1.5% |
| 3 Restock | 1.5–2.5% |
| 4 Sync, joining, leaving | 1.5–2.5% |
| 5 Layout and readability | 1.5–2.5% |
| 6 Combine, test, review, ship | 2–3% |
| Total | about 10–15% |

Suggested split if run before the reset: Phases 1 + 3 + 6 now (≈5.5–8.5%), Phases 2, 4, 5 and a smaller second Phase 6 (≈1–1.5%) after it. Check `get_usage` before launching agents.

## Rules for every agent phase
- Read `CLAUDE.md`, `Cosmic Daybook/CLAUDE.md` and `~/.claude/CLAUDE.md` first. Builds only through `Scripts/locked_xcodebuild.sh`; simulator tests through `~/.claude/bin/build-turn` with `-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"` and `-parallel-testing-enabled NO` (1 simulator). If the queue waits, let it wait.
- The plan lives at `/Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/groups-view-analysis-9432b3/Documentation/Implementation/ASSISTANT_BUG_FIX_PLAN.md` (a worktree's old path; now `docs/Plans/Plan - Daybook Assistant bug fixes.md`) (read it there; your worktree starts at origin/main and may not have it).
- Build only the `Daybook Assistant` scheme, plus — when the phase edits a shared notebook file — `Cosmic Daybook` for iOS Simulator **and** for macOS (`-destination "platform=macOS"`); run only the `-only-testing:` suites named in the phase. Never the full suites.
- Each behavior fix gets a test that fails on the old code (say which). Swift Testing; watch for vacuous `#expect` on `?.` bases.
- Shared notebook files the Assistant compiles must still build for iOS 18 and keep classic save notifications (not typed `.didSave`).
- Stay inside the phase's file list. If a fix needs a file another phase owns, don't edit it: note it in the reply.
- Plain English in every message; American spelling.
- Commit on the worktree's branch with a clear message; end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Reply in at most 15 lines: what changed (files), build and test results with counts, anything unresolved or decided differently from the plan. No narrative.

## Phase 1: Attendance grid, store and Siri attendance
- Who: `feature-phase-deep` (opus, xhigh): touches the shared attendance store and cross-device Close Arrival semantics, where a subtle mistake records children wrong on every device.
- Files owned: `Cosmic Daybook/Attendance/Store/CDAttendanceStore*.swift`, `Attendance/Store/AttendanceDeduplication.swift`, `Attendance/Rules/*` (AttendanceLatePhase, AttendanceRules, AttendanceSchoolDayCount), `Cosmic Daybook/Siri/SiriAttendance.swift`, `Cosmic Daybook/Siri/SiriHost.swift`, `Cosmic Daybook/Siri/AttendanceIntents.swift` (copy only), the notebook's `AttendanceGrid.swift` (copy at ≈71 only), `Daybook Assistant/FrontDesk/AssistantFrontDeskMail.swift`, `Daybook Assistant/Notification.Name+Assistant.swift`, `Daybook Assistant/Attendance/AssistantAttendanceViewModel*.swift`, `AssistantArrivalBar.swift`, `AssistantAttendanceView.swift` **only its `.task` block and note/pickup sheet wiring** (Phase 5 owns the count strip and tile sizing in that file), `Daybook Assistant/Siri/AssistantSiriCommands.swift`, `AssistantSiriHost.swift`.
- Steps (findings):
  1. **Close Arrival tag left after Undo** — `CDAttendanceStore.mark` (≈line 90) never clears `absenceReasonRaw`; grid `returnToArrival(undo:)` (AssistantAttendanceViewModel.swift ≈291–310) and Siri undo (SiriAttendance.swift ≈315–333, Close Arrival's Pending has no `fromReasonRaw`) go to `.unmarked` keeping "closeArrival"; a later status-only Absent (Siri "Maya is absent", `markUnwrapped` ≈160–185) makes `arrivalClosed(on:)` true everywhere. Fix per Decisions. Test: undo then status-only absent → `arrivalClosed == false`.
  2. **Undo = on-purpose reopen** — `returnToArrival` calls `AttendanceLatePhase.reopen` even for Undo; `isLate` then ignores the guide's later Close Arrival. Undo → `setLate(false, on:)`; Siri's `reopenArrival` (SiriAttendance ≈336, `SiriHost.arrivalReopened`) likewise for Undo. Test.
  3. **No way back to Late after Reopen Arrival** (sim) — `showsArrivalControl` (`+Rules.swift` ≈22–29) is false in arrival once nobody is unmarked. Show the control while any automatic absence stands.
  4. **Stale grid after the Restock tab** — `.task` (AssistantAttendanceView ≈224–231) skips `load()` when the view model exists; SwiftUI cancels the task on tab switch, so imports in between are missed. Load on every restart.
  5. **Unmark doesn't stick with a duplicate record** — dedup (`AttendanceDeduplication.wins` ≈26–28) makes the other, still-marked copy win. Going to unmarked also clears the day's other copies (as `updateLeavesAt` does via `otherCopies`). Test.
  6. **Absent › No Reason on a Close Arrival absence doesn't stamp** — `updateAbsenceReason` (≈260–268) compares the decoded reason ("closeArrival" reads `.none`) after rewriting the raw value. Compare raw values. Test.
  7. **Holiday at a non-midnight time shows "Weekend"** — `dayOff(on:)` (`+Rules.swift` ≈58) uses `date == %@`; use the whole-day range like `SchoolDayChecker.hasRecord`. Test.
  8. **Note/pickup saved to the wrong day** — `editRecord` (≈350) uses the grid's current day at save; pass the row's day captured when the sheet opened (or close the sheet on day change).
  9. **Close Arrival on a day locked since load** — `markUnmarkedAbsent` returns [] but phase flips to Late silently (≈264–278). Check `store.canWrite(on:)` first; reload and say "Your guide has locked this day."
  10. **Front-desk reminder tap sends an email missing unmarked children** (moved here from Phase 2: the question is the bar's private `confirmingClose` dialog, `AssistantArrivalBar.swift` ≈108–110) — `AssistantFrontDeskMail.openForReminder` (≈71–77) → `open()` ignores `unmarkedCount`; `draft` lists only present/tardy/absent/left early. When unmarked > 0 on a day she can mark, the tap asks the bar's "Mark N Absent & Email" question instead. Test the routing decision.
  11. **Day number cached from a partial first download** — `AttendanceDayCounter.count` (AttendanceSchoolDayCount ≈141–151) caches `firstDays[yearStart]` forever. Recompute on import reloads (or don't cache until the first download is done). Test.
  13. **Siri Close Arrival racing a grid close** — `AssistantSiriCommands.swift` ≈34–46: re-run `checkClose` inside `closeArrival` before marking; answer "Arrival is already closed".
  14. **Arrival-bar haptic on imports** — `AssistantArrivalBar.swift:78` keys a haptic to `viewModel.phase`, which every `load()` recomputes. Fire only on her own close/reopen (a counter like `completions`).
  15. **School calendar read from both stores** — `SiriAttendance.swift` ≈93 resolves days/ids from either store; scope to the shared store when it exists (as `AssistantDayRoll` does).
  16. **Sample Class "by an assistant" vs "by you"** — `AttendanceRules.markerName` falls through to "an assistant" with no record name and no name; with no record name, a mark stamped by this device should read "you" (match the front-desk line).
  17. **Copy** — "Daybook Assistant" strings in `AssistantSiriHost.swift` ≈13, 21, `AttendanceIntents.swift` ≈24, `AttendanceGrid.swift` ≈71: apply the app-name rule in Decisions.
- Done when: `Daybook Assistant` and `Cosmic Daybook` (iOS Simulator + macOS) build clean; `-only-testing:` passes for `Daybook Assistant Tests/AssistantAttendanceRulesTests`, `AssistantDayRulesTests`, `AssistantSiriTests`, `AssistantWelcomeBackTests`, `AssistantSchoolDayCountTests`, `AssistantScreenStateTests`, `AssistantMenuTests`, `AssistantSampleClassTests`, `AssistantShareScopeTests` and `Cosmic Daybook Tests/AttendanceDeduplicationTests`, `AttendanceViewModelTests`, `AttendanceDayLockTests`, `AttendanceMarkedAtTests`, `SiriAttendanceTests` (plus any new suite); each new test named in the reply with the old-code failure.
- Hand off: no.

## Phase 2: Reminders and the front-desk email
- Who: `feature-phase` (opus, high): notification scheduling and an email composer on an existing data layer.
- Files owned: `Daybook Assistant/Reminders/*`, `Daybook Assistant/FrontDesk/*` except `AssistantFrontDeskMail.swift` (Phase 1), `Cosmic Daybook/Attendance/Email/*` (FrontDeskEmailReminder, AttendanceEmailLog, AttendanceEmailReport/AttendanceEmail body builder), `AttendanceExpandedView+FrontDesk.swift` (notebook), `Cosmic Daybook/Siri/SiriSyncKeepAlive.swift`, `Cosmic Daybook/Siri/StudentAppEntity.swift`.
- Steps:
  1. (Moved to Phase 1, step 10.)
  2. **Arrival and front-desk reminders ignore remote changes** — `EarlyPickupReminderUpkeep.changed` (≈29–37) reschedules only pickups. Also run `ArrivalReminder.reschedule` and `FrontDeskEmailReminder.reschedule` with `asksPermission: false`. Test.
  3. **Pickup permission prompt over first-run setup** — `ArrivalReminder.swift:202` → `EarlyPickupReminder.swift:222`: pass `asksPermission: AssistantOnboarding.setupDone()`.
  4. **Reschedule cancelled midway by a tab switch** — `ArrivalReminder.swift:120`, `FrontDeskEmailReminder.swift:151` remove all then re-add with cancellation checks. Build the list first, then swap in without stopping after the removal.
  5. **Late then left early** — Decisions: under Left Early with "(arrived late)" when `statusBeforeLeavingRaw == tardy`; both the Assistant (`AssistantFrontDesk.draft` ≈78–84) and the notebook (`AttendanceExpandedView+FrontDesk.swift` ≈97–110 / shared body builder). Update `AttendanceEmailBodyTests`.
  6. **Siri keep-alive ends on a failed upload** — `SiriSyncKeepAlive.swift:70` `SiriExportWatch` must require `event.succeeded` (and the shared store's export). Test if feasible.
  7. **Email settings and sends read from both stores** — `AttendanceEmailLog.swift` ≈145–151, 235–240: scope to the shared store when one exists.
  8. **Full names on a locked phone** — `StudentAppEntity.entities(for:)` (≈82–87) doesn't set `displayName`; run through `SiriHost.displayNames` (read-only use of SiriHost; Phase 1 owns that file).
  9. **Copy** — `AttendanceEmail.swift` ≈74 "Daybook Assistant": apply the app-name rule in Decisions.
- Done when: `Daybook Assistant` and `Cosmic Daybook` (iOS Simulator + macOS) build clean; `-only-testing:` passes for `Daybook Assistant Tests/ArrivalReminderTests`, `EarlyPickupReminderTests`, `AssistantSiriTests`, `UnsentChangesKeepAliveTests`, `AssistantShareScopeTests` and `Cosmic Daybook Tests/AttendanceEmailBodyTests`, `AttendanceEmailLogTests`, `AttendanceEmailPreferencesTests`.
- Hand off: no.

## Phase 3: Restock
- Who: `feature-phase-deep` (opus, xhigh): `reconcile` and share-attach changes run on every device against shared records.
- Files owned: `Daybook Assistant/Restock/*`, `Daybook Assistant/Siri/AssistantSiriRestock.swift`, `AssistantRestockIntents.swift`, `SupplyAppEntity.swift`, `Daybook Assistant/AssistantTabs.swift`, `Cosmic Daybook/Supplies/Services/RestockService*.swift`, `Cosmic Daybook/Supplies/RestockModels.swift`, `Cosmic Daybook/Orders/Services/OrderService.swift` (only if the link test belongs there).
- Steps:
  1. **Check-offs live for the session; a stray tap days later undoes them** — `AssistantRestockModel.checkOffs` (≈43–45, 121–126, 175–183); `undoCheckOff` reverts even if restocked since and deletes the synced history line. Clear per Decisions; Undo only if the staple hasn't changed since the check-off. Test.
  2. **Check-off keyed by temporary objectID** — key by `need.id` (UUID). Test (check off before save, then save).
  3. **Siri marks the wrong staple** — `AssistantSiriRestock.addToOfficeRun` (≈98) takes `.first` of fuzzy matches. Per Decisions. Test ("paper" with Paper Towels + Toilet Paper → one-off).
  4. **Author frozen at tab creation** (sim) — `AssistantTabs.makeRestock` (≈55–58) builds `RestockAuthor.current(role: .assistant)` once; a name set later (or the CloudKit record name cached later) is missed, so her own changes read "Your guide". Read the author at write time (closure or refresh on `ClassroomIdentity` change). Test.
  5. **Restock rows saved by another save never attached** — `AssistantRestockModel` reads `context.insertedObjects` at save time (≈349–353). Keep a `createdSinceSave` list like attendance and pass it to `AssistantSave`. Test.
  6. **Level and need out of step across devices** — extend `reconcile` (RestockService+Needs ≈224–247) per the reconcile Decision (one direction, settled data only, no History line); the Stocked-with-open-need case gets the tag fix in `AssistantRestockStyle.swift` ≈67–72. Still only on appear/import, never a loop. Tests, including that a fresh (< 5 min) Low staple with no need is left alone.
  7. **Failed Siri save discards the tab's pending taps** — `AssistantSiriRestock.swift` ≈128–131 `context.rollback()`. Undo only Siri's own changes, and post the reload notice on failure too.
  8. **Trailing period** — `pastedLink` (`AssistantRestockModel` ≈227–231) treats "Kleenex." as a link; trim trailing punctuation before staple matching and link detection; a link needs "://" or a dot followed by a real domain ending. Tests ("Kleenex.", "Toilet paper.", "amazon.com/dp/x").
  9. **Unnamed second assistant shows as "your guide"** — `RestockModels.swift:101`; compare against the classroom owner, fall back to "another assistant". Test.
  10. **Hold-menu header wording** (`AssistantRestockModel` ≈246–255) — "Added …" when no history line exists; "Your guide orders it" instead of "Ordered".
  11. **AX text: tiles split words** (sim) — `AssistantRestockView.swift:16` two fixed columns; one column at accessibility sizes, like the attendance grid.
  12. **Office-run subtitle too light** (sim) — "4 to grab · check off as you go" uses a very light gray; use `.secondary`.
  13. **Copy** — `AssistantWeNeedSheet.swift` ≈169 "Daybook Assistant": apply the app-name rule in Decisions.
- Done when: `Daybook Assistant` and `Cosmic Daybook` (iOS Simulator + macOS) build clean; `-only-testing:` passes for `Daybook Assistant Tests/AssistantRestockTests`, `AssistantSiriRestockTests` and `Cosmic Daybook Tests/RestockNeedTests`, `RestockStapleTests`, `RestockPageTests`, `RestockSplitStoreTests`, `RestockLevelBackfillTests`.
- Hand off: no.

## Phase 4: Sync, joining and leaving
- Who: `feature-phase-deep` (opus, xhigh): share attach, stack rebuilds, Leave's purge and history trimming can lose marks.
- Files owned: `Daybook Assistant/Sync/*` (incl. `AssistantClassroomSheet.swift` — all its copy too), `Daybook Assistant/Onboarding/AssistantIntroPages.swift`, `Daybook Assistant/AssistantApp.swift`, `Daybook Assistant/AssistantStartupProblem*.swift`, `Cosmic Daybook/AppCore/Persistence/CoreDataStack.swift` (copy at ≈340–342 only), `Cosmic Daybook/Sharing/ClassroomSharingService.swift` (join timeout only), `Cosmic Daybook/Sharing/ClassroomLeave.swift`, `Cosmic Daybook/Utils/Diagnostics/AppErrorMessages.swift`, a new Assistant-only history-trim file under `Daybook Assistant/Sync/`.
- Steps:
  1. **"Sending to iCloud…" forever after mirroring stops** — `AssistantShareAttacher.swift` 171, 189–195 sets `stoppedContainer`; only an account arrival rebuilds. When a pass reports `mirroringStopped`, have the bootstrapper rebuild the stack once (as `rebuildStackForAccount`), and give `AssistantSyncStatusView` a plain stuck state if it still can't send. Test what's testable (decision logic).
  2. **Leave can drop unsent marks** — `AssistantBootstrapper.leaveClassroom` (≈182–187) purges at once. Per Decisions. Test the decision.
  3. **Leave's specific errors overwritten** — `AssistantClassroomSheet.swift` ≈293–297; use `AppErrorMessages.sharingMessage(for:action:)` so `ClassroomLeaveError` texts show.
  4. **Removed from the class → "No students yet… a minute after you join"** — while `.ready`, if no share in the shared store matches the pinned zone after an import, show "You're no longer in this class. Ask your guide for a new invitation." with Leave (`AssistantBootstrapper` ≈193–207; the empty state's text lives in `AssistantAttendanceView` ≈276–278 — **Phase 1/5 own that file: expose a state/property from the bootstrapper and note the one-line view change for Phase 6**).
  5. **Join that hangs** — `isJoining` (ClassroomSharingService ≈348–362) has no timeout; add ~60 s with a plain error; the timeout can't cancel CloudKit's accept, so a join that succeeds after the error must still finish and flip onboarding (Check Again finds it); keep Check Again / Try a Sample Class reachable (`AssistantIntroPages.swift` ≈244–255, 291).
  6. **Join errors unwrapped** — `AppErrorMessages.swift` ≈116–131: unwrap CKError partial failures' per-item error and Core Data underlying errors before matching. Tests.
  7. **History never trimmed in the Assistant** — per the History trim Decision (per-store export starts, per-store deletes, skip stores with no recorded export; CoreDataStack.swift ≈224–247 skips the processor under `ASSISTANT_APP`). Tests: cutoff rule, and a store with no export is untouched.
  8. **Overlapping account checks** — `AssistantBootstrapper` ≈226–246: number each `refreshAccountStatus`, ignore stale answers; re-check on foreground (hook in `AssistantApp.swift`). Test.
  9. **Copy:** `AssistantClassroomSheet.swift:183` and `AssistantStartupProblem.swift` 24/31/37 say "Daybook Assistant" → "Assistant"; the Classroom sheet's duplicate "Classroom" title/section header; split the one long reminders footer into short lines; also `AssistantIntroPages.swift` ≈20 and `CoreDataStack.swift` ≈340–342 — apply the app-name rule in Decisions.
- Done when: `Daybook Assistant` and `Cosmic Daybook` (iOS Simulator + macOS, since AppErrorMessages/ClassroomSharingService/CoreDataStack are shared) build clean; `-only-testing:` passes for `Daybook Assistant Tests/AssistantShareAttacherTests`, `AssistantShareAttacherStackTests`, `AssistantScreenStateTests`, `AssistantStartupProblemTests`, `AssistantOnboardingTests`, `AssistantICloudStatusTests`, `AssistantSplitStoreTests` and `Cosmic Daybook Tests/SyncPlainEnglishTests`.
- Hand off: no.

## Phase 5: Shell, layout and readability
- Who: `feature-phase` (opus, high): SwiftUI layout with simulator screenshots on an SE and an iPhone 17.
- Files owned: `Daybook Assistant/AssistantToastService.swift`, `AssistantRootView.swift`, `AssistantDatePickerSheet.swift`, `Daybook Assistant/Wallpaper/*`, `Daybook Assistant/Assets.xcassets/AccentColor.colorset`, `Daybook Assistant/Attendance/AssistantAttendanceView.swift` **only the count strip and tile sizing** (Phase 1 owns `.task` and sheets), `AssistantAttendanceView+Toolbar.swift`, `AssistantTileKey.swift`, `Daybook Assistant/Onboarding/AssistantNameSheet.swift`, `AssistantSetupFlow.swift`, `AssistantSetupPages.swift`, `Cosmic Daybook/Attendance/Tile/AttendanceTile+Menu.swift`, `Cosmic Daybook/Attendance/Delight/AttendanceWelcomeBack.swift`, `Cosmic Daybook/Attendance/Delight/AttendanceBells.swift`. Not `AttendanceTile.swift` (see the SE tile size Decision).
- Steps:
  1. **SE: 22 children don't fit** — per the SE tile size Decision: an SE-only smaller tile/gap in `AssistantAttendanceView` ≈150–160 (`hidesStatusBar ? min(height, AttendanceTile.phoneHeight)`, `smallestGroupedTileHeight`) so 22 fit with level groups and the tab bar. Update `AssistantTileSizeTests` and the code comment (≈12–16).
  2. **Date-picker sheet clipped on SE** — `AssistantDatePickerSheet.swift:37` `.medium`; open `.large` on short screens (or scroll).
  3. **Toasts** — `AssistantToastService.swift` 30–36 / `AssistantRootView` 12–25: time scaled to length, VoiceOver announcement, `.allowsHitTesting(false)`.
  4. **Failed photo Change is silent** — `AssistantWallpaperPicker.swift` 53–67, 92–94: show `importError` and a spinner under Change/Remove too.
  5. **Failed first photo read not retried** — `AssistantWallpaperPhoto.swift` 48–52: set `didLoad` only on success.
  6. **Accent purple has no dark variant** (sim) — add a dark appearance to `AccentColor.colorset` with enough contrast on near-black (check Close Arrival and the selected tab).
  7. **AX text: count overflows its strip** (sim) — `AssistantAttendanceView` ≈321, 327 fix height 20; let it grow.
  8. **AX text: SE header overflow** — `AssistantAttendanceView+Toolbar.swift` 95–125: date-only line at accessibility sizes.
  9. **Tile key "La/te"** (sim) — `AssistantTileKey.swift` 67–76, ≈107 fixed 72 pt; let the sample size itself; also say gray = absent in the "Green line" entry.
  10. **Name restored from iCloud doesn't fill an open name sheet** — `AssistantNameSheet.swift:19`, `AssistantSetupFlow.swift:84`: observe the name change and fill (or dismiss).
  11. **Onboarding mock says "Daybook Assistant"** — `AssistantSetupPages.swift`: "Assistant".
  12. **Bells built on the main thread** — `AttendanceBells.swift` 115–131, 182–216: build tunes off the main thread when Bells turns on; key `.here` by note index.
  13. **SE: no clock on a non-today day** (sim) — the status bar is hidden and the Today button replaces the clock; keep a clock visible.
  14. **Locked day: long-press shows nothing** (moved from Phase 1) — `AttendanceTile+Menu.swift:12` `if canMark`. Show a read-only menu (header with time/reason/who + note) when `canMark` is false. Check the notebook's iPhone/iPad tiles still behave.
  15. **Welcome-back wave on an absent child** (moved from Phase 1) — `AttendanceWelcomeBack.returning` ignores the day's own status; skip absent (incl. future absences). Test.
  16. **Copy** — `AssistantSetupFlow.swift` ≈208, 290–294 (spoken Siri phrases): apply the app-name rule in Decisions, checking Siri's name for the app first.
- Done when: `Daybook Assistant` and `Cosmic Daybook` (iOS Simulator + macOS, for the shared tile menu/welcome-back/bells files) build clean; `-only-testing:` passes for `Daybook Assistant Tests/AssistantTileSizeTests`, `AssistantGroupedTileSizeTests`, `AssistantLevelGroupsTests`, `AssistantWallpaperTests`, `AssistantDelightTests`, `AssistantOnboardingTests`, `AssistantMenuTests`, `AssistantWelcomeBackTests`; screenshots of the Sample Class (`-AssistantSampleClass`) on an SE on iOS 26.5 (`sim-lease --type "iPhone SE (3rd generation)" --os 26.5`, always with `--os 26.5`; see `Cosmic Daybook/CLAUDE.md`) and an iPhone 17 at default and accessibility-XXXL text and in dark mode, saved in the agent's scratchpad, paths in the reply. Shut the simulators down afterwards.
- Hand off: no.

## Phase 6: Combine, full builds, whole suites, SE check, ship
- Who: main session (needs the agents' replies and the merge context).
- Steps:
  1. Merge the five agent branches into `claude/assistants-app-bugs-3a5efa` one at a time (`git merge --no-ff`), resolving the two planned shared-file seams (`AssistantAttendanceView.swift`: Phase 1's `.task`/sheets vs Phase 5's layout; Phase 4's "no longer in this class" state needs its one-line view hookup here). Also check no phase reports a needed edit in another phase's file; apply those here.
  2. Builds: `Daybook Assistant`, `Cosmic Daybook` for iOS Simulator, and `Cosmic Daybook` for macOS (shared attendance/email/restock/sharing files changed).
  3. Whole suites once: `Daybook Assistant Tests`, then `Cosmic Daybook Tests` on the leased iOS simulator (`-parallel-testing-enabled NO`). Known skips: 7 album sentence-model tests.
  4. Sample Class pass on the SE (iOS 26.5, `--os 26.5`) and iPhone 17: 22 fit on the SE; Close Arrival → Undo → absent stays untagged; Reopen → back to Late; Restock tab round trip refreshes the grid; dark mode; AX XXXL.
  5. Review the combined diff (`/code-review high`) and fix what holds up.
  6. Squash onto main (main checkout may be on another session's branch: land with `git update-ref`, see memory `merge-when-checkout-shared`), push, then `roll-out` for the notebook and the Assistant; add the Assistant build to the "Assistants" group.
  7. Update memory `assistant-bug-hunt-2026-10-04` and the Tide device-check row.
- Done when: all three builds clean; both whole suites pass (counts in the report, any failure explained); the SE/iPhone 17 checks above seen in screenshots; main pushed; TestFlight uploads accepted and the Assistant build is in the Assistants group.
- Hand off: no.

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan.
3. Update the build board, if the plan lists one.
4. Run /close-out (Phase 6 only; agent phases end at their commit).
5. No fresh-session phases: the main session continues.

## Open questions
- Which phases to run now and which after the 2026-10-09 reset (Danny asked for per-phase estimates first; they're under Estimated cost).
