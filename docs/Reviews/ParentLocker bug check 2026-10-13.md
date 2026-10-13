# ParentLocker bug check 2026-10-13

> **Done 2026-10-13.** Read-only check of the ParentLocker work on main (55117e19, the diff from 043cdd7b), asked for by Danny ("After this is pushed to main I'd like a final bug check on the latest changes").
> In short: four Opus reviewers, split by area, found 19 distinct bugs. None of them repeats the 12 the Phase 5 review found and fixed. The fixes are in <../Plans/Plan - ParentLocker bug check fixes.md>.

**How it was checked:** each reviewer read its area's code against the plan's Decisions and `docs/Technical notes/PARENTLOCKER.md`. The main session checked findings against the code: B1 and C1 by reading it, and A1 against the live site, read-only in the browser pane. On 2026-10-13, `newattendance.php?date=2026-10-9` carried that day's own report ids (5842820 and 5842824, against today's 5902205 and 5902217); report ids are strings; a day nobody has taken yet already has one, with status `not_submitted`; and a future date shows today's. Every other finding is taken as confirmed by its reviewer's file:line and scenario, and each fix starts with a test that fails.

Severity: **High** means a day or a child can go wrong or unsent with nothing said, or an account can be locked. **Medium** means wrong but visible, or a narrow window. **Low** means rare or cosmetic.

## A. Requests, matching, sign-in (engine)

1. **High: a past day saves under today's report id.** `courses()` always loads the page with no date (`ParentLockerSync+Run.swift:168`, `ParentLockerWire.swift:193`). Send Now or MCP for Oct 9 would save that day's marks against today's report. Fix: load `newattendance.php?date=YYYY-M-D` for a day other than today, and take that day's report ids.
2. **High: one ParentLocker child matched to two notebook children.** `ParentLockerPlanner+Matching.swift:32-43`, `ParentLockerPlanner.swift:216-219`, `ParentLockerMatchView.swift:81-87`; the same as C4. Two stored matches pointing at one child (picked twice in Match Names, or a duplicated student record) send one child's mark onto the other with nothing said. And "Not matched" can't undo a name match: the next send matches by name again. Fix:
   - A stored id held by two children makes both ambiguous.
   - Picking a child in Match Names clears that pick from whoever else held it.
   - An explicit "not matched" value that name matching never overrides.
3. **Medium: Cancel during the final check still signs in.** `ParentLockerSignInSheet.swift:196-199`, `ParentLockerSync.swift:258-268`. Cancelling while the class list loads still saves the synced password. Fix: check for cancellation after `courses()` and before `savePassword`; on cancel, delete the cookies and stop.
4. **Low: the report id isn't sent back as it came.** `ParentLockerWire.swift:193`, `ParentLockerHTTP.swift:103`. It's stored as a string, and a null becomes `""`. Live ids are strings and always set, so today this only matters if the site changes. Fix: keep the raw JSON value and send it back as is; refuse a missing one.
5. **Low (unconfirmed): `{"error": 1}` reads as success, and `{"error": []}` as a failure.** `ParentLockerWire+Roster.swift:123-131`. The save reply has never been seen live. Fix: treat a non-zero number as an error, and an empty array or object as no error.

## B. When and what gets sent (engine)

1. **High: Close Arrival & Send is cancelled when its absences change.** "After" comes only from the automatic absences (`ParentLockerStore.swift:29,128`), so marking the last child Late inside the Undo window, or during a retry, refuses the send ("Arrival was reopened") and drops every later change too (`ParentLockerSync+Run.swift:65-73`). Fix: keep a lasting "arrival closed today" per day in `ParentLockerUnsent` (only Undo clears it), and count a started ParentLocker send as "after".
2. **High: a refused saved password is retried again and again.** `ParentLockerSync+Run.swift:113-141,345-347`. Every change and every return signs in again with the same wrong password, on every device, and the school's site may lock the account. Fix: remember the refusal (say, the password item's modification date) and don't sign in by itself again until a new password is saved.
3. **Medium: a refused backstop blocks the guide's backstops for the rest of the day.** `ParentLockerSync+Changes.swift:58-61,73`. Fix: set `backstopDay` only when a backstop actually sends.
4. **Medium: the first synced-in change after a launch never sends.** `lastSeen` starts empty (`Changes.swift:36`, `ParentLockerPlanner+Matching.swift:128-130`). Fix: when an imported change has no baseline, load the class lists read-only first, and fill `lastSeen` from them.
5. **Medium: signing in can send before Close Arrival's Undo has passed.** `ParentLockerSync.swift:271`, `Changes.swift:136`. Fix: keep when Undo ends on the whole-class job, and send no earlier.
6. **Medium: the guide's 60-s backstop can overwrite newer marks and record the day twice.** `ParentLockerSync+Run.swift:287-290`. Fix: run the backstop through the `lastSeen` check, and record a send only if none is recorded yet (see D3).
7. **Medium: the iPhone's background-task window can leak.** `ParentLockerSync.swift:185-191`, `ParentLockerSyncSupport.swift:138-141`, `+Schedule.swift:106`. Fix: `stop()` and `deinit` end the background work, and a stopped sync schedules nothing.

