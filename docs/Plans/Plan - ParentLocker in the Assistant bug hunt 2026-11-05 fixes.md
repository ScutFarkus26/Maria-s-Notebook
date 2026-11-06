# ParentLocker in the Assistant: fixes from the 2026-11-05 bug hunt

> **Done 2026-11-06** (183ce64d9). Written 2026-11-05 from <../Reviews/ParentLocker in the Assistant bug hunt 2026-11-05.md>, with Danny's answers to four questions and an Opus plan review (13 points, all taken).
> In short: fix all 25 findings in how the Assistant (and the notebook, through the shared engine) updates ParentLocker attendance, so a class on bad Wi-Fi always goes and is recorded, then land on main and, once schema 24 is in CloudKit Production, send both apps to TestFlight.

## Goal

On weak school Wi-Fi, Close Arrival & Send always reaches ParentLocker in the end. A late arrival, iOS closing the app, or a lost reply can no longer stop it. Once it lands, every device reads it as sent. The line never says "up to date" while a child is out of step. An Undo always means nothing went. Siri answers within seconds. A parent's or the office's words in ParentLocker's Notes box stay. Both apps are on TestFlight, and the Assistant is in the Assistants group.

## Progress
- [x] Phase 1: Three fix agents at once in their own worktrees: A engine ‖ B wire and status ‖ C Assistant (session: here) · est. ~6–10% weekly · started at 47% · cost ~2% (47→49; A 161k, B 254k, C 220k tokens). Each committed failing tests first, then fixes; nothing pushed.
  - **A** `worktree-agent-a372498f2285393e9` (9696c461c, 0e4a51a25): 26 files. The notebook builds for iOS and the Assistant for the SE. 207 tests in 25 notebook suites and 41 in 5 Assistant suites pass. Nine older tests were rewritten for #13's extra second. Beyond the plan: the live-update hold applies only while a whole-class send has a due time or its retry waits; any save of the guide's settings refreshes the line; a hidden sign-in's cookies are guarded against Sign Out; a hidden sign-in ending cancelled counts as "needs you"; a computed `importedDue` is kept for an older test. **For Phase 2:** the notebook's `AttendanceExpandedView` already adds a second to its Undo window, so drop it as C did in the Assistant, or the send goes ~2 s after the toast.
  - **B** `worktree-agent-a0a59753e77a3e67f` (09e063112, ddf05e853): 9 files. Both apps build. 177 tests in 21 suites pass, and 15 of the 16 new ones failed before the fix. No older tests needed rewriting. It added `ParentLockerPlanner.noteToWrite(_:over:)`. Beyond the plan: `isAppNote` also accepts the time forms earlier builds wrote (a narrow space, 24-hour); only JSON requests read a non-JSON reply as unreachable. Wording: "· some children need a look".
  - **C** `worktree-agent-a47185fe10b47b1f3` (4028eddf8, 7a753f0e5): 12 files. The Assistant builds. 114 tests in the touched suites pass. Four older tests were rewritten (the Undo limit, two of Siri's answers, a Wi-Fi to cellular move). Beyond the plan: `isExpensive` also counts as a network move (a phone hotspot). **Not checked:** the sign-in waiting while another sheet is up has no device check yet (a Phase 3 Tide row). The bar's menu now lists problems by position.
- [x] Phase 2: Combine, #14's bar side, full builds, whole suites, two cold reviews, their fixes, squash to main (session: fresh) · est. ~4–6% weekly · started at 49% · cost ~2% (49→51; the two reviewers 230k each, the fix agents 370k and 196k tokens)
  - **Combined** A, B and C with no conflicts. #14's bar side (1e702277b): a signed-in phone keeps Close Arrival & Send's Undo while nothing has gone, up to the 50-s limit (the guide's backstop sends at 60 s, signed in or not), and Undo can't be tapped while a send is under way. The notebook's Undo window lost its extra second.
  - **Two cold reviews** (engine; wire, status and Assistant) found 25 more points, written up under "Review of the fixes" in the review file. Danny asked mid-phase to finish autonomously with sessions; sessions can't be started from a Remote Control turn, so two `feature-phase-deep` agents fixed them instead: the engine half (E1–E12, W2–W4, 3ca314f7e) and the Assistant, Siri and wire half (W1, W5–W8, W10–W12, 623ada78f). A new `closeArrivalSendUnderWay` flag lets the bar and Siri refuse Undo while a send can still land; Siri's Undo waits up to 8 s for it. Who wrote a Notes box now comes from what this device last wrote, not the words. The main session tightened W12 (591bcf254): marks in a shape it can't read are "page changed", not "no marks".
  - **Left:** W13 (two classes with one id and text periods; needs per-class keys through the engine, never seen from ParentLocker). W5 in part (a maintenance page with script still reads as page changed). R9 kept by choice.
  - **Landed:** squashed to main as 183ce64d9 (pushed); the history is on `claude/daybook-parentlocker-attendance-880b8b-unsquashed`.
  - **Checked:** four builds clean (notebook iOS and macOS, Assistant Debug and Release; the only warnings are older type-check timings and one 11-03 Release warning in `AssistantSampleClass.swift`). Whole suites: notebook **4,798 tests in 787 suites**, Assistant **614 tests in 86 suites**, all passing. Nothing checked on a device yet (Phase 3's Tide rows).
  - **Board:** not updated; the board is in Danny's other claude.ai organization and this session can't reach it. The plan's `/close-out` step isn't available here, so its parts were done by hand.
- [x] Phase 3: Roll out both apps, the Assistant into the Assistants group, once schema 24 is in CloudKit Production (session: same as Phase 2) · est. ~1–2% weekly · started at 51% · cost ~1% (51→52)
  - **Schema 24:** the signed-in simulator used for earlier `-InitializeCloudKitSchema` runs is gone, and a Mac Debug run is ruled out, so with Danny's OK the field was added by hand in the CloudKit Console's Development schema (`CD_WorkCheckIn.CD_durationMinutes`, Int(64), as Core Data maps an Integer 16) and deployed to Production. The deploy's diff against Production was that one line. Its Queryable/Sortable indexes were left off (sync never queries on it; they can be added later). Tide's Release row is ticked.
  - **Uploads from origin/main 8a28e082e:** Cosmic Daybook 1.1 (300000000039) for iPhone/iPad and Mac, processed, internal group only; Daybook Assistant 1.1 (032) in the **Assistants** group with the approved What to Test note, status Testing (3 invites).
  - The roll-out page and the build board are in Danny's other claude.ai organization and weren't updated from here. Device checks: the five Tide rows above.

## Device checks (in Tide)
- [A late arrival after Close Arrival & Send on school Wi-Fi still lands and reads as sent](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=On%20my%20assistant%27s%20phone%20on%20school%20Wi-Fi%2C%20do%20Close%20Arrival%20%26%20Send%2C%20then%20mark%20a%20late%20arrival%2C%20and%20check%20the%20class%20lands%20in%20ParentLocker%20and%20reads%20as%20sent%20on%20every%20device>)
- [A parent's note in the Notes box stays](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Check%20a%20parent%27s%20note%20in%20ParentLocker%27s%20Notes%20box%20is%20still%20there%20after%20the%20Assistant%20sends%20attendance>)
- [A send still finishes after the phone is locked again](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Lock%20my%20assistant%27s%20phone%20while%20a%20ParentLocker%20send%20is%20going%2C%20and%20check%20it%20still%20finishes%20after%20the%20phone%20is%20locked%20again%20later>)
- [A signed-in phone's Undo while the send waits, and Siri's Undo mid-send](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=With%20Wi-Fi%20off%20on%20my%20assistant%27s%20signed-in%20phone%2C%20do%20Close%20Arrival%20%26%20Send%2C%20and%20check%20Undo%20stays%20up%20to%2050%20seconds%20and%20can%27t%20be%20tapped%20while%20it%27s%20sending>)
- [The sign-in waits for another sheet to close](<tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Have%20another%20sheet%20open%20on%20my%20assistant%27s%20phone%20when%20the%20Assistant%20wants%20a%20ParentLocker%20sign-in%2C%20and%20check%20the%20sign-in%20opens%20once%20that%20sheet%20closes>)

## Cost

About **12–18%** of the weekly all-models limit (Ultra plan). At writing, 47% is used and 53% is left until **Fri Nov 6, 12 PM EST**. **Fits.**
- Recent deep and feature agents ran 150–300k tokens, about 1–2.5% each (cost log, 2026-11-03 and 11-04).
- That gives A (xhigh, the most findings) ~3–5%, and B and C ~1.5–2.5% each.
- Phase 2 is sized from the log's lesson: the fix round costs about 40% of the wave, with two reviewers.
- The three agents at once fit inside one 5-hour window.

## Decisions

**Danny's answers (2026-11-05):**
- **Notes box (#10): leave theirs alone.**
  - The app writes its note ("Sick", "Left early at 1:30 PM") only when the box is empty or holds the app's own earlier note.
  - It never replaces or clears someone else's words.
- **Late Undo (#9): Undo ends before the guide's device sends.**
  - On a phone that isn't signed in, Undo goes at 50 s. The guide's backstop stays at `ParentLockerSync.backstopWait` (60 s).
  - The test that pins the opposite, `AssistantArrivalUndoTests.swift:48` (`unsentUndoLimit > backstopWait`), is rewritten to pin `<`.
- **Scope: all 25 findings.**
- **Roll-out:**
  - Upload both apps. Add the Assistant's build to the **Assistants** group with the "What to Test" note in Phase 3. The notebook is upload only, no group.
  - Main already carries schema 24, which isn't in CloudKit Production yet (Simplify round two; the Release row in Tide). Phase 3 waits for it.

**Rules for the agents:**
- **Who owns which files.** The three agents never share a file. Where a finding spans owners, it's split below. #14's bar side is done in Phase 2, since it reads a flag A adds.
- **No new engine source files.** The engine files are listed by hand in the Assistant target in `project.pbxproj`, so a new file would conflict. New code goes into the owner's existing files. New test files are fine; check that they're in the test target.
- **Tests first.** Each agent commits failing tests for its findings, then the fixes.
- **Older pinned tests.** One that pins the opposite of a decision in this plan is rewritten, and the reply names it. These are known so far:
  - #9's Undo limit.
  - #10's comment replacement (`ParentLockerPlannerTests`).
  - Any test pinning "a backstop leaves the record to others" stays as it is, because #3 keeps that rule.
  - For anything else this plan didn't decide, the old test wins, and the agent says so.
- **Never** run a Debug build that opens the live notebook on the Mac. Tests run on simulators from `sim-lease`.
- **No schema change** and no backup format change in this plan.

**How each finding is fixed:**
- **#1, a live update replacing the class retry (A).**
  - While today's whole-class send is owed, running or waiting to retry, live updates wait. The class send covers them, and this device's own changes stay owed until a send succeeds.
  - Held changes don't count toward the background hold (`updateBackgroundHold`, `+Schedule.swift:167`), so the app isn't kept awake through a 5-minute wait.
  - A failing Send Now during a Close Arrival retry keeps the retry's Close Arrival reason, so Undo can still stop it (`cancelCloseArrivalSend`).
  - Another day's retries are kept one per day, so they can't replace each other.
- **#2, keeping what's owed (A).** `saveOwed` writes the whole class as owed in three cases: while it waits (`wholeClass`), while its retry waits (`retry`), and **while it runs** (a mark during the run would otherwise write "no class owed"). It writes the reason with it.
  - `ParentLockerUnsent` gets an optional `reason`. Old saved data decodes without it.
  - `loadOwed` brings a Send Now back as a Send Now (#16), and brings back `awaitsSignIn` (#15).
- **#3, the lost reply (A).**
  - Before each save, the sync notes the row it's sending for each child (`noteSending`, beside `noteSaved`).
  - A later run treats a child whose ParentLocker row matches **this device's own noted row** as saved by this device: up to date, not "left to others". The comparison reuses the planner's same-mark check, so a box that kept a parent's words (#10) still matches.
  - "Would send" alone doesn't count. A guide's backstop that finds the class saved by someone else still leaves the record to them (`recordsSend`, `+Run.swift:305-311`).
- **#4, marks the page doesn't have (B).**
  - The day is still recorded when the class went, since nothing the assistant can do clears a missing mark type. Otherwise the reminders would ring all day.
  - The status keeps a standing problem line in plain English, with its words in `ParentLockerStatus.swift:214-226`. For example: "Late marks couldn't go: ParentLocker has no Late mark right now. Mark those children on the ParentLocker site."
- **#8, "up to date" (B).** Whenever the status has problems, the line doesn't say "up to date", in either form ("Up to date in ParentLocker" and "· up to date"). The symbol is the warning one. This covers the notebook too, and it covers #4.
- **#5, one class that won't load (A, with B's error rule).**
  - A class is skipped only for a per-class unreachable or refused error; the other classes still save. `signedOut` still throws, so `withTransport` signs in again, and so does `pageChanged`.
  - The run then counts as unfinished: not recorded, and retried. With #3 in, the classes already saved come back up to date.
  - Match Names and the read in `+LastSeen.swift:113` get the same rule. `ParentLockerMatchView.swift` lists the class it couldn't read (A owns it).
  - **The error rule A and B share:** after #22, `ParentLockerError.unreachable` means "try again later". A skips per class on it and on `.refused`, and on nothing else.
- **#6, signed out (A).** A Close Arrival & Send that finds no sign-in stays owed and waits for one. Undo still stops it, and the backstop still covers it. Other owed changes still clear on Sign Out.
- **#7, Siri (C, with B's timeouts).**
  - Siri waits **at most 8 s** for the send, then answers "Arrival is closed. Attendance is on its way to ParentLocker." The send keeps going.
  - The wait mustn't cancel or race-cancel the run. `run` awaits an unstructured task, so a task-group race won't return early, and cancelling would stop the send. Use a separate wait that ends on the run's finish or a sleep, whichever comes first, and leaves the run alone.
  - The done-test shows the send finishing and the day recorded after Siri answered.
  - B sets the session's timeouts (Apple guidance).
- **#13, Undo and the send due together (A, C).**
  - A makes the send due one second after `undoEndsAt` when the window isn't zero: in `closeArrivalSend` and at `+Changes.swift:291` (`due = max(moment, undoEndsAt)`). Siri passes 0 and goes at once.
  - C drops the bar's own `+ 1` (`AssistantArrivalBar.swift:356`), so the bar passes the plain window.
- **#14, Undo while nothing went (A flag, Phase 2 bar).**
  - A adds `closeArrivalSendUnsent: Bool` to the sync. It's true while today's Close Arrival send is owed, waiting, retrying or waiting for a sign-in, and none of its batches has reached ParentLocker. It turns false at the first batch saved, so a partial save (#3, #5, batch 2 failing) counts as gone.
  - In Phase 2, the bar (`AssistantArrivalBar+Undo.swift`, `afterUndoWindow`) keeps Undo on a signed-in phone while that flag is true.
- **#20, the duplicate cleanup's merges (A).**
  - `DeduplicationCoordinator` keeps the app's author on purpose: another author would bring back the loop its comment describes (`:211-217`).
  - Instead it names its context (`context.name`), and `ParentLockerWatcher` skips saves from that context.
- **#23.** The save reply's `updated` count is only logged; what it means isn't known. A conflict whose ids can't be read counts as a real conflict.
- **The other findings** follow the review's description, with owners below.

**Ruled out:**
- Clearing a mark in ParentLocker on Undo: the site can't.
- Acting on `updated: 0`.
- Not recording the day for #4: the reminders would ring all day with no way to clear them.
- A different author for the duplicate cleanup (#20).
- `BGContinuedProcessingTask` and `LongRunningIntent`: see Apple guidance.

## Apple guidance

Checked 2026-11-05 against the installed Xcode 27.2 (27B52) and the iOS/macOS 27.2 SDKs by `sdk-verifier`. Most of Apple's pages were last updated on 8 Oct 2026. The Xcode 27.3 beta (3 Nov) changes nothing here, so there's no need to update first.
- **URLSession timeouts (B, #7).**
  - `timeoutIntervalForRequest` is an idle timer that resets whenever data arrives (default 60 s). `timeoutIntervalForResource` caps the whole request (default 7 days), so set it for an interactive POST.
  - Apple says not to use short timeouts ([timeoutInterval](https://developer.apple.com/documentation/foundation/urlrequest/timeoutinterval)).
  - **Decided:** 20 s per request and 45 s per resource on `ParentLockerHTTP`'s session.
  - `waitsForConnectivity` covers only the connection, not a drop mid-request, so the engine's own retries stay.
  - **Gotcha:** Apple doesn't say whether a timed-out POST can still reach the server. Assume it can; that's #3's fix.
- **Background time (A, #21).**
  - Each `beginBackgroundTask(withName:expirationHandler:)` is balanced by `endBackgroundTask`. It returns `.invalid` when background running isn't possible, and its handler is main-actor ([docs](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(withname:expirationhandler:))). Begin before the work, not at backgrounding.
  - Whether a new task can begin after one expired isn't documented. Handle `.invalid`, and check it on a device (a Tide row).
  - `BGContinuedProcessingTask` (iOS 26+) must start from a tap and shows a Live Activity. It's ruled out: it would need `#available` in the iOS 18 Assistant, and it doesn't fit automatic sends.
- **Siri and App Intents (C, #7).**
  - An intent gets about 30 s before it can be cancelled, from Siri or any system surface ([IntentCancellationReason.timeout](https://developer.apple.com/documentation/appintents/intentcancellationreason/timeout); WWDC26 345).
  - There's no documented "answer early, keep working" pattern. `LongRunningIntent` is iOS 27 only, so the Assistant can't use it.
  - **Decided:** an 8-s cap, then answer. `openAppWhenRun` and `ForegroundContinuableIntent` are deprecated (iOS 26), so don't add them.
- **NWPathMonitor (C, #18).**
  - A Wi-Fi ↔ cellular switch shows as a change in `usesInterfaceType(.wifi)` / `.cellular`, or in `isExpensive`, between two satisfied paths ([NWPathMonitor](https://developer.apple.com/documentation/network/nwpathmonitor)).
  - Setting `currentPath` is deprecated (iOS 17).
  - Apple says little more. Tech Talk 111378 advises against pinning requests to an interface.

## Phase 1: Three fix agents

- **Who:** the main session launches three agents in one message with `isolation: "worktree"`, from pushed main `bc7111c8b`. That equals this branch apart from the two new docs, so briefs give their **absolute paths** in this worktree.
  - **A:** `feature-phase-deep` (Opus xhigh): sync, persistence and races, where a subtle slip loses a class.
  - **B:** `feature-phase` (Opus high): parsing, matching, wording.
  - **C:** `feature-phase` (Opus high): Assistant screens, Siri, the network watch.
- **Every brief includes:**
  - the absolute paths of this plan (its Decisions and the agent's section) and of the review file;
  - "tests first", the pinned-test rule and "no new engine source files";
  - the return format: at most 15 lines, with files, build and test results with counts, and anything decided differently.
- **Builds and simulators:**
  - Builds go through `Scripts/locked_xcodebuild.sh` with the worktree prefix-mapping settings (`Cosmic Daybook/CLAUDE.md`).
  - Notebook tests run on the leased iPhone 17. Assistant tests run on the iPhone SE leased with `--os 26.5`.
  - Each agent runs `~/.claude/bin/sim-lease --done` before replying.

### A: the sync engine
- **Files (only these):**
  - In `Cosmic Daybook/Attendance/ParentLocker/`: `ParentLockerSync.swift`, `+Run`, `+Schedule`, `+Changes`, `+LastSeen`, `+Report`, `+SignIn`, `ParentLockerSyncSupport.swift`, `ParentLockerWatcher.swift`, `ParentLockerJob.swift`, `ParentLockerMatchView.swift`.
  - `Cosmic Daybook/Services/Sync/DeduplicationCoordinator.swift` (only `context.name`).
  - Tests in new files `Cosmic Daybook Tests/Attendance/ParentLocker/ParentLockerFix1105A*.swift`, and existing tests it must rewrite.
- **Findings:**
  - #1, #2, #3, #5, #6, #11, #13 (engine side), the #14 flag, #15, #16, #19, #20, #21, #24.
  - #25's Sign Out cookies: a reply landing after Sign Out mustn't save cookies.
  - The engine review's leftovers: `completeSignIn` loads today's marks, and a hidden sign-in ending `.cancelled` sets `signInNeedsYou`.
- **Also:**
  - **#11:** the watcher also follows send-record imports, which refresh the status and release changes waiting for "after".
  - **#19:** each child synced in waits its own 60 s.
  - **#21:** the expiry handler clears `holdsBackground`, and a `.invalid` begin is handled.
  - **#24:** a run that ends on a new day leaves the status from today's view, not `.sending`.
- **Build:** the `Cosmic Daybook` scheme for iOS (build-for-testing); the `Daybook Assistant` scheme once at the end.
- **Tests:** `-only-testing:` every `ParentLocker*` suite in `Cosmic Daybook Tests/Attendance/ParentLocker/`, `DedupStudentParentLockerTests`, `MCPSendAttendanceToolTests`, and its new suites. Name the enclosing type for nested suites.
- **Done when:** both schemes build with no new warnings, and the suites pass. Each finding has a test that fails without its fix. At least these:
  - #1: a late mark during a whole-class retry still ends with the class sent and recorded, and Undo during that retry still stops it.
  - #2: a mark made during a whole-class run, then a relaunch, still sends the class.
  - #3: a lost reply, then a retry, records the day, and the guide's backstop still leaves another device's send to it.
  - #5: one class's roster failing still saves the other, the day stays unrecorded, and a `signedOut` roster still signs in again.

### B: the wire, planner and status wording
- **Files (only these):**
  - In `Cosmic Daybook/Attendance/ParentLocker/`: `ParentLockerPlanner.swift`, `ParentLockerPlanner+Matching.swift`, `ParentLockerWire+Roster.swift`, `ParentLockerWire.swift`, `ParentLockerHTTP.swift`, `ParentLockerStatus.swift`, `ParentLockerStatusLine.swift`.
  - Tests in new files `ParentLockerFix1105B*.swift`, and the existing tests it must rewrite.
- **Findings:**
  - **#4 and #8:** as decided above.
  - **#10:** the Notes box. `isAppNote` matches only the app's exact formats: a reason's display name, or "Left early at " plus the fixed time format.
  - **#12:** a roster child whose attendance is null or `[]` is skipped with a plain line.
  - **#22:** 408, 429, 5xx, and a non-JSON 200 that isn't the sign-in page, read as `.unreachable`. 404 and a real change of shape stay `.pageChanged`.
  - **#23:** as decided above.
  - **#25, B's part:**
    - the Left Early time in a fixed `en_US_POSIX` "h:mm a" with a plain space;
    - hyphens and curly apostrophes normalized for matching;
    - `ForEach` over problems by offset.
  - **The wire leftovers:** PHP keyed arrays arriving as objects are read as lists; a non-numeric `period` is sent back as it came.
  - **The #7 timeouts** (Apple guidance).
- **Build:** `Cosmic Daybook` for iOS (build-for-testing), and `Daybook Assistant` once at the end, since these files compile into the iOS 18 app.
- **Tests:** `ParentLockerPlannerTests`, `ParentLockerMatchingTests`, `ParentLockerMatchFixesTests`, `ParentLockerHTTPTests`, `ParentLockerHTTPDaysTests`, `ParentLockerPrivacyTests`, `ParentLockerReviewFixesTests`, `AttendanceParentLockerScreenTests`, `AttendanceParentLockerFixRoundScreenTests`, `AttendanceParentLockerAfternoonScreenTests`, and its new suites.
- **Done when:** both builds are clean, the suites pass, and each finding has a test that fails without its fix. These among them:
  - a parent's note is kept;
  - "up to date" never shows with problems.

### C: the Assistant
- **Files (only these):**
  - `Daybook Assistant/Siri/AssistantAttendanceIntents.swift`
  - `Daybook Assistant/FrontDesk/AssistantParentLocker.swift`
  - `Daybook Assistant/FrontDesk/AssistantParentLockerRow.swift`
  - `Daybook Assistant/Attendance/AssistantArrivalBar.swift`, `+ParentLocker.swift`, `+Undo.swift`
  - `Daybook Assistant/Sync/AssistantNetworkWatch.swift`
  - Tests in new files `Daybook Assistant Tests/AssistantFix1105*.swift`, and the tests it must rewrite.
- **Findings:**
  - **#7:** Siri's 8-s wait, as decided above.
  - **#9:** `unsentUndoLimit` = 50 s, with the pinned test rewritten.
  - **#13:** the bar's `+ 1` comes out.
  - **#17:** Siri's answer for each state, in plain English:
    - Page changed: "ParentLocker's page has changed. Take attendance on the ParentLocker site for now."
    - Refused password, signed out, or needs you: "Open the Assistant and sign in to ParentLocker."
    - Retrying: "It will try again by itself in a moment."
    - Up to date with problems: it says some children need a look in the Assistant.
  - **#18:** a switch to another usable network (Wi-Fi ↔ cellular) also calls `cameBack()`.
  - **#25, C's part:** the bar's sign-in sheet waits while another sheet is up, so it can't stick.
- **Build:** the `Daybook Assistant` scheme (build-for-testing) on the SE, `--os 26.5`.
- **Tests:** `AssistantArrivalUndoTests`, `AssistantParentLockerTests`, `AssistantParentLockerFixRoundTests`, `AssistantParentLockerAfternoonTests`, `AssistantSiriCloseArrivalTests`, `AssistantSiriTests`, `AssistantNetworkWatchTests`, `AssistantFix1103FD`, and its new suites.
- **Done when:**
  - the build is clean and the suites pass;
  - each finding has a test that fails without its fix;
  - #7's test shows Siri answering by 8 s while the send finishes afterward and is recorded.

- **Cost:** ~6–10% for the three.
- **Hand off:** no. Phase 2 needs the three branches.

## Phase 2: Combine, check, land

- **Who:** the main session, plus two cold `Plan` reviewers (Opus). One reviews the engine (A's diff); the other reviews the wire, status and Assistant (B's and C's diffs, and the bar change below). Each is given the code, not this plan's conclusions.
- **Steps:**
  1. Start from `claude/daybook-parentlocker-attendance-880b8b` (this plan's branch; a fresh session works on a branch cut from its tip). Merge A, then B, then C (their branches are under Phase 1 in Progress), and read each diff. Also drop the extra second from the notebook's Undo window in `AttendanceExpandedView+ParentLocker.swift` (A's note).
  2. **#14's bar side:** `afterUndoWindow` keeps Undo on a signed-in phone while `closeArrivalSendUnsent`, with a test in `AssistantFix1105*`.
  3. Run four builds: the notebook for iOS, the notebook for macOS (build only, never launched), the Assistant in Debug, and the Assistant in Release.
  4. Run each whole suite once: the notebook on iOS, then the Assistant on the SE. One simulator each, with `-parallel-testing-enabled NO`.
  5. Send the two reviews at once. Fix what holds up, directly if it's small, otherwise with one `feature-phase-deep` agent. Rerun the touched suites.
  6. Mark each finding fixed in the review file, with its commit, and tick this plan.
  7. Squash onto main and push. The unsquashed history stays on `claude/daybook-parentlocker-attendance-880b8b-unsquashed`.
  8. Update the memory note `parentlocker-attendance.md`.
- **Cost:** ~4–6%.
- **Done when:**
  - all four builds are clean;
  - both whole suites pass, with their counts noted here;
  - the reviews' fixes are in;
  - `git log origin/main` shows the squash.
- **Hand off:** no. Phase 3 follows straight on once schema 24 is in Production; otherwise it runs later, from the starter prompt.

## Phase 3: Roll out

- **Before starting:** schema 24 must be deployed to CloudKit Production (round-two Simplify's Release row in Tide). Check that row. If it isn't done, stop and tell Danny, and leave this phase for a fresh session later.
- **Who:** the main session, with the `roll-out` skill.
- **Steps:**
  1. Archive and upload the notebook (iOS and Mac) and the Assistant from main.
  2. Add the **Assistant's** build to the **Assistants** group with this "What to Test" note (approved with the plan): "Attendance to ParentLocker on weak Wi-Fi: after Close Arrival & Send, mark a late arrival, lock the phone, or switch Wi-Fi off and on. The class should still reach ParentLocker, and the line should say so. Undo now ends after 50 seconds when you're not signed in to ParentLocker."
  3. Upload the notebook's build only, with no group.
  4. Add Tide rows in `Areas/App Development/Cosmic Daybook/To do.md` for Danny's checks:
     - on an assistant's phone on school Wi-Fi, Close Arrival & Send followed by a late arrival lands in ParentLocker and reads as sent on every device;
     - a parent's note in ParentLocker's Notes box stays after a send;
     - a send that outlives its background time still finishes after the phone is locked again.
- **Cost:** ~1–2%.
- **Done when:**
  - both uploads are processed in App Store Connect;
  - the Assistant's build is in the Assistants group and in Testing;
  - the Tide rows exist, and this plan links them.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board (https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM), then run `~/.claude/bin/board-touch <url>`.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. The repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets this plan's status line and runs `docs-index`.
7. If the next phase is a fresh session, print its starter prompt. The first line is "Model: Opus 5.5, effort: high". Then: "In /Users/dannydeberry/Developer/Maria's Notebook, read docs/Plans/Plan - ParentLocker in the Assistant bug hunt 2026-11-05 fixes.md and do Phase <N>. Follow its Starting a phase and Ending a phase steps."

## Open questions
- Schema 24 in CloudKit Production gates Phase 3. Danny deploys it himself (his Tide row), unless he allows this session to do it in the browser pane, as he did for schema 18 on 2026-10-12.
