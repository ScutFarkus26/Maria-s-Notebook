# Daybook Assistant bug hunt 2026-11-06

> **Fixed on main 2026-11-07** (e17df4546). All 20 findings: Phase 3 fc13c413f (#14-#20), Phase 1 8b8075a9c (#1-#4, #6, #11-#13), Phase 2 4e7feabc8 (#5, #7-#10), and the final review's fixes e17df4546. Nothing is left. Found at main 616884850 (2026-11-06).
> In short: 20 findings, none a crash or lost data. The worst is Siri's Close Arrival, which on a View-only phone or an empty roll marks no one, says "Everyone was already marked" and puts the whole day into Late. After a Reopen Arrival, it also sends the whole class to ParentLocker again. Three Schedule bugs from the 10-28 hunt are still live.

"Confirmed" means the path was traced end to end in the code. "Plausible" means the path is real, but the trigger depends on timing or data.

## Scope

The whole Daybook Assistant target: `Daybook Assistant/` plus the 150 shared `Cosmic Daybook/` files it compiles. The hunt leaned on what changed since the last whole-target hunt at 19cfecc1. That covers 67 commits: the 11-03 fixes (9038f7525), the ParentLocker fixes (183ce64d9), the view-only fix (616884850), and the changes to Siri attendance and schema 24.

Four Opus reviewers each took one area: the grid, arrival bar and reminders; sync, joining and persistence; the front desk, ParentLocker and Siri; and Restock, Schedule and the app shell. Each read the 10-20, 11-03 and 11-05 reports first, so nothing here repeats them. The ParentLocker engine was hunted yesterday, so only its seams with the Assistant were looked at. This was a code read only. There was no simulator walk.

Checked by hand against the code before this was written: #1, #2, #7 and #15.

**Still sound:** 616884850's view-only rule (every place that decides it now agrees); schema 23/24 handling in the Assistant; the 11-03 fixes for keep-alive, the attacher, the watchdog, the shared `CKContainer` and the reminder queues; the arrival bar's Undo, its 50-second limit and the due-time timer; Restock's saving, needs, office run and history; onboarding, the wallpaper save and the Sample Class's separation. The 10-28 hunt's "stall rebuild every 10 minutes" bug is fixed (`sendsAtStallRebuild`).

## Bugs

### Siri's Close Arrival

1. **Siri's Close Arrival marks no one, says "Everyone was already marked," and still puts the day into Late.** Confirmed, medium.
   - **Where:** `Daybook Assistant/Siri/AssistantSiriCommands.swift:20-26` (`checkClose`) and `:36-49` (`closeArrival`, the empty branch). The store's refusal is at `CDAttendanceStore.swift:393`.
   - **What she sees:** Siri asks "Mark the 3 unmarked children absent?", she says yes, and Siri answers that everyone was already marked. Nobody was marked, but her phone is now in Late for the day. Every child tapped in afterwards is marked late, and that reaches the front desk and ParentLocker.
   - **Triggers:**
     - The phone is View only. `checkClose` never asks whether this phone may write, and `markUnmarkedAbsent` quietly returns nothing. The Late it sets stays after the guide switches her back to "can make changes", which is what happened in today's false alarm.
     - The roll is empty because the class's children haven't arrived from iCloud yet (a fresh join or a rebuilt stack).
   - **Fix:** Refuse in `checkClose` when `!store.roleMayWrite` (with the View-only message) or when the roll is empty. Set Late only when the close marked someone or the roll really was all marked.

2. **Siri's Close Arrival with no one left to mark sends the whole class to ParentLocker again.** Confirmed, medium.
   - **Where:** `Daybook Assistant/FrontDesk/AssistantParentLocker.swift:124-148` (`sendAfterClose`). The bar's rule, `sendsOnClose`, is at `AssistantArrivalBar.swift:375-377`.
   - **What she sees:** She sends the class, reopens arrival to mark one late child, then says "close arrival". Siri re-sends every child as a first Close Arrival & Send and puts back any change the office made in ParentLocker since the first send. The bar doesn't do this; the 10-20 hunt (#6) fixed it there.
   - **Fix:** `sendAfterClose` skips the send when the close marked no one, as the bar does.

3. **Undoing that empty Siri close after a Reopen Arrival leaves the day in Late, while Siri says "Arrival is open again."** Confirmed, low.
   - **Where:** `SiriAttendance.swift:393/399` → `AssistantSiriHost.swift:70-73` → `AttendanceLatePhase.setLate(false)` (`AttendanceLatePhase.swift:146-151`).
   - **Why:** Siri's close cleared the "reopened here" note, and its Undo doesn't put it back. The first close's automatic absences are still on the records, so the day still reads as closed.
   - **Fix:** Undoing a Siri close that marked no one on a reopened day reopens the day again (`AttendanceLatePhase.reopen`).

4. **After a relaunch, Siri's Undo of a half-sent Close Arrival doesn't warn that some absences already reached ParentLocker.** Plausible, low.
   - **Where:** `closeArrivalBatchSent` (`ParentLockerSync.swift:185`) is kept only in memory, and `loadOwed` (`ParentLockerSync+LastSeen.swift:208-224`) starts it at false. Siri's Undo reads it at `SiriAttendance.swift:437, 460-469`.
   - **What she sees:** One class reaches ParentLocker, the next fails and waits to retry, and then iOS ends the app or the stack rebuilds. "Undo that" says only "Arrival is open again", but ParentLocker keeps the first class's absences.
   - **Fix:** Save the flag with what's owed, or work it out from the saved sent rows on load.

### Sync, joining and view only

5. **Marks can sit under the filing hold all session, with "Trying again" on screen and nothing retrying.** Plausible, medium-low.
   - **Where:** `AssistantFilingHold.swift:96` (the hold that stays on, from the 11-03 #2 fix); `AssistantBootstrapper+Rebuild.swift:149-176`; `AssistantBootstrapper+AccountDecision.swift:70-102`.
   - **Why:** Since #2, the hold lifts only when the stack is rebuilt, and the rebuild needs the account check to say `.available`. If that check says "couldn't tell", it is retried only while the join screen can show, never once she's in the class.
   - **Trigger:** The class store's setup fails over an account blip while the account check can't tell yet, for example both right after a restart. She then stays in the app.
   - **Fix:** Keep `retryUnknownAccount` running while `filingHold?.setupFailedForAccount` is true.

6. **A View-only phone still offers Email the Front Desk, Send to ParentLocker and Send Now, and the send record it saves never reaches the class.** Plausible, medium-low.
   - **Where:** `AssistantFrontDesk.swift:95-97` (`isOffered`) and `AssistantParentLocker.swift:17-32` (`offersParentLocker`, `offersParentLockerSend`). The records are written through `ParentLockerStore.swift:237` and `AssistantFrontDesk.recordSend`, with no permission check.
   - **What she sees:** Her phone says "Emailed 8:42 by you" and stops its reminders. Nobody else's device gets the record, so the front desk can get a second email and the guide's devices still ring "attendance is late".
   - **Related:** On a View-only phone, Siri's here/late/absent says "Open the app to mark it", but the app can't mark either (`SiriAttendance.swift:207-209, 546`).
   - **Fix:** Both rows also require `viewModel.canMark`, and Siri gives the View-only message when `!store.roleMayWrite`.

7. **A wrong "view only" saved under the old rule clears only when the share says read-write.** Plausible, low.
   - **Where:** `ClassroomPermissions.swift:31-42` and `ClassroomSharingService.swift:232-237`.
   - **Why:** The old rule cleared view only when the share gave no answer. The new rule keeps the last answer then. If the share isn't found yet, or doesn't say, a phone hit by today's false alarm stays unable to mark.
   - **Fix:** Read the saved answer under a new key (for example `…shareIsViewOnly.v2`), so answers saved by the old rule are dropped.

8. **Leave and a stack rebuild don't wait for each other.** Plausible, low.
   - **Where:** `AssistantBootstrapper+Leave.swift:23-52` has no `isRebuilding` check. The rebuild paths at `+AccountDecision.swift:40` and `+Rebuild.swift:149` ignore `isLeavingHere`; only the stall and mirroring-stop paths respect it.
   - **What she sees:** Leave fails partway with an error and leaves a half-purged class, so she has to Leave again.
   - **Fix:** Leave waits while `isRebuilding`, and every rebuild path treats `isLeavingHere` as "not settled".

9. **A rebuild for a stalled send can close a sheet she opened during the ParentLocker wait.** Confirmed ordering, low.
   - **Where:** `AssistantBootstrapper.swift:299-314`. The `abandon` check (is a sheet up?) runs before `finishParentLockerBeforeRebuild()`, which can wait up to 10 s.
   - **Fix:** Wait for the ParentLocker run before the `abandon` check.

10. **"Can't start" retries only once after the first unlock.** Plausible, low.
    - **Where:** `AssistantApp.swift:36-47` and `AssistantBootstrapper.swift:204-209`.
    - **Why:** If the unlock arrives while the first start is still running, `retryFailedStart` returns early and the listener ends. "Can't start" then stays until the app is killed.
    - **Fix:** Keep listening until a retry actually runs.

### Attendance grid

11. **One child Close Arrival can't mark stops "Mark N Absent & Email" from opening the email, with a false error.** Plausible, medium-low.
    - **Where:** `AssistantAttendanceViewModel.swift:461-469` (`emailCanFollowClose`) and `:478-503`. The cause is in `CDAttendanceStore.swift:193-195, 385-399`.
    - **What she sees:** Arrival closes and the absences save, but the email doesn't open, and she sees "Couldn't mark everyone absent, so the email didn't open. Try again." Trying again does the same.
    - **Triggers:**
      - A student with no id, or a record with a status this build doesn't know. It reads as unmarked, but Close Arrival skips it. The no-id student's tile also does nothing when tapped.
      - Another device marks a child in the second before she confirms. That one clears itself, but the error message stays up.
    - **Fix:** After closing, check what the store holds rather than the grid's rows, and leave out rows Close Arrival can't mark.

12. **Debug Sample Class only: Siri's marks don't show on an open grid.** Confirmed, low.
    - **Where:** `AssistantAttendanceView.swift:221-237`, `AssistantAttendanceViewModel.swift:222-224`, `RemoteImportReloader.swift:104-107`.
    - **Why:** Since 9038f7525, Siri's notice goes through the import listener, which never starts in the sample's one in-memory store. This affects the simulator demo videos.
    - **Fix:** With no shared store, `siriChanged()` calls `load()` directly.

### Siri

13. **Siri looks a child up in both stores, so it can pick the copy that isn't the class's.** Plausible, low.
    - **Where:** `SiriAttendance.swift:108-121`, `context.object(CDStudent.self, id:)` with no store scope.
    - **What she hears:** For a child with a row in both stores, Siri can say the full name aloud on a locked phone, or refuse a current child because the other copy's enrollment dates don't fit.
    - **Fix:** Look the child up in the class's roster (`SiriHost.roster(in:)`), or limit the fetch to the share's store as `AssistantDayRoll.classroomStudents` does.

### Schedule tab

14. **The Schedule tab can open on yesterday after a night away.** Plausible, medium. Still live from 10-28.
    - **Where:** `AssistantScheduleView.swift:106` (`onAppear` only calls `load()`), `:356-375` (`ScheduleFollowsScene`), and `AssistantScheduleModel.swift:115-117`.
    - **Why:** Only the tab's own scene-phase handler moves it to today, and that handler doesn't hear the app return while another tab is showing. This is the same gap the 10-20 hunt (#1) fixed for Attendance.
    - **Fix:** Remember the calendar day she was last here, and call `showToday()` on appear or return when it has changed.

15. **"With Danny" rows show on a day he's out.** Confirmed, medium-low. Still live from 10-28.
    - **Where:** `ScheduleDayResolver.swift:62-64, 175-183` and `AssistantScheduleRows.swift:157-170`.
    - **What she sees:** The header says "Danny is out.", but the list still shows "10:00 With Danny · Maya S, Ari K". The resolver drops only his turns; his booked lessons still go into his lane, and the rows never check `lane.isOut`.
    - **Fix:** Leave out, or mark as out, `.lesson` and `.halfList` rows when the guide's lane is out.

16. **A "This Day and After" split leaves an open-ended copy that a later delete misses.** Confirmed, medium. Still live from 10-28. Written on the Mac, seen on both apps.
    - **Where:** `TimetableService+Blocks.swift:180-200` (`delete`), `:295-324` (`split`) and `:331-348` (`end`).
    - **What happens:** A block is edited "This Day and After" from a future day, then deleted "Every week" while an earlier day is in view. Only the original is ended, so the block comes back from the split day on.
    - **Fix:** These deletes also end any later block of the same lane and weekday that starts right where the original ends.

17. **The Schedule day stepper can cover its arrows at accessibility text sizes.** Plausible, low; needs a device check. Probably still live from 10-28.
    - **Where:** `AssistantScheduleView.swift:147-181`. The label always reads "Today" plus the date, with `.fixedSize()`.
    - **Fix:** Show only the date at accessibility sizes, as `AssistantAttendanceView+Toolbar.swift:73` does.

18. **Past midnight with the Schedule tab open, the stepper still says "Today" with yesterday's date.** Confirmed, low. A side effect of the 11-03 #26 fix.
    - **Where:** `AssistantScheduleView.swift:82, 129, 160` and `AssistantScheduleModel.swift:68`. `isToday` reads the clock, and nothing redraws the view at midnight. The Now card goes blank.
    - **Fix:** At the minute tick in `followClock`, call `showToday()` when the day changed and the tab was on today.

## Waste

19. **The 11-03 #28/#31 Restock menu-header fix saves nothing.** Confirmed.
    - **Where:** `AssistantRestockTile.swift:41, 120, 139`.
    - **Why:** `.contextMenu { menu }` builds its menu on every redraw, so the closure and its date formatting still run on every tile redraw.
    - **Fix:** Format inside the menu's items, or drop the claim from the comment.

20. **The 11-03 #33 wallpaper fix: the main-thread decode it targeted usually still happens.** Plausible.
    - **Where:** `AssistantWallpaperPhoto.swift:59-76`.
    - **Why:** The grid's `onAppear` calls `loadIfNeeded()` before the background preload finishes. It decodes on the main thread and throws the preload away.
    - **Fix:** `loadIfNeeded()` does nothing while a preload is in flight.