## C. The notebook's screens and MCP

1. **High: the screen and the sync can disagree on the method.** The attendance screen reads the synced preference (`AttendanceExpandedView+ParentLocker.swift:12`). The sync, the reminder, MCP and the assistants read the shared row, which is written only 1.5 s after a Settings edit, and never if Settings closes first (`AttendanceEmail.swift:142,160`). Pick ParentLocker and tap Back at once, and Close Arrival & Send sends nothing, with nothing said. Fix: the screen reads `AttendanceEmailLog.settings(in:)?.sendMethod`. A method or site change is written to the shared row at once, in a task that outlives the view, and again when Settings closes.
2. **Medium: Send Now, Mark as Sent and MCP work on future days.** `+Controls.swift:85`, `+ActionBars.swift:81`, `MCPNotebookTools+SchoolAttendance.swift:48`, `ParentLockerSync+Run.swift:63`. Sending tomorrow makes tomorrow "after" from midnight, so live updates start before arrival closes. Fix: refuse a day after today in the engine and in `recordFrontDeskSend`, and hide the items on a future day.
3. **Medium: a send for another day shows as today's status.** `ParentLockerSync+Run.swift:304`, `+ParentLocker.swift:32`. Fix: only today's jobs update `status`; other days report through the toast and the MCP reply.
4. Same as A2.

## D. The Daybook Assistant

1. **High: Siri's Close Arrival on a phone that isn't signed in leaves nothing waiting to send.** `Daybook Assistant/FrontDesk/AssistantParentLocker.swift:70-71`. Signing in later sends nothing, and neither does a cold launch where there is no sync yet. Fix: queue the whole-class send (`closeArrivalSend(on:after: 0)`) even when not signed in; with no sync, save the owed send so it loads at launch.
2. **Medium: on a phone that isn't signed in, Close Arrival & Send's Undo vanishes behind the sign-in sheet.** `Daybook Assistant/Attendance/AssistantArrivalBar.swift:151-158,321,327`. Fix: only a signed-in phone's Undo times out, and the sheet opens after the Undo window.
3. **Medium: each whole-class send records a new send, so an on-time day later reads "(late)".** `ParentLockerSync+Run.swift:286-291`. Fix: record only when nothing is recorded yet, whatever the job's reason.
4. **Low: Siri checks the wrong Sample Class flag.** `AssistantParentLocker.swift:68`. Fix: check `AssistantSampleClass.isRequested`, not `isActive`.

## Checked and sound

- **Requests:** the JSON content type, `YYYY-M-D` dates in the school's time zone, and ids compared as strings.
- **Redirects:** refused, with their cookies kept.
- **Cookies:** domain and path matching, expiry, and comma-joined `Set-Cookie`.
- **Keychain:** all its attributes.
- **The password:** passed only as an argument; the store isn't persistent.
- **Logs:** counts and statuses only.
- **Duplicates:** the dedup winner is the record read.
- **Saving:** Debug builds and test runs never save.
- **The Sample Class:** excluded.
- **Send records:** go to the right store for the role.
- **Backup v40:** v39 defaults and merge, and dedup copying `parentLockerID`.
- **The MCP tool:** its annotation, preview and save policy.
- **iOS 18 floor:** no newer API is used without a check.
- **The email path:** unchanged.
- **Older builds:** neither side overwrites the other's schema-18 fields.
