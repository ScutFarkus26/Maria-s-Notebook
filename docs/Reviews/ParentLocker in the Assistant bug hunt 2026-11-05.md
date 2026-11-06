# ParentLocker in the Assistant: bug hunt 2026-11-05

> In short: a read-only hunt over how the Daybook Assistant updates ParentLocker attendance (the shared engine in `Cosmic Daybook/Attendance/ParentLocker/` and the Assistant's screens, Siri and network watch). 25 findings. The top 3 were confirmed by reading the code, and each can leave a class unsent or "not sent" while the line says "up to date". **All 25 are fixed**, and so are all but one of the 25 points from the review of the fixes (W13 is left; R9 is kept by choice). Where each was fixed is below; the commits are on `claude/daybook-parentlocker-attendance-880b8b-unsquashed`.

## Where each was fixed

- **Engine (agent A, 0e4a51a25):** #1, #2, #3, #5, #6, #11, #13 (the sync's second), #14 (the `closeArrivalSendUnsent` flag), #15, #16, #19, #20, #21, #24, and #25's Sign Out cookies.
- **Wire, planner and status (agent B, ddf05e853):** #4, #8, #10, #12, #22, #23, #25's time text, hyphens, apostrophes and problem list, and #7's request timeouts.
- **Assistant (agent C, 7a753f0e5):** #7 (Siri's 8-s answer), #9 (Undo ends at 50 s), #13 (the bar's plain window), #17, #18, and #25's sign-in sheet.
- **Phase 2 (1e702277b):** #14's bar side (a signed-in phone keeps Undo while nothing has gone, up to 50 s, and it can't be tapped mid-send), and the notebook's Undo window losing its extra second (#13).
- **Review of the fixes:** E1–E12, W2, W3 and W4 in 3ca314f7e (tests aa421d766); W1, W5–W8, W10, W11 and W12 in 623ada78f (tests bb4199c8f), with W12's marks list in 591bcf254.
  - **W13 is left.** Two classes with one id and different text periods would need every per-class record keyed by class and period, all through the engine and planner. ParentLocker hasn't been seen to do this.
  - **W5 in part:** only a reply with no script at all reads as "try again later". A maintenance page that carries script still reads as page changed, since telling it from a rewritten attendance page would mean guessing at its words.

Three reviewers each took a slice (the sending engine; the wire, planner and matching; the Assistant side). Every finding was checked against the four earlier reviews (ParentLocker 2026-10-13 morning and afternoon, Assistant 2026-10-20 and 2026-11-03), and none repeats one. Findings 1–3, 4, 7, 8 and 18 were re-read by the main session. The rest are the reviewers' reading.

## High

1. **A failed late-arrival update overwrites the class send waiting to retry, so the class never goes.** `ParentLockerSync+Run.swift:363-368` keeps one slot for today's retry (`retry = next`). Close Arrival & Send fails on bad Wi-Fi, and its retry waits 30 s. Live updates aren't held then (`holdsLiveUpdates` is only true before the first try), so a late mark's update runs 4 s later, fails too, and takes the slot. When the network comes back, only that child goes, and the line says "up to date". Nothing records the day, and `owe()` ignores jobs that aren't whole-class. An Undo then finds no Close Arrival retry to stop (`cancelCloseArrivalSend`). Only the guide's own device's backstop can still send the class. The other day's slot (`otherDayRetry`) has the same overwrite.
2. **A class send waiting to retry isn't kept if the app is closed.** `saveOwed` (`ParentLockerSync+Schedule.swift:240-245`) writes `wholeClass: wholeClass != nil`. While a retry waits, the job sits in `retry` and `wholeClass` is nil, so the next `saveOwed` (any mark) writes "no class owed". Retry waits don't keep the app awake. If iOS ends the app during a 2- or 5-minute wait, or the Assistant rebuilds its stack (`finishParentLockerBeforeRebuild` waits only for a send already going), the class is never sent.
3. **A retry after a lost save reply treats this phone's own save as someone else's, so the day is never recorded.** `childrenToCompare` (`+LastSeen.swift:27-28`) stores the roster from before the save as "last seen". `noteSaved` runs only when a reply comes back. If the save reaches ParentLocker but its reply times out (school Wi-Fi), the retry (`comparesWithLastSeen`) sees every changed child as "changed elsewhere" (`changedElsewhere`, `Matching.swift:184`) and leaves them all to others. `recordsSend` then returns false. The class is in ParentLocker, every device says "not sent", and the 9:00 reminders ring. The guide's backstop ends the same way: with nothing seen, any held mark counts as elsewhere.

## Medium

4. **A class send counts as sent even when some marks couldn't go.** `finish` (`+Run.swift:294-299`) records the day once any child matched. It never checks for children skipped because the school's page no longer has that mark (`noSuchMark`, `unknownMark`). If the school renames its Late code, every late child is skipped, the reminder is withdrawn, and the line reads "up to date".
5. **One class that won't load stops the send for every class.** `sendPlan` (`+Run.swift:243-245`) loads every daily class before planning, and a single roster error throws for the whole run. Match Names (`:224-226`) does the same.
6. **Close Arrival & Send that finds her signed out is dropped.** `failed` → `signedOutHere()` (`+Run.swift:369-370`) clears everything owed. If she signed out on her other phone (the password is in iCloud Keychain, so it goes on both), she sees "Signed out" and signs in, and still nothing goes.
7. **Siri's Close Arrival waits for the whole ParentLocker send.** `AssistantParentLocker.swift:105` awaits `closeArrivalSendNow`, which runs the class list, rosters and saves. Requests use the default 60-s timeout (`ParentLockerHTTP.swift:43`). On slow Wi-Fi Siri gives up with its own error while the send carries on, and the assistant thinks it failed.
8. **The Assistant's bar says "up to date" while children are out of step.** `AssistantParentLockerRow.swift:109` draws the line with `showsProblems: false`, and the line still ends "· up to date" with a checkmark. "Ari is still absent in ParentLocker…" and unmatched children show only inside the menu.
9. **On a phone that isn't signed in, Undo stays for 120 s, but the guide's backstop sends at about 60 s.** `AssistantArrivalBar+Undo.swift:23`. If the guide's send record hasn't synced to her phone yet, an Undo at 90 s clears the absences on her phone only. ParentLocker keeps them, and her phone doesn't say so (Siri's Undo does).
10. **A reason or "Left early at…" replaces the office's or a parent's words in the Notes box.** `ParentLockerPlanner.swift:89-93`. "Mom emailed: strep, back Thu" becomes "Sick". `isAppNote` (`:120`) also clears anyone's note that starts "Left early". This follows the plan's rule, so it's Danny's call.
11. **A day that becomes "sent" only through another device's send record (Send with everyone marked, no Close Arrival) wakes nothing here.** The watcher follows only attendance saves (`ParentLockerWatcher.swift:117`). Changes made here before then wait for the next mark or a return to the app, and the line still offers "Send it to ParentLocker", which would send the class a second time.
12. **A roster child whose attendance is `null` or `[]` gets a save with no ids.** `ParentLockerWire+Roster.swift:24`: `json["attendance"] ?? .object([:])` doesn't catch JSON null. Those children are counted as saved.

