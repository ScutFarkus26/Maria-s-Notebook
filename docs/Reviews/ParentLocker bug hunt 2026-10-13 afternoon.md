# ParentLocker bug hunt 2026-10-13 (afternoon)

> **Done 2026-10-13.** Read-only hunt of the ParentLocker work on main 3ba3c2f8, the whole feature and both rounds of fixes, asked for by Danny ("bug hunt the parentlocker changes") with TestFlight on hold.
> **All 23 fixed** (see <../Plans/Plan - ParentLocker bug hunt afternoon fixes.md>, Progress): by four agents, then a review round that closed 3 partial fixes, the joins between agents and 6 new bugs.
> In short: four Opus reviewers came at it from new angles (a real day across five devices, a fresh line-by-line read of the engine, data and sync, and screens and words). They found 23 distinct bugs, 5 of them high. None repeats the morning's 19 or its 5 follow-ups. Five of them sit in this morning's fixes.

**How it was checked:** each reviewer read the code against `docs/Technical notes/PARENTLOCKER.md`, the plan's Decisions and the earlier reports. The main session confirmed H1 and H3 in the code: Settings' repair writes the preference over the row with no newer-check, and `noteChanges` schedules the backstop before `rollOwedDay` clears it. Three reviewers found H1 on their own, and two found M6. The rest rest on each reviewer's file:line and scenario. Every fix starts with a failing test.

## High

1. **H1. Opening Settings on a device whose iCloud preferences are behind switches the whole class back to email.** `Attendance/Email/AttendanceEmail.swift:175` → `AttendanceEmail+Prefs.swift:97-115`. This morning's C1 repair writes this device's synced preference over the shared row whenever they differ, stamped newest. It happens to the iPad that opens Settings › Messages before iCloud key-value storage has caught up, and to a new device. Every screen, the sync, the reminder, MCP and the assistants go back to email, quietly. Any edit on a lagging device does the same, through `shareNow`. Fix:
   - Repair only a write this device still owes: a local, unsynced "pending" flag, set when an edit's write was skipped and cleared when it saves.
   - Settings' picker and site field read the shared row.
   - A test: the row says ParentLocker, the preference says email, and nothing is written.
2. **H2. Siri's "Undo that" after the Assistant's Siri Close Arrival doesn't stop ParentLocker.** `Daybook Assistant/FrontDesk/AssistantParentLocker.swift:81-86`, `Cosmic Daybook/Siri/SiriAttendance.swift:349-352`. Signed in, the class has already gone and stays "after", so the reopened arrival's marks go live. Not signed in, the queued send and the "arrival closed here" mark survive, and a later sign-in sends a half-taken class. Fix: Siri's undo of a close calls `cancelCloseArrivalSend()` and clears the owed send. When the class has already gone, Siri says ParentLocker keeps those absences.
3. **H3. The guide's backstop is cancelled on the first change of a new day.** `ParentLockerSync+Changes.swift:30-33` runs `considerBackstop` and `considerDeadline` before `rollOwedDay`, which clears the job just scheduled. `backstopDay` stays set, so no backstop runs all day. On the Mac nothing refreshes the line at midnight either, so yesterday's "Up to date" shows. Fix: roll first; watch `.NSCalendarDayChanged` to roll and refresh; add a test that spans a day.
4. **H4. A mark made just before another device closes arrival can be lost.** `+Changes.swift:32` drops changes made before "after", and taking a backstop (`+Schedule.swift:63-68`) clears the imported job, which the refused backstop then throws away. The guide marks G at 8:44:50 and an assistant closes arrival seconds later: ParentLocker keeps G Absent while the Mac shows Present, with nothing flagged. Fix: don't clear imported or local work when taking a backstop; keep changes from before "after" (unscheduled) and send them through the imported/lastSeen route once the day turns "after".
5. **H5. A phone that closed arrival offline sends its stale view when it comes back.** `+Schedule.swift:14,59-62`, `+Changes.swift:120-129,221-226`, `+Run.swift:21,323-327`. Its whole-class retry fires on return before the CloudKit import and compares every child with no lastSeen check. Newer marks (a child marked present on the Mac, a "Sick" note) are overwritten, and a second, late send is recorded. Fix: on return or launch, turn a pending whole-class retry into an owed send released by the catch-up; give retries the backstop's lastSeen rule.

## Medium

