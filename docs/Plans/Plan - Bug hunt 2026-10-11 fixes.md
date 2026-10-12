# Bug hunt 2026-10-11 fixes

> **Done 2026-10-11** (a031f7ab). Not rolled out. Written 2026-10-11 from the read-only hunt in <../Reviews/Bug hunt 2026-10-11.md> (77 findings in the oldest code no earlier hunt had read).
> In short: fix every finding with nine fix agents in rolling waves of at most four, each owning its own files, then review the combined change, fix what the review finds with fresh small agents, and land it on main without rolling out.

**Runs autonomously** (Danny, 2026-10-11): approved to run every phase through landing on main without stopping. Decisions that come up mid-run are made by the main session from Decisions and sensible defaults, and logged under Open questions as "decided during the run" for Danny to read afterward.

## Goal

Every finding in the report is fixed, and the dead code it found is gone. When it's done:
- Every menu item, keyboard shortcut and Siri shortcut does what it says. New Lesson opens the New Lesson sheet. Import Lessons is gone. Tapping a child opens her on every device. A reminder tapped with the app closed lands where it should.
- Records stay right:
  - Project check-in work belongs to its project.
  - A recall check marks only that child.
  - Group meetings stay booked for the children not yet met.
  - Scheduling work doesn't move finished check-ins.
  - Album links stay on the right page.
  - A time set through Claude stays put.
  - Parent reports aren't overwritten.
- The checklist, the Quiet column and the Works log read each child's own copy of shared work, and the checklist's "Not yet" agrees with Presentations.
- Search works on every launch, ranks sensibly and ignores accents.
- The album index can't crash the app.
- Typed text isn't thrown away on a swipe, Cancel or app switch: capture, templates, album notes, calendar notes, project notes and reports.
- Children who left, and hidden test students, stop appearing as current. Children are named "Maya S" wherever two share a first name.

Everything ends on main, built and tested for iOS, Mac and the Assistant. It is not rolled out. Device checks become Tide rows.