## Low

13. Undo and the send are due at the same moment. The bar asks for "a second after the Undo", but `closeArrivalSend` sets both `undoEndsAt` and the send's due time from one value (`ParentLockerSync.swift:311-315`). A tap at that moment reverts the phone and doesn't stop the send.
14. A signed-in phone hides Undo at 7 s even when the send failed and is only waiting to retry (`+Undo.swift:36-40`), though `cancelCloseArrivalSend` could still stop it.
15. The sign-in prompt follows `awaitsSignIn`, which isn't restored after a relaunch (Siri's owed send, a killed app) and isn't cleared when the guide switches to email, so a ParentLocker sign-in can pop up on an email day.
16. "Send to ParentLocker" waiting for a sign-in comes back after a relaunch as an owed send (`loadOwed`, `+Schedule.swift:260`). That is refused before arrival closes, so her Send is dropped.
17. Siri says "Open the Assistant to send it" for every other failure, including ones opening the app won't fix (page changed, refused password, a retry already due in 30 s) (`AssistantParentLocker.swift:109`).
18. Switching from a dead Wi-Fi straight to cellular doesn't retry ParentLocker: `AssistantNetworkWatch` calls `cameBack()` only on no-network → network.
19. The 60-s wait for changes synced in starts once for everyone (`+Changes.swift:58, 115`), so a change synced in at second 59 goes almost at once.
20. The duplicate cleanup's merge reads as this device's own change (`DeduplicationCoordinator.swift:217`), so it skips the 60-s wait and the last-seen check.
21. After iOS ends a background window, `holdsBackground` stays true (`ParentLockerSyncSupport.swift:212`, `+Schedule.swift:173`), so a new send gets no window until the old run ends.
22. Temporary server trouble (408, 429, 404, an HTML maintenance page) reads as "page changed", with no timed retry and "take attendance on the site for now" (`ParentLockerHTTP.swift:167-170, 210-216`).
23. A conflict whose ids can't be read counts as "already equal" (`nil == nil`, `Roster.swift:165`). The save reply's `updated` count is never read.
24. A run that crosses midnight leaves the line on "Sending" (`+Run.swift:33`, `+Report.swift:47`).
25. Smaller: the bar's sign-in sheet can collide with another open sheet and stay stuck (`+ParentLocker.swift:80`); `ForEach(problems, id: \.self)` breaks on two identical problem lines (`ParentLockerStatusLine.swift:27`); "Ben-David" vs "Ben David" don't match (`Matching.swift:133-137`); Sign Out can leave cookies from a reply still in flight; the Left Early time text is locale-dependent (`ParentLockerPlanner.swift:129-131`).