6. **M1. The notebook's sign-in sheet covers its own Undo** (the morning's D2, fixed only on the Assistant). `Today/Views/Attendance/AttendanceExpandedView+ParentLocker.swift:66`. Fix: open the sheet once `undoEndsAt` has passed.
7. **M2. "Everyone's marked" tells you to close arrival when there's no Close Arrival to tap.** `ParentLockerStatus.swift:54`, `+Changes.swift:144`, `+FrontDesk.swift:59-63,183-187`. The notebook iPhone has no Send button there, and the reminder tap opens nothing. Fix: "Everyone's marked. Send it to ParentLocker.", the Send button in the iPhone row, and a reminder tap that offers it.
8. **M3. "None of the class's children were found in ParentLocker…" never shows on the notebook.** `+Run.swift:307-312` ends `.idle`, and `ParentLockerStatusLine.swift:17` draws problems only with a line; Send Now's toast is silent too. Fix: draw problems without a line, and toast the first problem.
9. **M4. Send Now runs with children unmarked and records the day as done.** `+ParentLocker.swift:133`, `AssistantParentLockerRow.swift:59`, `SendAttendanceIntent.swift:43-44`. Fix: with anyone unmarked, ask first and name them, and don't record the day. The Shortcut says how many aren't marked.
10. **M5. A synced-in change is dropped when its class-list read fails or is late.** `+Schedule.swift:86-93`, `+Changes.swift:283-296`. Fix: fall back to the mark from before the change; after a failed read, keep the child waiting and retry.
11. **M6. Close Arrival's automatic absence wipes the office's or a parent's note.** `ParentLockerPlanner.swift:86-88` sends `comment: ""`. Fix: send nil (the app's own notes are still cleared through `isAppNote`); update `ParentLockerPlannerTests.swift:91`.
12. **M7. A child matched after the class went never reaches ParentLocker that day.** `ParentLockerMatchView.swift:107-123`; the watcher ignores student saves (`ParentLockerWatcher.swift:84-90`). Fix: after a pick on a day past "after", note the child as a local change.
13. **M8. A day ParentLocker marks "not expected" reads as "no children found" and "23 aren't matched".** `+Run.swift:259,305-309`, `ParentLockerStatus.swift:192-200`. This invites "Not matched" for everyone, and the reminders keep firing. Fix: when every class was skipped, say "ParentLocker isn't expecting attendance today", drop the other two lines, and withdraw the reminder.
14. **M9. "ParentLocker needs you to sign in again" (new terms, a reset) offers no way to sign in, and every change tries again.** `ParentLockerSignIn.swift:36`, `ParentLockerSync.swift:124`, `+Run.swift:155-185`. Fix: a flag set on `.needsYou` and cleared by `completeSignIn`, included in `needsSignIn`, with no automatic sign-in while it's set.

## Low

15. **L1. The Assistant's Send Now for a past day says nothing when it fails.** `AssistantFrontDeskRow.swift:213-218`. Fix: show the message.
16. **L2. The Assistant's sign-in prompt never opens if she locks the phone during the Undo.** `AssistantAttendanceView.swift:246-249`, `AssistantArrivalBar.swift:362`. Fix: tie the prompt to the waiting send plus `needsSignIn`.
17. **L3. Editing the address can sign devices out.** `AttendanceEmail.swift:159-160`, `AttendanceParentLockerSettings.swift:68`. A half-typed host is written after a 1.5-s pause, and Sign In within 1.5 s uses the old host. Fix: write the site only on Return or close, and commit it before the sheet opens.
18. **L4. The Assistant's Classroom row shows "Signed in" after a refused password.** `AssistantParentLockerSection.swift:23-28`. Fix: use `needsSignIn` and "Sign in again".
19. **L5. Siri says "Open the Assistant to send it" after a refused password.** `AssistantParentLocker.swift:81`. Fix: check `needsSignIn` and give the not-signed-in reply.
20. **L6. "Send to ParentLocker" needs a second tap when not signed in.** `+ParentLocker.swift:107-110`, `AssistantParentLockerRow.swift:32`. Fix: queue the send to go after sign-in.
21. **L7. iPhone Settings clips at the largest text sizes** (`AttendanceEmail.swift:57-65`), and the address field is cramped on the SE. Fix: put the label above the control at accessibility sizes.
22. **L8. One retry slot.** `+Run.swift:346`: a failed past-day send replaces today's retry. Fix: keep today's retry separate.
23. **L9. An orange "Couldn't send yet" stays with nothing pending.** `+Changes.swift:146-153`, `+Schedule.swift:239`. Fix: on return with nothing owed, reset to idle.

## Checked and sound

- **Schema 18:** additive, with the version stamp and digest bumped; the old rows read as email; Production has it.
- **Older Assistant builds:** they stop offering the email and ignore the new fields.
- **Backup v40:** reads 17–40; older backups restore with email defaults; the new preference keys are backed up; the password and cookies never are.
- **Duplicates:** dedup copies `parentLockerID`; release keeps matches.
- **Send records:** go to the right store for each role; the Assistant reads only the class share.
- **MCP:** annotations and preview are right, and replies carry no secrets.
- **First launch on the live store:** a lightweight migration, backed up first.
- **The morning's other fixes:** sound.
- **JSON, cookies, Keychain and preference keys:** sound.
- **Observers and retain cycles:** sound.
- **DST:** both 2026 changes fall on Sundays.
- **Scenarios that held up:** a normal day's live updates, the snow day, the locked day, Locked by Admin, a session expiring with the Mac signing back in, and mixed app versions.