Finding numbers (#n) are the report's.

## Progress
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (m1–m3 = the three phases).
- [x] Phase 1: Wave 1 — P Projects, reports & Today ‖ A Albums, lessons & resources ‖ W Work & checklist ‖ M Command bar & MCP (session: here, agents in worktrees) · est. ~5–9% weekly · started at 3% · cost ~5% (3→8%, overlapping Wave 2's start). As planned: all four agents' builds clean, suites pass (M 462, A 165 + 7 skipped, P 226, W 360 tests), new tests failed first; merged into this branch. Differed: Tide rows wait for Phase 3 (no Tide connection in this session); two cross-owner follow-ups from P (WorkDeletionService.removalPlan for Uniform rows; OrderRequestDraftSheet's Mac mail) and one from M (MCP_SERVER.md) go to Phase 3.
- [x] Phase 2: Wave 2 — R App core & navigation ‖ S Students & meetings ‖ Pr Presentations ‖ C Calendar, school year & Siri ‖ Q Search & chat (session: here; each starts as a Wave 1 slot frees, at most four agents at once) · est. ~5–9% weekly · started at 3–8% (R, S, Pr began while Wave 1 ran) · cost ~2% (8→10%, overlapping Phase 3's first reviews). As planned: five agents, builds clean, suites pass (R 82, S 165 + the one MCP test it handed on, Pr 287, C 139, Q 71 tests); merged. Differed: C didn't show its tests failing first (they call API the fix adds; review (c) judged them real); Pr's #25 pill and R's leftovers were cross-owner and done by the main session; Q kept the snapshot format (folds on load) and made the chat tool context per answer.
- [x] Phase 3: Combine, review, fix round, full builds and suites, land on main (session: here) · est. ~5–9% weekly · started at ~8% (merging and review (a) began while Wave 2 ran) · cost ~4% (8→12%). Whole run ~9% (3→12%) against 16–28%. Merged all nine with no conflicts; three Opus reviews found 24 problems ((a) 6, (b) 11, (c) 7): 21 fixed (main session plus four fresh agents), 1 false alarm, 1 known limit, 1 design note in MCP_SERVER.md. Full builds clean (notebook iOS + macOS, Assistant iOS) with no new warnings; whole suites: notebook 3,377 tests in 562 suites, Assistant 309 in 47, all passing. Differed: the device checks went into Tide after the run (listed below); the Go menu's any-window switching was found and left as a separate task.

## Cost

About **16–28%** of the weekly all-models limit on Max, plus ~1% spent planning (the hunt itself cost ~2%). 98% is left (2% used at writing) until **Sun Oct 18, 4 PM EDT**. **Fits** with plenty of room.

Sizes come from the cost log:
- **Fix agents:** this app's fix agents have cost ~1% each (10-09 plan) to ~2% each (10-10 plan, 13 agents ~26%). Nine agents at 1–2% = 9–18%.
- **Reviews:** three Opus reviewers ~2–3%.
- **Fix round:** fresh small agents or the main session ~1–3%. This is the 10-10 lesson: resuming the agent that wrote the code reloads its whole transcript, which cost ~19% there.
- **Final phase:** combining, the full builds and both whole suites ~2–3%.

The 5-hour window was 8% used at writing. Four agents at once, three at xhigh, can take most of a window, which is why waves are capped at four and rolling.

## Decisions

**Danny's answers (2026-10-11):**
- **Import Lessons (#1):** remove every Import Lessons item: File menu ⌘I, the Lessons sidebar row's right-click, and the Lessons header's Add menu. Also remove `AppRouter.requestImportLessons` and `.importLessons`. New Lesson (⌘N, the sidebar, Siri's "Create New Lesson") opens Lessons with its New Lesson sheet, keeping the default area and sequence when given.
- **Group meeting from Today (#27):** tapping a group booking shows a short pick of the booked children. Completing one child's meeting removes only her from the booking; the booking is deleted when nobody is left. Today keeps showing it for the rest. The rule lives in `MeetingScheduler` (`completeBooking` and `clearMeeting`), so meetings Claude files through MCP `create_meeting_entry` follow it too.
- **Landing:** squash to main and push when reviewed and both whole suites pass. Keep the unsquashed history on the local branch `bug-hunt-2026-10-11-fixes-unsquashed`. No roll-out.
- **Dead code:** remove all of it, each item by the agent that owns its file (listed per agent below). Stored Core Data attributes stay in the model (no schema change); only code goes.

**Settled from the code or by default (not Danny's call):**
- **Uniform project work (#65):**
  - `createWork` in `NewProjectSessionSheet.swift` sets `sourceContextType = .projectSession` beside `sourceContextID`.
  - A one-time repair stamps the type on existing works whose `sourceContextType` is empty and whose `sourceContextID` matches a `CDProjectSession` id. It runs once per device (a local flag), never while `FirstDownloadGate` is pending, and is idempotent: it only fills an empty field, so two devices writing the same value converge.
  - It goes in `Services/Migrations/` beside the 10-10 note repair, called from `MigrationRunner.launchSweep` (agent P owns that one call). Reset Local Cache clears its flag, as the 10-10 note repair's flag is cleared.
- **Linked copies vs shared rows (#18, #19):** decide per linked group with `WorkGrouping.visibleWork` (not `gatingWork`, which drops real shared rows whenever the child owns any other work). A set of linked copies counts only for each copy's owner. A genuinely shared row (one row, several participants, e.g. a project choice) counts for every participant who isn't completed, as today.
- **Checklist readiness (#17):** `ChecklistMatrixBuilder` stops computing its own "Not yet" and asks the engine for each child's readiness. Agent W owns `BlockingAlgorithmEngine.swift` for this and may add a small per-child entry point (`latestFirst`, `gatingWork`, `needsPractice` already exist). The engine must be given the **closed** work of the preceding presentations too, as its doc says, or finished children read "Not yet". Presentations' behavior must not change, and Pr doesn't edit the engine.
- **View Class Progress (#6):** goes to agent W. `ClassSubjectChecklistViewModel` applies `AppRouter.checklistFilterSequence`, so that field is **kept**, not removed as dead code.
- **Work Schedule (#16, and #25's student-overview Schedule):** move only a check-in whose status is Scheduled. When there is none, create one through `WorkCheckInService`. Completed check-ins and their notes never move.
- **Hide Scheduled Work (#20):** hides `partition.work.scheduled`, the same set the Scheduled pill shows; overdue items stay.
- **Untagged work (#21):** Practice everywhere (card, list, log, filter, detail).
- **Recall Forgotten (#26):** the shared `needsAnotherPresentation` is set only on a presentation she had alone. On a group presentation, her own `CDLessonPresentation` row is marked for re-presentation (the field `ChildRepresentations` reads; the 10-09 #12 meeting fix is the model).
- **Recall duplicates (#28):** one mastered row per child and lesson (earliest `masteredAt`) before grouping strands; `coveredIntents` dedupes within itself.
- **A time set through Claude (#10):** `DayHalfPlanner.times` and its three callers leave a card whose `DayHalfPlanner.moment` is `.time` at its stored time and renumber only the sort-slot cards around it.
- **"Given earlier, date not recorded" (#12):** the undated branch also runs `YearPlanReleaseService.releaseRedundantPlans(after:in:)` and `PresentationRecordCleanup.returnEntriesForOtherLessons`.
- **Rollover default (#35):**
  - When the current school year has already started and more than 30 days have passed, the default effective date is the day before the current year's start. The year being closed out is then the one that just ended, and the incoming year is the current one from `SchoolYearStore`, not "effective date + 1 year".
  - When the chosen date falls inside the current year after its first 30 days, the sheet says plainly which year it will close and roll into, and asks to confirm.
  - The within-60-days-of-the-end case stays.
- **Grade equivalents (#38):** add a separate fixed September 1 cutoff (Florida's rule) used only by `FloridaGradeCalculator`'s grade and age functions. Keep `schoolStartMonth` / `schoolStartDay` / `schoolYearStart` and every existing signature, because attendance, `ProjectActivity` and S's #34 count use them. A child with no birthday shows "—" for birthday, age and grade (#31) and sorts last by Next Birthday.
- **Search (#43, #44, #50):**
  - **Deferred launch:** a launch on a hot device or in Low Power Mode still gives `SearchIndexService` its container (and loads the on-disk snapshot when cheap), so `ensureReady()` builds on first use. The photo move to iCloud and the iPhone/iPad download sweep move above the deferral guard; the download sweep already respects energy policy on its own (check; if not, give it its own guard).
  - **Ranking:** students, then lessons, then everything else, newest first within each.
  - **Accents:** `tokenize` folds case and diacritics. Bumping the snapshot's format version forces one rebuild.
- **MCP writes and the guide's unsaved edits (#53):** a failed MCP save must not discard unrelated unsaved changes in the view context. There are 54 `rollback()` calls in 31 MCP files. **One helper replaces every one.** `ContextMutationTransaction` swaps in its own undo manager and can't nest, so tools whose service already runs its own transaction (e.g. `remove_student_from_work` → `WorkDeletionService`) aren't wrapped again, and a test covers one. On failure, undo only the tool's own inserted and updated objects (G7, through `ContextMutationTransaction` / `SaveCoordinator.saveEdit` from `Work/Support/SaveCoordinator+ScopedEdit.swift`), never `rollback()`. **Against Apple's preferred background context, on purpose:** MCP writes must go through the in-app services, which run on the view context. A test holds an unsaved edit in the view context through a failing MCP save.
- **`create_meeting_entry` with a future date (#53):** refused with a plain reason.
- **The Mac's mail sender (#75):** after the compose window opens, always ask "Did the email send?" and record Sent only on yes (G3; as Draft Request does since 10-09 #25). On iOS, `canSendMail()` → the composer with the PDF; otherwise open the mailto link, treat a failed open as failure, and say the PDF can't go by link, offering Share (G4).
- **Parent Reports (#67–#69):**
  - "Draft All Missing" captures the month before it starts and disables the month arrows while it runs.
  - `upsertReport` never overwrites a Sent report.
  - Regenerate asks before replacing text that differs from the last generated draft, and the editor is read-only while generating.
  - Typing into a report with no row creates one (`aiGenerated: false`).
- **Unsaved text (#9, #47, #64, #41, #72, #69):** where a sheet holds typed text, it uses `dismissalConfirmationDialog` while changed (G2), and Cancel asks the same question. Text fields that commit on Return also commit on focus loss and on disappear. Project check-in notes debounce-save, and the background flush saves them.
- **Router requests (#2–#4):**
  - Off the Mac, `requestOpenStudentDetail` also selects Students.
  - New Student / Import Students also navigate to Students.
  - `restoreSelectionIfNeeded` reads a pending `appRouter.selectedNavItem` / `navigationDestination` first, and restores the saved section only when nothing is pending. It's a small function with a unit test. Not `onChange(initial:)`: Apple doesn't say whether it runs before or after `.onAppear`, so the restore could overwrite the request.
  - The shared one-shot "new" flags (#5) go through the window's own `QuickCaptureActions`.
- **Siri (#37):** replies use the short name ("Etty D"). Open Lesson uses `AppRouter.navigateToLesson`. Mark Presented no longer falls back to a former student. Spotlight (#39) deletes the previous identifiers before re-indexing.
- **Names:** the canonical short-name formatter everywhere these findings name a child; chat and MCP lookups also match `shortName`, folded (#49).
- **Departed and test children:** filtered by the visible enrolled roster at each named place (#11, #23, #24, #32, #51, #77).
- **Attendance counts (#34, #74):** `deduplicatedPerStudentDay()`, with tardies counted by `cameLate`.
- **Album index (#54):** the range is clamped (`min(pageIndex, upper)`), and albums without text are skipped. A reload that arrives mid-build marks the build stale, and one more build runs after it. The memory-purge path can't hand a half-empty text table to `semanticItems`.
- **Album links (#55):** re-resolve only when the stored page's title no longer matches. When it doesn't, pick the occurrence of that title nearest the stored page.
- **Wording:** new and changed messages go in the existing catalogs (`SettingsCopy.swift`, `AppErrorMessages.swift`), in plain English and American spelling, added at the end of the relevant section.

**Ruled out:**
- A blanket save of the view context at quit or on background (decided 10-10; the app-core reviewer's safeguard item is not taken).
- A schema change. Nothing here needs one.
- Rebuilding a lesson importer (Danny's answer).
- Rolling out.

## File ownership

Every source file is owned by one agent. An agent edits only its own files. If a fix needs a change elsewhere, the agent says so in its reply, and the main session does it in Phase 3.

The catalogs (`SettingsCopy.swift`, `AppErrorMessages.swift`) are shared and append-only. Each agent puts its new tests in **new test files** named `…Fix1011<agent>.swift`, so branches don't collide. Existing test files that need edits belong to the agent owning the code they test; anyone else asks in the reply.

**Assistant-compiled files:** `TestStudentsFilter.swift`, `AppCore/Constants/UserDefaultsKeys.swift`, `AppCore/Persistence/CoreDataStack+Stores.swift` (P's flag-clearing line goes inside its existing `#if !ASSISTANT_APP` block, since `+LaunchRepairs` isn't in the Assistant), `Siri/StudentAppEntity.swift`, `Siri/StudentEntity+CoreData.swift`, `Siri/StudentNameMatcher.swift`, `AppErrorMessages.swift` and `SaveCoordinator.swift` are also built into the Assistant (106 by-path files; see `project.pbxproj`). An agent touching one also builds the `Daybook Assistant` scheme and runs its matching Assistant suites.

| Agent | Findings | Owns (under `Cosmic Daybook/` unless noted) |
|---|---|---|
| **P Projects, reports & Today** | #65–#77 | `Projects/`, `ParentReports/`, `Notes/Observations/`, `Today/` except `Today/Views/TodayView+Sheets.swift`, `Today/Views/Sections/TodayViewMeetingsSection.swift` (S's) and `Today/Views/TodayViewToolbarPlusMenu.swift` (R's), `Attendance/Email/AttendanceEmail.swift`, the new project-work repair in `Services/Migrations/`, its one call in `Services/Migrations/MigrationRunner.swift`, its flag key in `AppCore/Constants/UserDefaultsKeys+LaunchRepairs.swift`, and the one line clearing it on Reset Local Cache in `AppCore/Persistence/CoreDataStack+Stores.swift` (as the 10-10 note-repair flag does) |
| **A Albums, lessons & resources** | #54–#64 | `Albums/`, `Resources/`, `Lessons/Detail/LessonAlbumLinkSection.swift`, `Lessons/ScopeMap/` |
| **W Work & checklist** | #16–#25 (except #25's calendar pills), #6 | `Work/` except `Work/Practice/RecordPracticeSheet.swift` (R's), `Lessons/Checklist/`, `Components/WaitingStudents/`, `Presentations/Planning/BlockingAlgorithmEngine.swift`, `Students/Detail/StudentOverviewTab.swift`, `Students/Progress/StudentProgressTab.swift` |
| **M Command bar & MCP** | #46–#48, #49's MCP lookup, #51–#53 (MCP items and dictation) | `CommandBar/`, `Services/MCPServer/` |
| **R App core & navigation** | #1–#5, #7, #8, #9, #45 | `AppCore/` except `AppBootstrapper.swift`, `SchoolCalendarService.swift`, `Constants/UserDefaultsKeys+LaunchRepairs.swift` and `Persistence/CoreDataStack+Stores.swift` (P's lines), `Settings/Templates/`, `Lessons/Library/LessonsRootView.swift` and `LessonsRootView+Header.swift`, `Work/Practice/RecordPracticeSheet.swift`, `Today/Views/TodayViewToolbarPlusMenu.swift`, `Students/Roster/StudentsView.swift`, `Students/Detail/StudentObserveWorkspace.swift`, `Components/FilterOrderStore.swift` |
| **S Students & meetings** | #26–#34, #27's Today side | `Students/` except W's, R's and Pr's named files, `Today/Views/TodayView+Sheets.swift`, `Today/Views/Sections/TodayViewMeetingsSection.swift` |
| **Pr Presentations** | #10–#15, #25's calendar pills | `Presentations/` (all but `Presentations/Planning/BlockingAlgorithmEngine.swift`), the top-level `Planning/` folder, `Students/Presentations/PresentationDetailViewModel*.swift` |
| **C Calendar, school year & Siri** | #35–#42 | `SchoolYear/`, `PerpetualCalendar/`, `Siri/`, `Schedules/`, `Students/Rollover/`, `Students/YearPlan/`, `AppCore/SchoolCalendarService.swift`, `Settings/Classroom/SchoolCalendarSettingsView.swift` |
| **Q Search & chat** | #43, #44, #49's chat lookup, #50, #53 (chat items) | `Services/Search/`, `Services/AI/`, `Chat/`, `AppCore/AppBootstrapper.swift` |

The folders above don't overlap. Where a path sits inside another agent's folder, it is named as an exception on both rows.

## Apple guidance

Checked 2026-10-11 against Xcode 27.0 (27A266a, iOS/macOS 27.0 SDKs). Xcode 27.1 RC and 27.2 beta 2 exist; their notes touch none of these APIs, so no update first. Doc pages mostly last modified Aug 14 – Sep 18, 2026.

- **G1. Pending requests (agent R).** `onChange(of:initial:_:)` (iOS 17 / macOS 14) with `initial: true` runs "when this view initially appears", so a request set before RootView existed is applied on first appear. Don't rely on `oldValue` in the initial call. The one-parameter `perform:` form is deprecated. ([onChange](https://developer.apple.com/documentation/swiftui/view/onchange(of:initial:_:)))
- **G2. Confirming a discard (R, M, A, P).** New in the 27 SDK: `dismissalConfirmationDialog(_:shouldPresent:actions:)` (and a `message:` variant). On iOS it fires only for a user swipe or tap outside; **on macOS it also fires for a programmatic `dismiss`, so set `shouldPresent` false before calling `dismiss()` after Save**. A cancel-role button blocks the dismiss; on iOS a destructive button replaces the default close. Use it for sheets holding typed text. `interactiveDismissDisabled` blocks only swipe and outside-click; how the two combine isn't documented, so don't stack them. HIG: confirm before losing content; pair Cancel with Done/Save. ([dismissalConfirmationDialog](https://developer.apple.com/documentation/swiftui/view/dismissalconfirmationdialog(_:shouldpresent:actions:)), [sheets HIG](https://developer.apple.com/design/human-interface-guidelines/sheets))
- **G3. Mail on the Mac (agent P).** `NSSharingService`'s `didShareItems` is documented only as "finished sharing the items"; nothing in AppKit reports that Mail actually sent. Treat it as "handed to Mail", never "sent": always ask "Did the email send?". `didFailToShareItems` with `NSUserCancelledError` means the guide cancelled. ([NSSharingServiceDelegate](https://developer.apple.com/documentation/appkit/nssharingservicedelegate))
- **G4. Mail on iOS (agent P).** `MFMailComposeViewController.canSendMail()` → the composer (it can attach the PDF). Otherwise `await UIApplication.shared.open(mailtoURL)` and treat `false` as failure. `canOpenURL` is deprecated in iOS 27 ("prefer attempting to open URLs and handling any failures"). A mailto link can't carry the PDF, so say so and offer Share. ([open](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)), [canSendMail](https://developer.apple.com/documentation/messageui/mfmailcomposeviewcontroller/cansendmail()))
- **G5. Spotlight (agent C).** `CSSearchableIndex.deleteSearchableItems(withIdentifiers:)` (or by domain identifier) removes items; completion means "journaled", and an error means retry. Delete the ids no longer current (a diff against the last indexed set kept on the device) rather than relying on expiry. Moving to `IndexedEntity` (iOS 27's `IndexedEntityQuery`) is out of scope. ([CSSearchableIndex](https://developer.apple.com/documentation/corespotlight/cssearchableindex))
- **G6. Search folding (agent Q).** `folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale:)` folds once for stored keys, as Apple suggests for repeated comparisons. Pass a **fixed locale** (`Locale(identifier: "en_US_POSIX")`), not `nil`, so index keys don't change with the device's locale. ([folding](https://developer.apple.com/documentation/foundation/nsstring/folding(options:locale:)))
- **G7. MCP writes (agent M).** `rollback()` discards every unsaved change in the context, so a failed MCP save on the view context drops the guide's own edits. Apple's preferred pattern is a separate background context, but the project rule is that every MCP write goes through the service the in-app control uses, and those run on the view context. So **on failure, undo only the tool's own changes.** The 10-10 `ContextMutationTransaction` / `SaveCoordinator+ScopedEdit.swift` does this with its own undo manager for the edit's span; reuse it (`SaveCoordinator.saveEdit`, or `ContextMutationTransaction` directly; in `Work/Support/`, W's file, so M calls it without editing it) rather than `rollback()`. Its transactions don't nest (see Decisions). Not a child context either: its save pushes into the view context, and the next view-context save would carry the guide's half-done edits. (See Decisions.) ([rollback](https://developer.apple.com/documentation/coredata/nsmanagedobjectcontext/rollback()))
- **G8. Dictation (agent M).** `SFSpeechAudioBufferRecognitionRequest.endAudio()` (or the task's `finish()`) "finishes processing on the audio input that has already been accepted"; `cancel()` just cancels. So on stop, end the audio and wait briefly for the `isFinal` result before tearing down. `SpeechAnalyzer` (iOS 26+) is Apple's newer path; moving to it is out of scope. ([SFSpeechRecognitionTask](https://developer.apple.com/documentation/speech/sfspeechrecognitiontask))
- **G9. Siri navigation (agent C).** `openAppWhenRun` is deprecated in favor of `supportedModes` (`.foreground(...)`). Leave existing intents' mode as they are unless the fix needs it, and route Open Lesson through the app's own `AppRouter.navigateToLesson`. App Shortcuts are still capped at 10 per app (HIG); the plan adds none. ([App Shortcuts HIG](https://developer.apple.com/design/human-interface-guidelines/app-shortcuts))
- **G10. Numbers and PDFs (agents M, A).** `Int(exactly:)` returns nil for out-of-range, fractional, NaN and infinite Doubles. PDFKit declares no thread safety. Build a `PDFDocument` and read `page.string` inside one task, and pass only `String`s out; `page.string` can be nil.

## Agent brief (every fix agent)

- **Worktree:** your own (`isolation: worktree`, starting at the last-pushed main, ee7923e6). This plan and the report are not on main. Read them at these absolute paths:
  - `/Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/oldest-unanalyzed-files-hunt-a610ad/docs/Plans/Plan - Bug hunt 2026-10-11 fixes.md` (Decisions, File ownership, Apple guidance, your section)
  - `/Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/oldest-unanalyzed-files-hunt-a610ad/docs/Reviews/Bug hunt 2026-10-11.md` (your findings)
- **Rules:** read `Cosmic Daybook/CLAUDE.md` first. Edit only the files your row owns.
- **Tests:** for each data or logic fix, write a failing test first, in a new test file, and **commit the test before its fix**, so a reviewer can check it out and see it fail. View-only fixes need no test; name them in your reply as "not tested (view code)".
- **Build:** build only the `Cosmic Daybook` scheme for iOS Simulator through `Scripts/locked_xcodebuild.sh` (with the prefix-mapping settings from CLAUDE.md, built once before editing). Build macOS too when you touch Mac-only code (`#if os(macOS)`, Mac windows, menus, the Mac mail sender), and the `Daybook Assistant` scheme when you touch an Assistant-compiled file.
- **Test runs:**
  - Run only `-only-testing:` suites: the existing suites covering your files (find them by grep in `Cosmic Daybook Tests/`, and name them exactly in your reply) plus your new ones.
  - Always on your leased **iOS** simulator (`-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`, `-parallel-testing-enabled NO`), through `~/.claude/bin/build-turn`.
  - **Never run tests on macOS:** the Mac test host opens Danny's live notebook.
  - Run `~/.claude/bin/sim-lease --done` before replying.
- **Builds wait in the shared queue; never give up your turn.** Run long builds in the background or with the longest timeout.
- **Commits:** commit on your branch with clear messages ending in the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` line.
- **Reply in at most 15 lines:** what changed (files), build and test results with counts, which new tests failed on the old code, anything unresolved or decided differently from the plan, and any device check worth doing. No narrative.

## Phase 1: Wave 1 — P ‖ A ‖ W ‖ M

Four agents at once, each per the Agent brief, with its row of File ownership and its findings.

### P Projects, reports & Today (#65–#77)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). Has a launch data repair, and reports that go home to parents.
- Steps: per Decisions. The Uniform type and the repair (#65); stamp and touch only on real changes (#66); Parent Reports (#67–#69, #74–#76); Today's todo rule matching `TodoListFilter.isDueOrPlanned` (#70); Today's lesson lookup through the catalog (#71); project check-in notes save on background and don't overwrite newer text (#72, #73); #77's smaller items (project editor, guardian email check, Reflect task, the Parent Reports banner).
- Done when: iOS + macOS + Assistant build clean; its suites pass, with new tests for #65 (the type and the repair), #66, #67, #69, #70, #74 and #76 failing on the old code.

### A Albums, lessons & resources (#54–#64)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). A crash in concurrent index code, and link data that syncs.
- Steps: per Decisions. Index build (#54); link re-resolve (#55); Find a Different Page and its wording (#56); the Album row's setup check (#57); reload keeps the page and highlights, and `refreshIfChanged` compares loaded files (#58); Resources' selection, Recents and missing-file message (#59, #60); the section drag (#61); repair after reload (#62); keep unreachable bookmarks (#63); #64's smaller items. Dead code: `AlbumsNavModel.showFolderPicker` and its picker; the unused `includeAlreadyLinked` default is now used by #56.
- Done when: iOS + macOS build clean; its suites pass, with new tests for #54 (the reload-mid-build case), #55, #56 and #59 failing on the old code.

### W Work & checklist (#16–#25, #6)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). It changes how shared work is read across the planner, the checklist and the work screens.
- Steps: per Decisions. Schedule (#16, and #25's student-overview Schedule); the checklist uses the engine's readiness (#17); per-group reading through `WorkGrouping.visibleWork` in the checklist cells, the Quiet column, the child filter and the Works log (#18, #19); Hide Scheduled (#20); the Practice fallback (#21); the lesson name in the log (#22); roster rebuild on student saves (#23); hide test students' work (#24); #25's printed-sheet age and set-aside quiet days; View Class Progress (#6).
- Done when: iOS + macOS build clean; its suites pass, including `BlockingAlgorithmEngine`'s existing suites unchanged; new tests for #16–#20 and #22 fail on the old code. One of them compares the checklist cell with the engine for (a) practice that exists only as closed work and (b) a confirmation recorded on the other giving.

### M Command bar & MCP (#45–#48, #49 MCP side, #51–#53)
- Who: `feature-phase-deep` (Opus 5.5, xhigh). MCP writes share the view context with the guide's edits; the rollback helper reaches 31 files, so expect this agent at the top of the cost range.
- Steps: per Decisions. Leave `CommandBarSheet`'s parameters as they are (R wires `onPractice`; the main session removes the dead `onPresentation` / `onNote` in Phase 3). Unresolved names (#46); dismiss guard and raw text in Recent (#47); post `.noteDidSave` after the capture save and MCP `create_observation` / `update_observation` (#48); short-name lookup in `MCPNotebookTools.swift` (#49); enrolled-only follow-ups (#51); `Int(exactly:)` (#52); #53's MCP rollback scope, future-date refusal, `classroom_snapshot` description, and dictation keeping its last words.
- Dead code: `CaptureProposalReviewView.Mode.recordedPresentation` and the `recordedPresentationID` path; `buildAction`'s `.recordPresentation` / `.addNote` and `CommandAction.openPresentation` / `.openNote`, as far as the sheet's `onPresentation` / `onNote` parameters (those two stay until Phase 3).
- Done when: iOS build clean (macOS too, since the MCP server is Mac-only); its suites plus `MCPToolRegistryTests` pass; new tests for #46, #48, #49, #51, #52 and the rollback case fail on the old code.

## Phase 2: Wave 2 — R ‖ S ‖ Pr ‖ C ‖ Q

Each starts as a Wave 1 slot frees, in this order.

### R App core & navigation (#1–#5, #7–#9, #45)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. New Lesson opens Lessons with its sheet, and every Import Lessons item and the router case go (#1). Open Student off the Mac (#2); New and Import Students navigate (#3); pending requests on first appear (#4); per-window "new" actions (#5); the floating button's offset clamp (#7); a Done button on Guide Review (#8); the template editor's dismiss guard, save failure and sort order (#9). Command bar Practice (#45): `RecordPracticeSheet` gains optional `lessonID` / `studentIDs` init parameters with defaults, `ActiveSheet` gains a case carrying them (the bare `.recordPractice` stays for existing callers), and the `CommandBarSheet(…)` call passes `onPractice`.
- Dead code: `NavigationDestination.backfillIsPresented` / `requestBackfillIsPresented()` (both in `AppRouter.swift`); `FilterOrderStore`'s saved area-order read only. **Keep `loadAreaOrder(existing:)` itself** (`GroupsView`, `LessonsViewModel`, two Curriculum Map models and MCP call it, and its merge dedupes). **Keep `checklistFilterSequence`** (W uses it).
- Done when: iOS + macOS build clean; `NavigationGroupTests` and its suites pass; new tests for #1, #2, #3 and #4's router logic fail on the old code.

### S Students & meetings (#26–#34)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. Recall Forgotten (#26); the group-booking pick and per-child completion, including Today's side (#27); recall duplicates (#28); pinned notes from the whole list (#29); the report window clearing on option changes (#30); no-birthday display and sort (#31); recall names across all students, with test students out of the stats (#32); Siri summary short names (#33); profile attendance counts (#34).
- Dead code: `StudentDetailView`'s `selectedLessonForGive` sheet and the iOS `selectedLessonAssignmentForDetail` sheet; `RecallFrontierEngine.precedingLesson` and its tests; `StudentNotesViewModel.loadInitialPage` / `displayedItemCount` / `hasMoreItems`; `TestStudentsFilter.hiddenIDs(from:)` (Assistant-compiled: build the Assistant too); `coveredThisYear` in `buildQueue`.
- Done when: iOS build clean, and the Assistant if it touched `TestStudentsFilter`; its suites pass; new tests for #26, #27, #28, #29 and #34 fail on the old code.

### Pr Presentations (#10–#15, #25 calendar pills)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. Times set through Claude kept (#10); follow-ups filtered by the visible enrolled roster in both callers (#11); the undated branch runs the two cleanups (#12); Suggest's bonus and its "booked" rule (#13); undated presentations skipped for last-taught (#14); the Balance wording and hiding it when the filter hides presentations (#15); one purpose spelling in the calendar grouper (#25).
- Dead code: `ScheduledItem`; the miss-window filter (`PresentationsMissWindow`, the `missWindow` filter in `partitionIntoReadyAndBlocked`); `recentWindowDays` / `syncRecentWindowWithMissWindow` (keep the `UserDefaultsKeys.planningRecentWindowDays` key: `BackupPreferencesService` still carries it); `UndoToken.createdHistoryCount` and `presentedDay`. Don't edit `BlockingAlgorithmEngine.swift`.
- Done when: iOS build clean; its suites pass (the engine's unchanged); new tests for #10, #11, #12, #13 and #14 fail on the old code.

### C Calendar, school year & Siri (#35–#42)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. The rollover default and its confirmation (#35); Add Sequence counts only planned entries (#36); Siri short names, Open Lesson, no former-student fallback (#37); the Sep 1 grade cutoff (#38); Spotlight deletes before re-indexing (#39); the year arrows and scroll jump (#40); day notes commit on focus loss, and the shading reloads (#41); the day toggle deletes the whole day range (#42).
- Dead code: `SchoolYear/SchoolYearFilter.swift` and its use in `SchoolYearTests`.
- Done when: iOS build clean, plus the Assistant, since the Siri entity files are shared; its suites pass; new tests for #35, #36, #38, #39 and #42 fail on the old code.

### Q Search & chat (#43, #44, #49 chat side, #50, #53 chat items)
- Who: `feature-phase` (Opus 5.5, high).
- Steps: per Decisions. The deferred launch (#43); ranking (#44); short-name lookup in `NotebookTools.swift` and a prompt that says to use short names (#49); diacritic folding with a snapshot version bump (#50); #53's chat items (one `ChatToolContext` per chat session, the Private Cloud fallback's sources and cancel, and capping the note text returned to on-device chat).
- Dead code: `SearchIndexService.indexResult`; move its tests to `search`.
- Done when: iOS + macOS build clean; its suites pass; new tests for #43, #44, #49 and #50 fail on the old code.

## Phase 3: Combine, review, fix round, full builds and suites, land (main session)

1. Bring this branch up to date with main (`sync_with_base_branch` if main moved).
2. Merge the nine branches as they finish (the merge can start while later agents still run). Resolve catalog merges and any `project.pbxproj` lines. Make the cross-owner changes agents asked for, and remove `CommandBarSheet`'s dead `onPresentation` / `onNote` parameters and their arguments at the call in `RootView+Sheets.swift` (after M and R are both merged).
3. Build `Cosmic Daybook` for iOS Simulator once, to catch merge breaks.
4. Three `Plan` reviewers (Opus 5.5), read-only, on the combined diff against main, each given this file and the report, each returning at most 15 real problems:
   - (a) records that spread or sync: P, A, W, S.
   - (b) MCP, command bar, search and chat: M, Q.
   - (c) navigation, presentations, calendar and Siri: R, Pr, C.

   Start each reviewer as soon as its agents are merged.
5. **Fix round:** the main session fixes small problems itself. Larger ones go to a **fresh** small agent (`feature-phase-light` on Sonnet, or `feature-phase` for anything touching records), given just the problem, the files and the Decisions it rests on. Don't resume the agent that wrote the code (the 10-10 cost lesson).
6. **Full builds:** notebook iOS Simulator (build-for-testing) and macOS, and the Assistant iOS Simulator, with no new warnings.
7. **Whole suites once:** the notebook (one simulator, `-parallel-testing-enabled NO`) and the Assistant (its SE on iOS 26.5). Then `sim-lease --done`.
8. Squash to main with one message listing the areas, and push. Keep the unsquashed history on `bug-hunt-2026-10-11-fixes-unsquashed`.
9. Make a Tide row for every device check the agents named (`add_action` under Check on a device in `Areas/App Development/Cosmic Daybook/To do.md`), each linked from this plan.
10. The report's status line becomes `> **All fixed** on main in <commit> (<date>). Not rolled out.` Run `docs-index`. Update the memory file.
- Cost: ~5–9%.
- Done when: all three builds are clean; both whole suites pass, with counts recorded here; main is pushed; the Tide rows are made; the report and plan status lines are set; `docs-index` reports the map current.

## Starting a phase
Read the plan usage (`get_usage`) and note the weekly % used next to the phase under Progress ("started at N%").

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan. Read the plan usage again and note the actual cost (end % minus start %).
3. Add a row to the log in `~/.claude/skills/plan-efficiently/references/cost-estimates.md`.
4. Update the build board, if the plan lists one.
5. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Tide holds the row; the repo line keeps one plain sentence plus the row's `tide://` link.
6. Run /close-out. It sets the plan's status line (`> **Not started.**` after a phase, `> **Done <date>** (<commit>).` after the last, checked against main) and runs `docs-index` so the map follows.
7. Every phase here runs in this session, so there's no starter prompt between phases. If the session has to end early, the next session's prompt is: "Model: Opus 5.5, effort: high. In /Users/dannydeberry/Developer/Maria's Notebook/.claude/worktrees/oldest-unanalyzed-files-hunt-a610ad, read docs/Plans/Plan - Bug hunt 2026-10-11 fixes.md and continue from the first unticked phase. Follow its Starting a phase and Ending a phase steps."

## Open questions
None open. **Decided during the run** (for Danny to read):
- **The build board** is a new one in this claude.ai organization (https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM); the 10-09/10-10 board is in the other organization. Later Daybook builds can add milestones to it.
- **Rollover default (#35, changed by review (c)):** the plan's "more than 30 days in → last year" rule made a June rollover close the wrong year. Now: in the year's first half the default closes out last year; from its midpoint on, it closes out this year on its last day. A date in the first half of the year under way asks to confirm.
- **Removing the last child from project work:** only a choice session's offered row may be left with nobody on it; a whole-class (Uniform) row's last child is refused, as any one-child row is.
- **Group bookings (#27):** a booking also ends when everyone left on it has left the class; a group down to one child counts as her own booking. Two devices finishing different children before syncing can bring a met child back (known limit, in the device checks).
- **Parent Reports:** a month's twin rows read as the one furthest along everywhere; a sent report can't be retyped; typing into an AI draft makes it the guide's text, so Regenerate asks only then.
- **The checklist** treats a plan the guide unlocked as ready, as Presentations does.
- **A card after a time Claude set** counts on from that time, so it draws below it; a card the guide moves loses its own set time (Pr).
- **New Lesson, New Student and Import Students** act in the window they were chosen in (Mac and iPad), not through the shared router. The Go menu has the same old problem and was left for a separate task.
- **Search:** no snapshot format bump for accent folding (the snapshot keeps raw text and folds on load); every caller shares one index build.
- **Chat:** the tool context is made per answer (stricter than per session); chat's own meeting and follow-up writes undo only their own changes on failure.
- **MCP:** `adjust_supply` refuses changes beyond ±1,000,000; a mastery batch that partly saved says which marks were kept.
- **Dictation:** a Send in the two seconds after stopping waits for the last words; a second Send meanwhile is ignored.
- **Command bar, misheard names:** picking a child settles a name only when it's the single name left and matches nobody in the class.
- **C's new messages** (rollover, Siri) sit beside their views, not in the catalogs.

## Device checks

In Tide under Cosmic Daybook's To do (Release and Check on a device). None tried yet; all wait for the roll-out.

- Roll out to the Mac, iPhone and iPad together. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=Roll%20out%20main%20%28a031f7ab%20or%20later%29%20to%20the%20Mac%2C%20iPhone%20and%20iPad%20together)
- The Mac command bar asks before throwing words away, not after Save or when opening a form. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20type%20in%20the%20Mac%20command%20bar%20and%20check%20it%20asks%20before%20throwing%20words%20away%20on%20Cancel%20or%20a%20click%20outside%2C%20not%20after%20Save%2C%20and%20opens%20the%20Practice%20or%20Work%20form%20without%20asking)
- New Lesson, New Student and Import Students act only in the front Mac window. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20open%20two%20Mac%20windows%2C%20one%20on%20Lessons%20and%20Today%20in%20front%2C%20and%20check%20New%20Lesson%2C%20New%20Student%20and%20Import%20Students%20act%20only%20in%20the%20front%20window)
- Template and album-note editors ask only when something changed. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20edit%20a%20template%20and%20an%20album%20note%20on%20the%20Mac%20and%20check%20Cancel%20and%20Save%20ask%20only%20when%20something%20changed%2C%20never%20twice)
- Report and office-order emails ask "Did the email send?" [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20send%20a%20report%20with%20Send%20to%20Family%20and%20an%20office%20order%20email%20on%20the%20Mac%2C%20and%20check%20each%20asks%20%22Did%20the%20email%20send%3F%22%20before%20marking%20it%20sent)
- View Class Progress, the report window's PDF and the Work column. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20on%20the%20Mac%20use%20View%20Class%20Progress%20on%20a%20Geometry%20track%20card%20and%20check%20the%20checklist%20scrolls%20to%20the%20Geometry%20band)
- Claude's presentations reach Observations at once; two chat windows keep their own class. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20have%20Claude%20record%20a%20presentation%20with%20an%20observation%2C%20and%20check%20it%20shows%20in%20Observations%20on%20the%20Mac%20straight%20away)
- Dictation keeps typing and last words, and organizes once. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20dictate%20in%20the%20command%20bar%20on%20my%20iPhone%2C%20stop%2C%20type%20a%20few%20words%20at%20once%2C%20press%20Return%20twice%2C%20and%20check%20my%20typing%20stays%20and%20the%20capture%20is%20organized%20once)
- Search after a Low Power launch, Spotlight, and the floating button. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20launch%20the%20notebook%20cold%20on%20my%20iPhone%20in%20Low%20Power%20Mode%20and%20search%20straight%20away%2C%20and%20check%20results%20come)
- A time Claude set stays put; group meetings keep the others booked (and the known two-device limit). [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20have%20Claude%20book%20a%20lesson%20at%2010%3A30%2C%20drag%20another%20card%20on%20that%20day%2C%20and%20check%20the%20lesson%20stays%20at%2010%3A30%20with%20the%20dragged%20card%20below%20it)
- Albums keep the page while reloading; a missing resource file says so. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20read%20an%20album%20while%20adding%20an%20albums%20folder%2C%20and%20check%20the%20page%20and%20highlights%20stay%20put%20while%20the%20library%20reloads)
- The rollover sheet's default date and its warning. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20open%20the%20year%20rollover%20sheet%20and%20check%20its%20default%20date%20is%20the%20day%20before%20this%20school%20year%20began%2C%20and%20that%20picking%20a%20date%20this%20autumn%20warns%20first)
- The calendar's arrows and day notes, old project check-ins, and the front-desk reminder. [Tide](tide://box/Areas/App%20Development/Cosmic%20Daybook/To%20do.md?text=After%20the%20next%20roll-out%2C%20use%20the%20calendar%27s%20year%20arrows%20and%20New%20Year%20scroll%2C%20write%20a%20day%20note%20and%20click%20away%2C%20and%20check%20the%20note%20is%20kept)