## Checked and sound

With email picked, nothing reaches ParentLocker. Debug and test builds never save. There are no busy loops, and retries stop after 4. Locked rows are never overwritten. Dates go as YYYY-M-D. Cookies and the Keychain allow sending with the phone locked. Taps, Siri and Undo all reach the engine. A rebuild waits for a send under way. The earlier fixes re-traced (10-13 H3/H4/H5/M5, 10-20 #16, 11-03 #1) still hold.

## Review of the fixes (Phase 2, 2026-11-05)

Two cold reviews (Opus, code only) of the combined fixes. Line numbers are from the combined branch at 8723f8abe. **R9 is left as it is:** a signed-in phone's Undo still ends at 50 s while the send waits to retry, since the guide's backstop sends at 60 s.

### The engine (`Cosmic Daybook/Attendance/ParentLocker/`)
- **E1.** `cancelCloseArrivalSend` (`ParentLockerSync.swift:341`) ignores a run under way. An Undo mid-run (Siri's, which has no Undo window) does nothing, `arrivalClosedHere` stays true, and if the run times out its retry sends the reopened class.
- **E2.** `takeDueJob` (`+Schedule.swift:79-82`) runs a pending whole-class retry before the Close Arrival check, with nothing holding it to `closeArrivalNotBefore`. A Send Now retry due 3 s after a new Close Arrival & Send sends the automatic absences inside the Undo window.
- **E3.** Once the retries give up, an owed Close Arrival send (`due` nil) waits for a local change, a return or a sign-in (`+Changes.swift:47-58, 129, 144`, `+Run.swift:234-238`). Changes synced in never release it, and the backstop and deadline checks need `wholeClass == nil`. On the guide's Mac the class and the day's record sit unsent for hours while each imported change goes live and the line says up to date.
- **E4.** `ParentLockerJob.init(retrying:)` (`ParentLockerJob.swift:63-65`, used at `+Changes.swift:215`, `+Schedule.swift:339`) turns a Send Now into `.owed`, which skips the unmarked-children rule in `recordsSend` (`+Run.swift:265`). A Send Now with children unmarked that times out and comes back records the day as sent.
- **E5.** The noted rows (`sending`) aren't saved with what's owed (`+Schedule.swift:263-293`, `+LastSeen.swift:76-85`). A save that landed with its reply lost, then iOS ending the app, comes back with nothing noted: every child reads as changed elsewhere, the day is never recorded, and the line says up to date.
- **E6.** Setting `runningJob` saves nothing (`+Run.swift:30-32`); only `markArrivalClosed` saves, and it returns early when arrival was already closed here. A Send Now later in the day, killed mid-run, is lost.
- **E7.** A class whose roster keeps answering `.refused` makes every run throw after the other classes saved (`+LastSeen.swift:212-216`, `+Run.swift:190`): the whole-class send stays owed, re-runs at every mark, and the day is never recorded.
- **E8.** `owedWholeClass` (`+Report.swift:72-73`) saves a `.backstop` ahead of a pending Close Arrival retry, so after a relaunch Undo no longer stops it.
- **E9.** Another device's Sign Out picked up through `refreshSignIn` (`+SignIn.swift:246-248`, `:222`) keeps the Close Arrival but never sets `awaitsSignIn`, so the Assistant never asks to sign in.
- **E10.** `keepRetry` (`+Run.swift:326-327`) lets a newer live retry replace a pending one whose imported children were already dropped by `forgetImported`, so their changes never go.
- **E11.** `runDue` (`+Schedule.swift:66-72`) doesn't `reschedule` when `takeDueJob` returns nil (a wake just after midnight): `holdsBackground` and `closeArrivalSendUnsent` stay on.
- **E12.** Tests: `closeArrivalUnsentWaitingForSignIn` (`ParentLockerFix1105AStopsTests.swift`) never calls `runDue`; nothing tests an Undo during a run or a retry inside a new Undo window.

### The wire, status and Assistant
- **W1.** Siri's "Undo that" while the send is still going (Siri answered "on its way" at 8 s) reverts the absences with no warning, and the save then lands with them (`AssistantParentLocker.swift:126-128`, `SiriAttendance.swift:396`, with E1).
- **W2.** A later one-child run replaces the status with its own problems only (`+Run.swift:227-238`, `finish`), so "Late marks couldn't go…", unmatched and locked lines vanish and the line says "· up to date".
- **W3.** A one-word note from a parent or the office ("Sick", "Family") reads as the app's own (`ParentLockerPlanner.swift:123, 140`), so an automatic absence with no reason clears it, and a reason replaces it.
- **W4.** The time pattern (`ParentLockerPlanner.swift:130`) accepts a time with no AM/PM ("Left early at 2:15", typed by the office), and misses the app's own older "1:30 pm" / "1:30 p.m." forms.
- **W5.** A 200 maintenance page on the first page load (`courses(on:)`, `ParentLockerHTTP.swift:114-116`) still reads as page changed, with no retry.
- **W6.** Between `takeDueJob` clearing `wholeClass` and the run starting (waiting for `baselineTask`), the bar's Undo can be tapped and does nothing to the send (`AssistantArrivalBar+ParentLocker.swift:22-24`, `+Schedule.swift:87-89, 161-162`).
- **W7.** Siri's "It will try again by itself in a moment" (`AssistantParentLocker.swift:219`) isn't reliable when Siri launched the app in the background, and after a partial run "hasn't gone to ParentLocker yet" is false.
- **W8.** Siri's `default:` answer "Open the Assistant to send it" (`AssistantParentLocker.swift:144, 222`) covers `.idle`, `.refused` and `.keychainTrouble`, where opening the app won't help.
- **W10.** `isExpensive` flipping on the same Wi-Fi (`AssistantNetworkWatch.swift:127, 226-229`) counts as a move, restarting the 20-s import wait each flap.
- **W11.** The sign-in sheet's check for another sheet (`AssistantArrivalBar+ParentLocker.swift:112-117`) looks only at the key window, which may not exist yet as the app becomes active.
- **W12.** `listValue` (`ParentLockerWire.swift:78-86`, used at `+Roster.swift:118`) treats any object as a PHP keyed list, so a single-object `students` reads as an empty roster ("isn't matched") instead of page changed.
- **W13.** Two courses with one id and text periods "A" and "B" are both kept (`ParentLockerWire.swift:260`), but per-class state is keyed by course id alone.
