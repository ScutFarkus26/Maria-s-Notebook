# Daybook Assistant bug hunt 2026-11-06 fixes

> **Done 2026-11-07** (e17df4546; pushed as 204eae649, Assistant 1.1 (034) uploaded to no group). Written 2026-11-06 from the read-only hunt in <../Reviews/Daybook Assistant bug hunt 2026-11-06.md>.
> In short: all 20 findings of that hunt get fixed in three parallel phases (Close Arrival, Siri and the front desk; sync; the Schedule tab and waste). A final phase then combines them, reviews, runs every suite, pushes main and uploads an Assistant build to TestFlight without adding it to a group.

## Goal

Danny gets all 20 findings fixed on main and pushed. Each bug has a test that pins it. The combined fixes get a cold review. An Assistant build is uploaded to App Store Connect and left out of every TestFlight group. The finding numbers (#1–#20) are the report's: each phase reads its findings there for the file, line, trigger and suggested fix, and this plan's steps say where a fix must differ from the report's suggestion.

## Progress
Marks: `plan/assistant-fixes-1106`. Each phase tags the primary checkout `plan/assistant-fixes-1106/phase-<N>` when it merges; see `~/.claude/bin/plan-wait`.
- [x] Phase 1: Close Arrival, Siri and the front desk (#1, #2, #3, #4, #6, #11, #12, #13) · done 2026-11-07 (8b8075a9c) · session d0ef0a0f-bdbb-475b-a6a1-453a4750931b · actual $15.93 (~0.6%)
- [x] Phase 2: Sync, joining and view only (#5, #7, #8, #9, #10) · done 2026-11-07 (4e7feabc8) · session 019808ab-195f-4d9e-907d-81f72a5e13cd · actual $12.96 (~0.5%)
- [x] Phase 3: Schedule tab and waste (#14–#20) · done 2026-11-07 (fc13c413f) · session 7bc259ee-81d2-4164-9ae4-da7d711cc6bb · actual $11.52 (~0.4%)
- [x] Phase 4: Final check, review, push and upload · done 2026-11-07 (e17df4546, pushed 204eae649) · session 9e106f0d-8ef3-43ee-9e08-05e175af01e6 · actual $11.04 (~0.4%)

Total: about $86 (about 3% of the week) against $120–200: $51.45 for the four phases and $34.43 for the conductor, including the hunt itself.

Build board: https://claude.ai/artifact/1xdTk2e14yP7gDuX9sqTus (milestones m1–m4 are Phases 1–4; tasks `p<N>-*`).

## Cost

About $120–200 at list prices, **5–8% of the weekly limit** (1% ≈ $26 this week, calibrated 2026-11-06 at 10% used):
- $80–155 for the four phases.
- About $40 for the conductor: this session's hunt and planning ($23 so far) plus about $2 a wake.

90% of the week is left until Fri 13 Nov, 12 pm, so this **fits**. The three parallel phases together are about 3% of the week, far under a 5-hour window. The run brakes itself if a phase costs more than twice the top of its estimate or the week passes 90%.

## Before you go

- **The main checkout** (`~/Developer/Maria's Notebook`): done. The branch-cleanup session dropped the cosmetic project-file commit and moved local main to `origin/main` (4d62e7f20), and the checkout is clean. Before any phase starts, the conductor commits this plan, the hunt report and `docs/Start here.md` there, because phase sessions are cut from local main.
- **Upload key:** checked at planning time. `roll_out.sh upload-key` passed: App Store Connect accepts key 46SC228WQ9.
- **TestFlight groups:** a new build reaches any internal group set to receive builds automatically. If the Assistants group is set that way (Danny's call, in App Store Connect), "added to no group" won't hold for it. It has been added by hand before.
- **Mac plugged in**, and keep-awake on in the app (checked at the go-ahead).
- **Screen lock:** the screen locks as soon as the display sleeps. No phase drives the Mac or a simulator by hand. Simulator checks run headless (`xcodebuild test`, `simctl io screenshot`) and work while the screen is locked, and anything that needs a person becomes a Tide row. So leave the lock as it is.
- **Permission mode:** the conductor is in `bypassPermissions`, and phase sessions inherit it. Nothing to do.
- **Model:** the conductor runs Opus 5.5 at high effort, and every phase runs at the same.

## Decisions

- **Danny's answers (2026-11-06):**
  - When everything passes, push main and upload an Assistant build, added to no TestFlight group. The notebook app gets no new build: its only change people will see is #16, the Mac's split-then-delete, which waits for the notebook's next roll-out.
  - On the Schedule tab, the guide's booked lessons are **hidden** on a day he's out (#15), not shown as out.
- **Fixes may change behavior where the behavior is the bug.** The 11-03 round's "no change in behavior or look" rule doesn't apply here. Everything else stays as it is.
- **Siri's Close Arrival follows the arrival bar's rules** (#1, #2, #3):
  - A View-only phone is refused with the View-only message. An empty roll is refused with a plain "The class hasn't loaded on this iPhone yet. Try again in a moment."
  - When everyone really was marked, arrival closes (Late) but nothing is sent to ParentLocker.
  - "Really marked" and "unmarked" mean the same thing in Siri and on the grid: rows Close Arrival can't mark (no id, a status this build doesn't know) aren't counted as unmarked anywhere. That is why #11 is in Phase 1: one helper, used by both.
- **View only (#6, #7):**
  - A View-only phone hides Email the Front Desk, Send to ParentLocker and Send Now. The grid's View-only notice already says why.
  - Siri gives the View-only message instead of "Open the app to mark it".
  - The saved answer moves to a new key. An old saved `true` is carried over as "not confirmed": it still blocks writes, and it is dropped at the first share read, even one that gives no answer. A View-only phone is never let write in the gap, because the store doesn't refuse such a write. It saves on the phone and never reaches the guide.
- **#9:** wait for the ParentLocker run before the `abandon` check, and stop ParentLocker only after the check passes. Otherwise an abandoned rebuild leaves ParentLocker stopped until a relaunch.
- **#10:** retry when the start that was still running ends, not at the next unlock.
- **#12:** load directly when the Sample Class is open, not "when there's no shared store". Every test fixture has no shared store, and the tab-scoping test `AssistantFix1103Gr.siriMarkFollowsTheScreen` must keep passing.
- **#13:** `SiriAttendance.swift` is shared with the notebook, whose children live in the private store. Narrow the lookup only for the assistant role, or use the per-app `SiriHost.roster(in:)`. Never narrow it to the shared store on the guide's devices.
- **#14:** after a night away, the Schedule tab goes to today, as Attendance does. A day she stepped to within the same day is kept.
- **#16:** only a block the split itself made counts as the split's copy. `replaceWeek` (MCP `set_timetable`) and `copyDay(from:)` also make same-lane, same-weekday blocks that start where old ones end, and a delete must never end those.
- **No new files under `Cosmic Daybook/` that the Assistant compiles**, and no edits to `Cosmic Daybook.xcodeproj/project.pbxproj`. The Assistant lists its shared files there by hand. New test files go in `Daybook Assistant Tests/` or `Cosmic Daybook Tests/`, which are synchronized folders and need no project edit. Each phase puts its tests in **new files of its own** (`AssistantFix1106<Phase>.swift`, `Fix1106<Phase>Tests.swift`), so parallel phases don't conflict in shared test files.
- **Tide rows:** Assistant-only items go in `Areas/App Development/Daybook Assistant/To do.md`; notebook items (#16) in `Areas/App Development/Cosmic Daybook/To do.md`. Device checks go under "Check on a device" and an upload row under "Release".
- **Decided in Phase 2 (2026-11-07):**
  - #5: the account check keeps retrying, with the existing back-off, while the filing hold is on for a failed setup. That now includes while she's in the class.
  - #8: Leave waits for a running rebuild. If the phone is still reconnecting, it says plainly that nothing was removed and to try again in a minute. A rebuild asked for during Leave runs after Leave ends.
  - Test seams added: `Stacks.open` and `Stacks.isOpen`; `notePermission(_:)` split out of `readPermission`; `readClassShare` made internal.
- **Decided in Phase 4 (2026-11-07):**
  - The arrival bar's own Undo after a Reopen had the same bug as #3, so it was fixed the same way and pinned by `AssistantFix1106Review`.
  - Also fixed: the arrival reminder counts "unmarked" by #11's rule; a photo let go during its preload is dropped (#20); Leave takes its notification center from the bootstrapper, so its test runs in under a second.
  - #7: an old View-only answer is dropped only once the class's share is found, which is the safer reading.
- **Decided in Phase 1 (2026-11-07):**
  - The View-only check behind the email and ParentLocker rows asks "may this phone write", not "can mark right now". So on a day the guide has locked, the email is still offered, as before. This is in Tide under Daybook Assistant › Review choices.
  - Siri's Undo on a View-only phone is refused with the View-only message.
  - The #3 Undo fix applies to every Siri close on a reopened day, not only one that marked no one.
  - A close that marks no one while children are still unmarked fails with "couldn't save" instead of closing.
  - Not fixed: the grid's own Undo after a Reopen probably leaves the day Late, as #3 did. Phase 4's review checks it.
- **Decided in Phase 3 (2026-11-07):**
  - #16: a "This Day and After" split gives its copy an ID worked out from the original block and its first day, so a delete can tell the split's own copy from blocks made by `set_timetable` or Copy Day. No schema change is needed. Splits made before this fix keep random IDs, and a delete won't find them.
  - #16: deleting "Every week" from a later piece also ends the pieces before it, so the whole weekly block goes.
  - #16 needed one new file, `Cosmic Daybook/Schedules/Services/TimetableService+Splits.swift`. Only the notebook compiles it, so `project.pbxproj` is unchanged.
  - Both choices are in Tide under Cosmic Daybook › Review choices.
- **Ruled out:**
  - A simulator walk of the Sample Class. The screen locks, and headless screenshots cover the one visual fix, #17.
  - A notebook roll-out.

## Apple guidance

This wasn't looked up as a separate step. Every fix uses APIs the Assistant already uses, in the same way: SwiftUI scene phase, `contextMenu`, App Intents dialogs, `UserDefaults`, store-scoped Core Data fetches, CloudKit share permissions. Two points to follow:
- **#19:** `contextMenu(menuItems:)` builds its items each time the view's body is evaluated. Format the header inside the menu items, or, if that isn't possible, correct the comment.
- **#5:** `CKContainer.accountStatus()` can answer `.couldNotDetermine` or throw shortly after boot or unlock. Keep retrying with the existing back-off, and react to `.CKAccountChanged`.

## Phase 1: Close Arrival, Siri and the front desk

- Who: phase session (Opus 5.5, high). This is shared Siri, attendance and ParentLocker code, where a slip marks the wrong child or sends the wrong thing.
- Needs: —
- Steps (findings in the report; see Decisions for where the fix differs from the report):
  - **#11 first:** one rule for "Close Arrival can mark this row", used by `AssistantDayRoll.unmarked` (and so by Siri's count) and by the grid. Files: `Daybook Assistant/Attendance/AssistantDayRoll.swift` and `AssistantAttendanceViewModel.swift` (`emailCanFollowClose`, `beginLate`: judge by what the store marked, not by the grid's rows). `AssistantArrivalBar.swift` changes only if a caller must.
  - **#1, #2, #3:**
    - `Daybook Assistant/Siri/AssistantSiriCommands.swift` (`checkClose`, `closeArrival`).
    - `Daybook Assistant/Siri/AssistantAttendanceIntents.swift`.
    - `Daybook Assistant/FrontDesk/AssistantParentLocker.swift`: `sendAfterClose` gets a new argument for how many children the close marked, **with no default**, so the compiler finds every caller and test. There is no send when that number is 0, as `AssistantArrivalBar.sendsOnClose` already decides.
    - `Daybook Assistant/Siri/AssistantSiriHost.swift` and `Cosmic Daybook/Attendance/Rules/AttendanceLatePhase.swift`: undoing an empty close on a reopened day reopens the day again.
  - **#4** `Cosmic Daybook/Attendance/ParentLocker/ParentLockerSync.swift` and `ParentLockerSync+LastSeen.swift`: keep `closeArrivalBatchSent` with what's owed, or work it out from the saved sent rows on load.
  - **#6:**
    - `Daybook Assistant/FrontDesk/AssistantFrontDesk.swift` (`isOffered`) and `AssistantParentLocker.swift` (`offersParentLocker`, `offersParentLockerSend`) also require that the phone can mark.
    - `Cosmic Daybook/Siri/SiriAttendance.swift`: here/late/absent on a View-only phone says the View-only message.
  - **#12** `Daybook Assistant/Attendance/AssistantAttendanceView.swift` and `AssistantAttendanceViewModel.swift` (`siriChanged`): load directly when the Sample Class is open.
  - **#13** `SiriAttendance.swift` `student(for:)`: per Decisions. Pin it with a **two-store test** in both test targets, like `AssistantFix1103SR.twoStores`: the guide's Siri still finds a private-store child, and the assistant's Siri finds the class's copy.
  - Tests in the new files `Daybook Assistant Tests/AssistantFix1106Siri.swift` and `Cosmic Daybook Tests/…/Fix1106SiriTests.swift`.
- Cost: $25–45, 1–2%. Based on an Opus high session's thread plus feature-phase-sized work, +50% for shared code tested in two targets and the eight findings.
- Done when:
  - The `Daybook Assistant` scheme builds for the iOS Simulator, and the `Cosmic Daybook` scheme builds for iOS (the shared files).
  - These suites pass with `-only-testing:` in both test targets: the touched Siri attendance, Assistant Siri commands, ParentLocker sync, front desk, grid taps and arrival bar suites (including `AssistantFix1103Gr` and `AssistantFix1103SR`), plus the new ones.
  - Each new test fails without its fix.
- By hand: none. The device checks go to Tide: Siri Close Arrival after a Reopen, and a View-only phone's front-desk rows.

## Phase 2: Sync, joining and view only

- Who: phase session (Opus 5.5, high). These are sync and launch paths, where a mistake leaves marks unsent. Before merging, send a cold Opus review of the phase's diff to a subagent.
- Needs: —
- Steps:
  - **#5** `Daybook Assistant/Sync/AssistantFilingHold.swift`, `AssistantBootstrapper+AccountDecision.swift` and `AssistantBootstrapper+Rebuild.swift`: keep `retryUnknownAccount` running while the filing hold is held for a failed setup, in the class as well as on the join screen.
  - **#7** `Cosmic Daybook/Sharing/ClassroomPermissions.swift` and its reader in `ClassroomSharingService.swift`: the new key, and the old `true` carried over as "not confirmed" (per Decisions). Update `AssistantFix1103SR.swift:15`, which hard-codes the old key.
  - **#8** `AssistantBootstrapper+Leave.swift`, `AssistantBootstrapper.swift`, `+AccountDecision.swift` and `+Rebuild.swift`: Leave waits for a rebuild in progress, and every rebuild path treats `isLeavingHere` as not settled.
  - **#9** `AssistantBootstrapper.swift` (`rebuildOnce`) and `AssistantBootstrapper+ParentLocker.swift`: split `finishParentLockerBeforeRebuild` into "wait for the run", before the `abandon` check, and "stop", after it.
  - **#10** `Daybook Assistant/AssistantApp.swift` and `AssistantBootstrapper.swift` (`retryFailedStart`): retry when the running start ends with the store still unreadable after an unlock (per Decisions).
  - Tests in the new files `Daybook Assistant Tests/AssistantFix1106Sync.swift` and, for the key, `Cosmic Daybook Tests/…/Fix1106ViewOnlyTests.swift`.
- Cost: $15–30, ~1%.
- Done when:
  - The `Daybook Assistant` scheme builds, and the `Cosmic Daybook` iOS scheme builds.
  - The bootstrapper, filing-hold, leave and view-only suites pass with `-only-testing:` (including `AttendanceShareFix1102Tests` and `AssistantFix1103SR`), plus the new ones.
  - Each new test fails without its fix, and the cold review's real findings are fixed.
- By hand: none. One device check goes to Tide: a phone that showed View only under the old rule clears after the update.

## Phase 3: Schedule tab and waste

- Who: phase session (Opus 5.5, high). Seven small, separate fixes across view code and one notebook service.
- Needs: —
- Steps:
  - **#14, #18** `Daybook Assistant/Schedule/AssistantScheduleView.swift` and `AssistantScheduleModel.swift`: remember the calendar day she was last on the tab. On appear, on return and at the minute tick, move to today when the day has changed and the tab was on today, or after a night away.
  - **#15** `Daybook Assistant/Schedule/AssistantScheduleRows.swift`: leave out `.lesson` and `.halfList` rows when the guide's lane is out (Danny chose to hide them).
  - **#16** `Cosmic Daybook/Schedules/Services/TimetableService+Blocks.swift` (`delete`, `split`, `end`), per Decisions:
    - "Every week" and "This Day and After" also end the copies a split made, following a chain of splits.
    - Read `validUntil` before `end()` changes it.
    - Leave blocks from `replaceWeek` and `copyDay` alone. Add a test that runs `replaceWeek` from a future day and then deletes. This is a notebook-only file.
  - **#17** `AssistantScheduleView.swift`: at accessibility text sizes the stepper shows only the date, as `AssistantAttendanceView+Toolbar.swift:73` does. Check it with a headless screenshot at XXXL (`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`, with the Sample Class launch argument and the Schedule tab).
  - **#19** `Daybook Assistant/Restock/AssistantRestockTile.swift`: format the header inside the menu items, or correct the comment if that isn't possible.
  - **#20** `Daybook Assistant/Wallpaper/AssistantWallpaperPhoto.swift`: `loadIfNeeded()` does nothing while a preload is in flight.
  - Tests in the new files `Daybook Assistant Tests/AssistantFix1106Schedule.swift` and `Cosmic Daybook Tests/…/Fix1106TimetableTests.swift`.
- Cost: $15–30, ~1%.
- Done when:
  - The `Daybook Assistant` scheme builds, and the `Cosmic Daybook` iOS scheme builds.
  - The schedule model and rows suites and the timetable service suites pass with `-only-testing:`, plus the new ones, and each new test fails without its fix.
  - The XXXL screenshot shows the arrows and the Today button clear of the date. Give its path in the final message.
- By hand: none. Device checks go to Tide: the Schedule tab after a night away, and split-then-delete on the Mac.

## Phase 4: Final check, review, push and upload

- Who: phase session (Opus 5.5, high), with one cold-review subagent (`general-purpose`, Opus).
- Needs: 1, 2, 3
- Steps:
  1. On a branch from local main (which holds Phases 1–3), send the combined diff to a cold Opus review. The diff starts at the commit that added this plan. Give the reviewer the report path and ask for real problems only, in at most 20 lines. Fix what holds up, and say in the final message what was rejected and why.
  2. Build the `Daybook Assistant` scheme, and the `Cosmic Daybook` scheme for iOS and for macOS.
  3. Run the whole Assistant suite and the whole notebook iOS suite, on one leased simulator each, with `-parallel-testing-enabled NO`. Fix what fails: the failing files show which phase it came from.
  4. Update the report's status line (`docs/Reviews/Daybook Assistant bug hunt 2026-11-06.md`) to "Fixed on main <date> (<commit>)", with any item left and why.
  5. Merge (close-out, as "Running a phase" says), then **push main** with `git -C "/Users/dannydeberry/Developer/Maria's Notebook" push origin main`, never force. Danny's go-ahead covers this push. If the push is rejected because origin moved, fetch, merge `origin/main` into local main under the merge lock, rebuild the Assistant scheme, and push once more. If that fails, stop.
  6. Upload the Assistant: read `~/.claude/skills/roll-out/SKILL.md` and follow it for the **Daybook Assistant only** (iPhone, `Scripts/archive_assistant_testflight.sh` or the skill's way for the Assistant), from the pushed main. **Add the build to no TestFlight group.** If the upload fails, stop there and add a Tide row under Release in Daybook Assistant's list: "Upload the Assistant build of <commit>".
- Cost: $25–50, 1–2%. It covers the review, one fix round, both whole suites and the upload.
- Done when:
  - The three builds are clean.
  - Both whole suites pass, with counts.
  - Main is pushed.
  - The Assistant build is uploaded, with its build number given (or its Tide row added).
- By hand: none.

## Running a phase (phase sessions read this)
The conductor started you, and Danny accepted this plan and is likely away. Don't ask him anything and don't wait on him. **Don't edit this plan file**: other phases are running beside you, and the conductor writes Progress and Decisions. Put anything you'd add in your final message.

0. Get your session id: run `echo $CLAUDE_CODE_SESSION_ID`. It isn't filled in for you anywhere else.
   - If your phase needs other phases, wait for them first. Run `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/assistant-fixes-1106 --needs <their numbers>` with `run_in_background`, and end your turn. You're woken when it exits.
   - On "Go ahead", carry on. On anything else (a needed phase stopped, the run braked, a time-out), stop. Mark yourself stopped (step 7) unless the run was braked, and report its line.

0b. Make sure your branch starts from local main, which holds every phase merged so far: if `git merge-base --is-ancestor main HEAD` fails, run `git merge main`.

1. Read `Cosmic Daybook/CLAUDE.md` (the project's rules), then your findings in `docs/Reviews/Daybook Assistant bug hunt 2026-11-06.md` and this plan's Decisions. Then do the phase's steps:
   - Build only the phase's smallest targets and run only its `-only-testing:` suites (`~/.claude/CLAUDE.md` › Xcode builds and Simulators). Build through `Scripts/locked_xcodebuild.sh` and take simulators from `~/.claude/bin/sim-lease`.
   - Three phases share the build queue. If a build or test run exits with **75** (the build turn timed out before it started), that isn't a failure: queue it again, with `run_in_background`.
   - Test on simulators headless. Leave tapping, clicking and screen-driving to the conductor, and list what to check under "By hand" in your final message.
   - Don't add files under `Cosmic Daybook/` that the Assistant compiles, and don't touch `Cosmic Daybook.xcodeproj/project.pbxproj`.

2. If a decision comes up that the plan didn't settle, take the safer option that's easier to undo. Add a `Review choices` row in Tide for Danny in the app's list (see Decisions › Tide rows), and put it under "Decided" in your final message.

3. Check every "Done when" item. Before each fix round, run `~/.claude/bin/plan-cost session`. If one item still fails after two tries, or the phase has cost more than twice the top of its estimate, stop.

4. Make every "not verified", "for your review" or "check on a device" item from this phase a Tide row (`add_action`), in the list Decisions › Tide rows names, under Check on a device. Skip ones already there.

5. Update the build board, https://claude.ai/artifact/1xdTk2e14yP7gDuX9sqTus (read the `build-board` skill's section 3 › Helper agents for how). Your steps are the `tasks/p<N>-*` documents, where `<N>` is your phase number: set each one `active` with `startedAt` and `by: "Phase <N>"` when you start it, and `done` with `doneAt` and a one-line `note` of evidence when its check passes. Touch only your own tasks. The conductor owns `status/current` and the milestones. After each write, run `~/.claude/bin/board-touch https://claude.ai/artifact/1xdTk2e14yP7gDuX9sqTus`.

6. Merge: read `~/.claude/skills/close-out/SKILL.md` and follow it (it can't be invoked as a skill). Danny's acceptance of the plan is his go-ahead. Make these changes to it:
   - In its step 2, bring the branch up to date with **local** `main` (`git merge main`), not `origin/main`.
   - Before its step 4, take the merge lock: `~/.claude/bin/plan-merge-lock take "/Users/dannydeberry/Developer/Maria's Notebook"`. Run it with `run_in_background` if it says it's waiting.
   - Right after the squash commit, before releasing the lock, mark the phase merged: `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/assistant-fixes-1106 --mark <N>`. Phases waiting on you start from that.
   - Release the lock with `plan-merge-lock release "/Users/dannydeberry/Developer/Maria's Notebook"` right after the squash commit, and also if you stop before that commit.
   - Skip its step 4b (the conductor keeps the plan's status and the docs map) and its step 5 (no push; Phase 4 pushes, in its own step 5).
   - Wherever it says "stop and ask", stop instead: release the lock, don't merge, and report it.

7. If you stopped without merging, mark it so the phases waiting on you stop too (`plan-wait … --mark <N> --stopped`), and shut down your simulators (`~/.claude/bin/sim-lease --done`). Otherwise close-out releases them.

8. Make this line the first of your final message, so the conductor's note shows it:
   - `Phase <N> done (<commit>). Session <your id from step 0>. By hand: <list or none>.`
   - or `Phase <N> stopped: <plain reason>. Session <id>. Nothing merged.`
   
   Under it, list any "Decided:" items, what each new test pins, and anything that differed from the plan.

## Open questions

None.
