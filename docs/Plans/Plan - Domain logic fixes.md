# Domain logic fixes

> **Not started.** Written 2026-11-20 from <../Reviews/Domain logic review 2026-11-20.md> (found at main e25eb65d8).
> In short: fix all 25 findings and the 20 smaller ones from the 2026-11-20 domain-logic review, in nine phases plus a final check, with one schema bump (25, backup format 47) that touches both stores.

## Goal

Every classroom rule the review found written more than once gets one home that every path calls: the screens, Claude's tools, Siri, the command bar and restore. The four bugs that cost records stop: "given today" from the recap, logged work stuck in Attention, Claude's unmark that doesn't clear, and one-child notes missing from the Progress tab. The missing rules get added: who was in class on a date, a real school session with first and last days, a classroom time zone, linked work with a real assignment id, dated level history, siblings' shared guardians, and one busy picture for the schedule.

Item numbers below are the review's: **R1–R25** are the top 25 and **A1–A20** the "Also found" list. Each phase reads its items in the review for the evidence and the file:line references.

## Progress
Marks: `plan/domain-logic` (each phase tags the primary checkout `plan/domain-logic/phase-<N>` when it merges; see `~/.claude/bin/plan-wait`)
Build board: https://claude.ai/artifact/CN28oMqiKihr3cjEPqmrVc (the conductor keeps it current; tasks p1–p10 are the phases)
- [ ] Phase 1: Schema 25 and backup format 47 · runs as: session · needs: — · est. $15–30 (~1%)
- [ ] Phase 2: Attendance rules in the store · runs as: session · needs: — · est. $10–20 (~1%)
- [x] Phase 3: Schedules, Restock and repeating to-dos · done 2026-11-21 (208cd6aa3) · agent acfea9405548e36ca, squashed by the conductor · actual ~350k agent tokens
- [ ] Phase 4: Presenting and mastery · runs as: session · needs: 1 · est. $18–35 (~1–2%)
- [ ] Phase 5: Work rules · runs as: agent (Fable 5.2) · needs: 2, 4 · est. $50–90 (~2–4%)
- [ ] Phase 6: Lesson order, year plan and prerequisites · runs as: session · needs: 4, 5 · est. $12–25 (~1%)
- [ ] Phase 7: Who's in class, departures and meetings · runs as: session · needs: 3, 6 · est. $12–25 (~1%)
- [ ] Phase 8: Notes, reports, level history, guardians and rollover · runs as: session · needs: 7 · est. $20–40 (~1–2%)
- [ ] Phase 9: School session, time zone and the front desk · runs as: agent (Fable 5.2) · needs: 7 · est. $35–65 (~2–3%)
- [ ] Phase 10: Final check · runs as: session · needs: 1–9 · est. $15–35 (~1%)

Phases 1, 2 and 3 start together. Then the middle runs in a line, because those phases share files: 4 after 1, 5 after 4 (and 2), 6 after 5, 7 after 6 (and 3). 8 and 9 run together after 7, and 10 comes last. Every phase needs the ones before it in that line, so at most three run at once.

## Cost

About **$300–495 (13–21%)** of the weekly limit, of which about $90–160 is Fable (22–40% of Fable's own window, at 3% now): phases $205–398, plus the conductor (planning about $60 so far, about ten wakes at $2–3 each, plus the close). 1% is about $23 this week (calibrated 2026-11-20 against 10% used). You have 90% left until Fri Nov 27. **Fits.** The run brakes itself if a phase costs more than twice the top of its range or the week passes 90%. Past Cosmic Daybook phases came in at about half their estimates, so the low end is the likelier one.

## Before you go

- **How it runs (2026-11-21):** as background agents inside the conductor session (Decision 20). You can't open or stop one phase on its own, and per-phase costs are rougher. If you type "go" on the Mac, the conductor can start the remaining phases as sessions instead; they pick up from the same marks.
- **Effort:** the conductor can't raise its own effort, so every phase session runs at high. Phases 1, 5 and 9 hand their delicate parts to a `feature-phase-deep` agent (Opus, xhigh).
- **Permission mode:** bypass. Already on.
- **The screen is locked and locks itself straight away,** so nothing in this run drives the Mac or a simulator by hand. Every "check on a device" item becomes a Tide row for the morning. No app grants are needed.
- **Keep awake** is on, also on battery, and the Mac is plugged in. A closed lid still sleeps.
- **The build queue is busy** (one build running, three waiting). The run's builds wait their turn; nothing to do.
- **More than eight phases:** the app may stop waking the conductor partway through. The phases still run, each starting from the others' marks; only the checking and Progress lines fall behind until your next message ("go on" is enough).
- **Leave Tide running.** Every phase adds its device checks to Tide (`add_action`).
- **The run takes long.** The middle phases run one after another because they share files, so expect it to go well into tomorrow, with builds waiting in the queue.
- **Only you, later (Tide rows, not tonight):** before any roll-out, add schema 25's new fields and entity to the CloudKit Development schema and deploy to Production. Until then, TestFlight builds with schema 25 won't sync. Then install schema 25 on every device in one sitting. Don't open a schema-25 Debug build on your Mac against the live notebook before that: it would move the store to schema 25, and the installed copy would then refuse to open it (`verifyStoreIsNotFromNewerBuild`).

## Decisions

Danny's answers (2026-11-20):
1. **Scope: everything, shared store too.** One schema bump (25, backup 47) carries every new field, in Phase 1, so no two phases edit the model.
2. **Mastery closes work as Mastered.** Marking mastery anywhere closes her open work on that lesson as Mastered (not Finished). Closing work as Mastered from the work page offers the mastery mark right then. Never backfill marks.
3. **Parent reports swap other children's names** for "a classmate" before drafting. No per-note question.
4. **Claude follows the ahead-of-day rule:** on days still to come it takes only absences and notes, like the screens. Restore stays free. This reverses the line in `docs/Technical notes/SIRI.md` ("screens and view model, not the store, so MCP and restore are unchanged"), which Phase 2 updates.
5. **The clash badge uses overlap:** lessons less than `LessonLength.assumedMinutes` apart clash, matching free times. This changes the co-teacher plan's decision 7; Phase 3 notes it there.

Settled here (safer, easier to undo):
6. **Meetings (R8): Re-present and Ready take effect at the tap,** through the existing close tokens for undo. The draft's text stays on the device. Ruled out: a synced draft record. It is L, and acting at the tap already removes the harm (records left half-done on one device).
7. **Practicing (R14): the ladder treats the stored Practicing / Ready for Assessment state as a floor.** The pill stays.
8. **Reported days (R18): show "changes since reported"; don't lock days.** Ruled out: making a reported past day read-only for assistants (older Assistant builds wouldn't honor it).
9. **Arrival closed (A1): readers in this plan, writer in the next release.** The close goes on an `AttendanceEmailSend` channel row, like `notExpected`. An Assistant build without the reader would count that row as a send, so the writer waits for one roll-out. That becomes a Tide row.
10. **School session (R20): first and last day on the shared settings row** (`CDAttendanceEmailSettings`). Days outside the session are days off for every reader. Unset falls back to today's behavior. Ruled out: the "Summer break" action alone; it would be redundant with the real dates.
11. **Time zone (A4): a classroom time zone on the same row.** The guide sets it (defaulting to the Mac's zone on first save), and `AppCalendar` uses it, falling back to the device's zone when unset.
12. **Guardians (A9): a `personID` shared by a sibling's copies of the same parent, not a family entity.** It is filled once by matching email (then phone) across children. An edit updates every row with that id, and the guardian sheet says "Also Leo's parent". Ruled out: a family entity. It needs a new relationship on the shared `Student`, while `personID` keeps older builds working with separate rows.
13. **Level history (A8): a new private entity `CDLevelChange`** (student, from, to, the day). A change undone the same day removes the pair, so a mis-tap leaves no history. Reports read the level she had that month.
14. **Linked work (R22): `assignmentID` and `isSharedRow` on `CDWorkModel`**, stamped by `createWork` and filled once at launch from today's 60-second guess (the guess then retires as the reader). One ownership rule is built on them.
15. **Per-child presentation facts (R24): `needsPractice`, `needsAnotherPresentation` and `manuallyUnblocked` move onto her `CDLessonPresentation` row as optional Bools.** Nil means "not set on her row", and readers then fall back to the group record's value, so existing rows and format-46 restores keep their meaning. Writers set the child's row and keep the group record's field as "true if any child" for older builds.
19. **Every fill keys on nil and also runs after a restore,** never on a one-time flag: `assignmentID`/`isSharedRow` (Phase 5) and `personID` (Phase 8). A format-46 restore then gets filled too.
16. **Year-plan promotion (R17): fix the drift with shared functions plus the repair run wherever the index is built.** Ruled out: deriving promotion from the record. It is L, and the stored fields are still read by older builds and backups.
17. **A20 was not checked by hand.** Phase 8 checks it first and fixes it only if real.
18. **No roll-out, no push, no install in this plan.** Phases merge to local main; Phase 10 adds the roll-out row to Tide.
20. **2026-11-21: the phases run as background agents of the conductor, not as sessions.** The go-ahead came over Remote Control, and a Remote Control turn can't start sessions. Phase 1 runs as `feature-phase-deep` (Opus, xhigh); the rest as `feature-phase` (Opus, high), except as Decision 21 says.
21. **2026-11-21, Danny: use Fable where it's the better model.** Fable 5.2 (high) runs Phase 5 (the ownership rule and what a due date means, across about 25 files) and Phase 9 (the pinned calendar, which every day calculation in both apps follows), plus Phase 10's cold review. Those are where a subtle mistake is hardest to notice. Fable costs about 2.5× Opus per token, so the rest stay on Opus. Phase 1 was already running on Opus xhigh and stays. The conductor launches each phase once the phases it needs are marked (`plan-wait --status`), at most three at once, and runs Phase 10's full builds and whole suites itself. See "If you are a phase agent" below.
22. **2026-11-21: the conductor does every merge.** A guard refuses any git command an agent runs in the primary checkout, so Phase 3 couldn't squash itself. The conductor squashes each finished branch onto main with `git commit-tree` (main's tip as parent, the branch's tree) under `plan-merge-lock`, then runs `plan-wait --mark <N>`.

## Apple guidance

Checked 2026-11-20 against Xcode 27.2 (27B52), iOS and macOS 27.2 SDKs. Xcode 27.3 is only in beta, and its notes change nothing here.

**Schema 25 (Phase 1)**
- **Adding attributes and adding an entity are lightweight migrations** ([Migrating your data model automatically](https://developer.apple.com/documentation/coredata/migrating-your-data-model-automatically), 2026-10-08). The project edits one model version in place, which isn't Apple's documented path; `StoreMigrationTests` is the evidence it works here. Phase 1 adds a 24 → 25 store test.
- **Staged migration is not needed.** `NSStagedMigrationManager` (iOS 17+) is meant for changes lightweight migration can't do, and needs one model version per stage.
- **CloudKit's schema doesn't follow the model.** Run `initializeCloudKitSchema` in Development only (never in production; it blocks other CloudKit work while it runs), then deploy. Deploys only add; fields can't be changed or removed afterwards ([Creating a Core Data model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit), 2026-10-08).
- **A field missing from Production stops sync** ("Cannot create or modify field … in production schema", error 134406), so TestFlight builds don't sync until the deploy ([TN3164](https://developer.apple.com/documentation/technotes/tn3164-debugging-the-synchronization-of-nspersistentcloudkitcontainer), 2026-10-08). This is why the deploy is a Tide row before any roll-out.
- **Both stores share one schema.** All databases in a container use it, so one initialize and one deploy cover the private and shared stores. `CDLevelChange` stays out of the shared configuration.
- **Older builds** "have access to every record… but not every field." Apple doesn't say whether an older build that re-saves a record keeps the new fields. So readers must treat a missing new field as unset (Decisions 12, 14, 15 already fall back).

**Time zone (Phase 9)**
- **Apple has no page on "the same day across zones".** Use one pinned `Calendar` everywhere: `var c = Calendar.autoupdatingCurrent; c.timeZone = zone`. It keeps the locale and `firstWeekday`; `Calendar(identifier: .gregorian)` has an empty locale ([Calendar](https://developer.apple.com/documentation/foundation/calendar), 2026-10-08).
- **Validate the synced identifier.** `TimeZone(identifier:)` returns nil for bad strings, including the wrong case (`america/new_york`). Fall back to the device's zone.
- **Some days start at 1:00.** On those days, adding `.day` to a day start lands at 1:00 the next day, so call `startOfDay` again after adding. `date(bySettingHour: 0…)` also gives 1:00.
- **Formatters default to the device's zone,** so date formatters that show a day must take the pinned calendar's zone.
- **Days already saved in another zone are a different instant.** Phase 9 makes attendance records, locks and sends match by the day's range instead of exact midnight, as days off already do (`SchoolDayChecker`).

Not applicable: no other new Apple APIs. App Intents, SwiftUI and the rest change only in project code.

## Rules every phase follows (project-specific)

- Build through `Scripts/locked_xcodebuild.sh` (see `Cosmic Daybook/CLAUDE.md` › Build & Run), with `COMPILER_INDEX_STORE_ENABLE=NO` and the three prefix-mapping settings. Build once right after the worktree is made, before editing.
- **Never run tests with a macOS destination:** the Mac test host opens the live notebook. Test on this checkout's leased iOS simulator (`-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`, `-parallel-testing-enabled NO`), and the Assistant on the leased SE (`~/.claude/bin/sim-lease --type "iPhone SE (3rd generation)" --os 26.5`). Mac only builds.
- Every fix gets a test that fails on main first (Swift Testing; name the enclosing type in `-only-testing:`, memory: nested suites). No vacuous `#expect(base.prop)`.
- Plain English in anything the app shows (`AppErrorMessages`); American spelling.
- A file the Assistant compiles (`Sharing/*`, `AppCore/Persistence/*` and about 90 more) must build for iOS 18: guard iOS 26+ APIs.
- Keep to your phase's file list. If a fix needs a file another phase owns, make the smallest change and say so in your final message.
- **The Assistant lists its files one by one in `project.pbxproj`.** Prefer putting Assistant-shared code in files it already compiles. If you add one, add it to the Assistant target too, and merge main just before close-out so two phases' pbxproj edits meet once.
- A build that exits 75 ("never started", the queue timed out) is not a failed try: start it again with `run_in_background`.
- "Done when" counts only with evidence: every `-only-testing:` suite reports a nonzero "Executed N tests", the new tests are named in the final message, and each was seen failing on main first.
- In close-out, skip `git pull --ff-only` (nothing is pushed in this plan); work from local main only.

## Phase 1: Schema 25 and backup format 47
- Who: phase session (Opus 5.5, high). The model, backup and migration edits go to a `feature-phase-deep` agent (xhigh); the session checks, tests and merges. Storage only; it changes no behavior. Also leaves a small public hook in `Backup/BackupService+RestoreAftercare.swift` that later phases' after-restore fills and `normalize()` register with.
- Needs: —
- Steps:
  - `Cosmic Daybook/CosmicDaybook.xcdatamodeld`, the one model version edited in place, to schema 25. All fields are optional or defaulted, with no unique constraints and no relationships:
    - **Private:** `WorkModel.assignmentID` (String) and `isSharedRow` (Bool, NO) for R22.
    - **Private:** `LessonPresentation.needsPractice`, `needsAnotherPresentation` and `manuallyUnblocked` (Bool, NO) for R24.
    - **Private:** `Guardian.personID` (String) for A9.
    - **Private:** a new entity `LevelChange` (`id` UUID, `studentID` String, `fromLevelRaw`, `toLevelRaw` String, `changedOn` Date, `createdAt`, `modifiedAt` Date) for A8.
    - **Shared:** `AttendanceEmailSettings.classroomTimeZoneID` (String), `sessionFirstDay` and `sessionLastDay` (Date) for A4 and R20.
  - The entity classes (`@NSManaged`, the `CD` prefix, the entity's own file). Add `CDLevelChange` to the private configuration and to `CoreDataStack`'s lists, and give it id-based duplicate folding like the other private rows.
  - Bump `currentSchemaVersion` to 25 and add its history line (`AppCore/Persistence/CoreDataStack+SchemaVersion.swift`).
  - The three R24 Bools are **optional** (no default), per Decision 15.
  - Backup format 47 (`Backup/`): every new field and the new entity as `ModelRow` specs. Format 46 backups still restore, with the new fields at their defaults. Add golden and round-trip tests.
  - `docs/Technical notes/DATA_MODELS.md` (the entity table, the schema 25 line, "93 entities" → 94) and `Cosmic Daybook/CLAUDE.md`'s Data Model paragraph.
  - Add a Tide row: "Add schema 25 to the CloudKit Development schema and deploy to Production, before any roll-out" (Cosmic Daybook › Build & fix).
- Cost: $15–30, ~1% (schema bump at xhigh; schema 24 plus format 46 ran in this range).
- Done when: the iOS app, the Assistant and the Mac all build. The model, backup and CoreDataStack suites pass on iOS, plus a new round-trip test per field, the 46 → 47 restore test, and a test that opens a store made by main's schema-24 model and finds its rows.
- By hand: none.

## Phase 2: Attendance rules in the store
- Who: phase session (Opus 5.5, high). Shared-store writes and the duplicate rule need care.
- Needs: —
- Steps:
  - **R5:** add `CDAttendanceStore.mark(student:status:reason:on:)`. It checks the roll (`AttendanceRoster.wasEnrolled`; test students and departed children refused), the lock and the role, and the ahead-of-day rule for every caller except restore (Decision 4). It routes Unmarked to `unmark`, and makes an absence the guide's (clearing Close Arrival's automatic marker). Pick one day-off policy: confirm, which Claude returns as a refusal that says why. Move the grid (`AttendanceViewModel`), Siri (`SiriAttendance`), Claude (`MCPNotebookTools+Attendance*`) and the Assistant's view model onto it. Update `docs/Technical notes/SIRI.md` and `MCP_SERVER.md`.
  - **R19:** one attendance tally that counts a record only on a school day she was enrolled, and gives days enrolled, present, absent and late. It is used by `AttendanceStatusReport` and `AttendanceInsightsService`. Making a day with marks a day off says so (`SchoolCalendarService`).
  - **A13:** `CDAttendanceRecord.normalize()`, run before save and after restore (through Phase 1's after-restore hook), plus a `data_checks` line.
- Files: `Attendance/Store/`, `Attendance/AttendanceViewModel*.swift`, `Attendance/Rules/AttendanceRules.swift`, `Attendance/Reports/`, `Attendance/Insights/`, `Services/Calendar/SchoolCalendarService*.swift` (the day-off message only), `Siri/SiriAttendance*.swift`, `Services/MCPServer/MCPNotebookTools+Attendance*.swift`, the data-checks tool, and `Daybook Assistant/Attendance/` view models.
- Cost: $10–20, ~1%.
- Done when:
  - The iOS app, the Assistant and the Mac all build.
  - The attendance store, view model, Siri attendance and MCP attendance suites pass, plus the Assistant's attendance suites.
  - New tests show each of these: Claude's unmark beats a duplicate's mark; Claude refuses a departed child and a "present" on a day ahead; Absent claims Close Arrival's absence; the tally drops a day turned into a day off.
- By hand: none (device checks → Tide).

## Phase 3: Schedules, Restock and repeating to-dos
- Who: phase session (Opus 5.5, high).
- Needs: —
- Steps:
  - **R15:** an every-week or This Day and After edit applies its changed fields to each later one-day change wherever that change still holds the old value.
  - **R16:** one per-day busy model built from the resolved `ScheduleDay`. It covers co-teacher groups, Danny's turns, Out Today (lessons set aside, with one "You're out; N lessons are planned" warning), children leaving early (from `leavesAt`) and absent all day, lesson-on-lesson overlap (Decision 5), and overlapping blocks (a child in two groups at once, or a person in two blocks at once). Free times, the planner cards, the day badge, the Schedules warnings and `weekly_schedules`/`set_timetable` all read it. Note the change to decision 7 in `docs/Plans/Plan - Co-teacher times when scheduling.md`'s Decisions as a dated line.
  - **A7:** a lane kind for the adolescent room (a new `kindRaw` value; older builds read it as a room). The name rule stays as the fallback, and Today's "Your turn" uses the same definition.
  - **A14:** one booking-window constant both apps read. Outside the window, the Assistant says Danny's lessons show for today and the next two weeks.
  - **R7 (schedules part):** Claude's timetable writes match children with `StudentNameMatcher` over the enrolled roster. Add `TimetableService.takeOutOfGroups(studentID:from:)` (This Day and After), which Phase 7's departure step calls.
  - **R25:** the next occurrence of a repeating to-do gets an id derived from the completed one's (like `splitCopyID`), so the existing same-id duplicate cleanup folds the pair and the Tide link survives. Find the previous occurrence by that id, falling back to the title for older rows.
  - **A2:** `RestockService.reconcile` lets the later of the level and the need win, once things have settled.
- Files: `Schedules/`, `Presentations/Planning/DayHalfPlanner*.swift`, `Schedules/Services/AwayTimes.swift`, `Presentations/…/PresentationPlannerCard*.swift`, `Services/MCPServer/MCPNotebookTools+Timetable*.swift`, `Today/Support/TodayScheduleRows.swift`, `Daybook Assistant/Schedule/`, `Supplies/`, `Todos/Services/`, and the to-do dedup in `DataCleanupService+Deduplication.swift` only if needed.
- Cost: $15–30, ~1%.
- Done when:
  - The iOS app, the Assistant and the Mac all build.
  - The Schedules, AwayTimes, DayHalfPlanner, MCP timetable, Restock and to-do suites pass, plus the Assistant's Schedule and Restock suites.
  - New tests: an every-week edit reaching Nov 24's change; free times avoiding Danny's turn; a 9:00 and 9:15 clash; a child leaving at 1:30 blocking 1:45; a child in two 9:15 groups; two devices' next occurrences folding into one.
- By hand: none.

## Phase 4: Presenting and mastery
- Who: phase session (Opus 5.5, high). Many writers, and records Danny can't easily rebuild.
- Needs: 1
- Steps:
  - **R2:** one `MasteryMarking.mark/unmark`, called by the Checklist (cell and batch), the presentation sheet's pill, the work page and Claude's `mark_mastered` (plus a new unmark on Claude's side). It:
    - marks every row she has;
    - closes her open work on the lesson as **Mastered** (Decision 2);
    - treats any mastered row as "already mastered";
    - reads mastery one way, `SequenceStanding.isMasteryMark`, everywhere.
  - **Rest of R2:**
    - The same-id lesson merge raises the state.
    - A "Not mastered" Checklist step changes only mastery rows.
    - Closing work as Mastered on the work page offers the mark.
  - **R3:** the recap's status on a lesson she has no record of uses the Checklist's undated attachment. `PresentationRecordIndex.given` is the one answer to "given"; move `DaysSinceLastLesson` and the Checklist cell onto it.
  - **R6:** move the sheet's follow-up-row writing into `CaptureFollowUpPersistence.persist`, so Claude and the command bar write Ready, Practice and Follow-up rows.
  - **R10:** `persistObservations(observedOn:)`; remove the after-the-fact re-dating in Claude's and the command bar's paths.
  - **R12:** one `PresentationRecorder.resolvePlan(lesson:present:on:)` for the sheet, Claude, the command bar and Siri. The same day counts as an edit, and absent children move to their own plan.
  - **R24:**
    - The `studentIDs` setter keeps confirmations to children still on the presentation.
    - Per-child `needsPractice`, `needsAnotherPresentation` and `manuallyUnblocked` live on her row (Decision 15). Write the child's row and the group's "any child". Readiness (`BlockingAlgorithmEngine.swift`) reads the child's row first.
    - Fix `YearPlanReleaseService`'s comment.
- Files:
  - `Presentations/Session/`, `Presentations/Workflow/`
  - `CommandBar/Services/` and `CommandBar/ViewModels/CommandBarViewModel+CapturePersistence*.swift`
  - `Siri/MarkLessonPresentedIntent.swift`
  - `Services/MCPServer/MCPNotebookTools+Presentation*.swift`, `MCPNotebookTools+Mastery.swift`
  - `Students/Presentations/`
  - `Lessons/Checklist/Model/` and its cell and batch action files
  - `Models/LessonAssignmentEntity.swift`, `Models/LessonPresentation*.swift`
  - `Presentations/Planning/BlockingAlgorithmEngine.swift` (not its `+SequenceOrder` or `+WorkCompletion` files)
  - `PresentationRecordIndex*.swift`, `YearPlanReleaseService.swift`
  - `Services/Migrations/DataCleanupService+DeduplicateLessons.swift`
  - `Work/Detail/WorkDetailView+Helpers.swift` (the offer only)
  - `Services/Progression/DaysSinceLastLesson.swift`

  Does **not** edit `ClassGrid/` or other `Work/` files (Phase 5 runs after it and builds on `MasteryMarking`). Leave `gatingWork` in `BlockingAlgorithmEngine` to Phase 5.
- Cost: $18–35, ~1–2%.
- Done when:
  - The iOS app and the Mac build. The Assistant builds too if `Models/` changed.
  - The presentations, recording, capture, checklist, mastery, MCP mastery and presentation, Siri presentation and readiness suites pass.
  - New tests: each mastery path leaves the same rows and work status; a recap pill on an ungiven lesson makes no "given today"; Claude's Ready writes the follow-up row; Friday's notes recorded Monday are dated Friday; a second Siri "presented" makes no second record; a child taken off and added back isn't confirmed.
- By hand: none.

## Phase 5: Work rules
- Who: `feature-phase` agent on Fable 5.2 (high), Decision 21. Seven items across about 25 files; R4 changes what `dueAt` means and R22 changes who owns what.
- Needs: 2, 4 (4 shares `BlockingAlgorithmEngine` and `createWork`)
- Steps:
  - **R4:** the next check comes from the earliest scheduled check-in. `dueAt` holds only a due date the guide set; scheduling stops copying the check day into it, and triage reads the two apart. Claude's `due_date` sets only the due date, and scheduling a check goes through `scheduleCheck`.
  - **R11:** the work page's Done and Claude's `complete_check_in_on` go through `WorkLogService` as "seen, unchanged", with one date rule (clamped to today).
  - **R13:** one `WorkNeglect` rule in school days from the latest meaningful touch, where the end of a rest counts as a touch. It is used by triage, Today's Gone quiet, the Checklist dot (`ClassGridEngine+Staleness`), the meeting work snapshot and the meeting insights. "Age since assigned" gets its own name where meetings mean that.
  - **R14:**
    - `createWork` picks the default kind from the resolved presentation.
    - One practice predicate needs a completed check-in; replace the four string copies.
    - Three Years, the Checklist and the timeline get the same ladder input, and stored Practicing / Ready for Assessment act as a floor (Decision 7).
  - **R22:**
    - `createWork` stamps `assignmentID` and `isSharedRow`. A launch step fills rows where they are nil from `WorkGrouping`'s guess, and the same fill runs after a restore (Decision 19).
    - One ownership rule replaces `WorkGrouping.visibleWork`, `WorkVisibility`, `ownWork`, `gatingWork`, `workInvolvesStudent`, and the owner-only reads in Today and the meetings.
    - Linked-copy matching reads `assignmentID`, falling back to the guess for unfilled rows.
  - **R23:** when the last participant finishes, the row closes through `WorkLogService`; `isOpen` then means the status.
  - **A3:** one `WorkAssignmentService.create(...)`, used by Quick New Work and `assign_work`, that adds check-ins through `addCheckIn` (school days) and writes the participant cross-links once.
- Files:
  - `Work/` (except `Work/Detail/WorkDetailView+Helpers.swift`, already changed by Phase 4), `Today/` (except `Today/Support/TodayScheduleRows.swift`, Phase 3's)
  - every caller of `WorkVisibility`, `visibleWork`, `ownWork`, `gatingWork` and `workInvolvesStudent` (grep), among them `ClassGrid/Children/`, `Presentations/Planning/WorkToShowFirst.swift`, `Presentations/Planning/BlockingAlgorithmEngine*.swift`, `Students/Detail/StudentDetailViewModel.swift`, `Students/Progress/StudentLessonRecords.swift`, `MCPNotebookTools+Schedule.swift` and `+StudentRecordWork.swift`
  - `Lessons/Checklist/ViewModels/ClassSubjectChecklistViewModel+LadderSteps.swift` (R14)
  - `AppCore/RootView/QuickNewWorkItemSheet+Actions.swift`
  - `Services/MCPServer/MCPNotebookTools+Work*.swift`
  - `ClassGrid/Engine/`, `ClassGrid/Children/`
  - `Students/Progress/StudentChecklistState.swift`, `ProgressionTypes.swift`, `StudentAnalysisService.swift` (the predicate)
  - `ParentReports/Services/MonthlyReportContextBuilder.swift` (the predicate only)
  - `CurriculumMap/CurriculumMapLoader.swift`
  - `Students/Meetings/` (only `MeetingWorkSnapshotHelper`, `MeetingInsightsService`, and `MeetingQueueModel`'s stuck count)
  - the launch steps and the after-restore hook.
- Cost: $30–55, ~1–2% (xhigh, seven items, wide).
- Done when:
  - The iOS app and the Mac build.
  - The work, triage, Today, check-in, WorkLogService, practice, Class Grid engine, checklist state, curriculum map, meeting snapshot and MCP work suites pass.
  - New tests: logged work leaves Attention; work-page Done settles Monday's missed check; Record Practice yesterday reads fresh in every place; a month's rest doesn't wake as 28 days untouched; Checklist Practicing makes Practice work; a shared project finished child by child closes; the launch fill gives linked copies one `assignmentID`.
- By hand: none.

## Phase 6: Lesson order, year plan and prerequisites
- Who: phase session (Opus 5.5, high).
- Needs: 4, 5
- Steps:
  - **R21:** one `LessonOrder` (sort, next, previous): order, then `sortIndex`, then name, then id. It is used by `PlanNextLessonService`, Unlock, the ready queue and Groups (`BlockingAlgorithmEngine+SequenceOrder`), the Class Grid, the Lessons screens, Claude's curriculum support and the meetings' tie code. Renumber a sub-area when a tie is found (on load, written once).
  - **A15:** the lesson editor rebuilds `sortIndex`.
  - **R17:**
    - Move the year plan's cascade into `YearPlanPacing.reschedule(...)`, which the screen and `update_year_plan_entry` both call.
    - `schedule_presentation` uses the dated promotion, and `update_presentation_roster` promotes an added child's entry.
    - The entry repair runs wherever the index is built, and adds the case of an entry promoted into a presentation that no longer exists (Decision 16).
  - **A16:** year-plan Remove skips the entry instead of deleting it.
  - **A6:** prerequisites: an editor on the lesson page, an `update_lesson` field, and a readiness reason ("check first: X not yet presented") in the Checklist and ready-queue rules.
- Files:
  - `Planning/Services/`, `Services/Progression/`, `Presentations/Planning/BlockingAlgorithmEngine+SequenceOrder.swift`
  - `ClassGrid/Engine/ClassGridEngine.swift` and `ClassGridEngine+Checklist.swift` (sort and readiness)
  - `Lessons/` (editor, scope map), `Repositories/LessonRepository.swift`
  - `Students/YearPlan/`, the YearPlan services (`YearPlanPromotionService`, `YearPlanEntryRepair`, `YearPlanPacing`), `PresentationRecordIndex*.swift`
  - `Services/MCPServer/MCPNotebookTools+YearPlanWrites.swift`, `+ScheduleWrites.swift`, `+PresentationEdits.swift`, the curriculum and lesson tools
  - `Students/Meetings/Workflow/MeetingDraftModel+Fields.swift` and `MeetingLessonDecisions.swift` (calls to `LessonOrder` only)
- Cost: $12–25, ~1%.
- Done when:
  - The iOS app and the Mac build.
  - The lesson order, plan-next, ready queue, Groups, Class Grid, year plan and MCP year-plan, schedule and lesson suites pass.
  - New tests: two lessons tied on order give the same "next" everywhere; Claude's year-plan move shifts the successors; Remove skips; a prerequisite holds a child back with its reason.
- By hand: none.

## Phase 7: Who's in class, departures and meetings
- Who: phase session (Opus 5.5, high).
- Needs: 3, 6 (6 owns `LessonOrder` and the year-plan services the departure cascade uses)
- Steps:
  - **R7:** one `CDStudent.isInClass(on:)` / `isInClass(during:)`. A departed child with no date is out; one with a date is in through her last day.
    - Readers that move onto it: `isEnrolled` call sites that mean "in class", `AttendanceRoster.wasEnrolled`, `isActive(in:)`, `ClassroomShareScope`, the monthly report queue (in class that month), and `update_work`'s default targets (skip departed children's copies).
    - `StudentRepository.updateStudent` writes status and date together and runs the departure cascade. The cascade covers the year plan, open work and Phase 3's `takeOutOfGroups`, offered on the screen and done by Claude.
    - Re-enrolling un-skips the entries her departure skipped (through Phase 6's year-plan services).
  - **R8:** a meeting's Re-present and Ready take effect at the tap (Decision 6). Re-present plans the lesson again at once, and Ready puts the next lesson (`LessonOrder.next`) On Deck; both are undone through `MeetingCloseToken`. Complete then has nothing left to carry out.
  - **R13 (meetings part):** meeting cadence counts in school days, with the year-start reset. Settle whether an unfinished meeting counts as met (it doesn't).
  - **A19:** a child who never met counts as late, so the comment and the guard agree.
- Files:
  - `Students/` (repository use, departure, `StudentDeparturePlans.swift`, `Meetings/Workflow`, `Meetings/Data`, `MeetingQueueModel`), `Repositories/StudentRepository.swift`
  - `SchoolYear/SchoolYearScoping.swift`, `Attendance/Rules/AttendanceRoster.swift`, `Sharing/ClassroomShareScope.swift`
  - `ParentReports/ParentReportsQueueView.swift`
  - `Services/MCPServer/MCPNotebookTools+WorkStatus.swift`, `Work/Completion/WorkLogService.swift` (targets only), the MCP student tools
- Cost: $12–25, ~1%.
- Done when:
  - The iOS app, the Assistant (`ClassroomShareScope` is shared) and the Mac all build.
  - The roster, departure, year-plan cascade, attendance roster, share scope, meetings, report queue and MCP work and student suites pass.
  - New tests: Maya leaving Friday stays on every screen through Friday; a departed copy isn't closed by `update_work`; Re-present on one device plans the lesson with no Complete; re-enrolling un-skips.
- By hand: none.

## Phase 8: Notes, reports, level history, guardians and rollover
- Who: phase session (Opus 5.5, high).
- Needs: 7
- Steps:
  - **R1:** one helper picks the notes for a child's report, used by `ReportGeneratorService` and the rollover's copy. Before drafting, other enrolled children's names in a note become "a classmate" (the quick-capture name matcher finds them). Decision 3.
  - **R9:**
    - The Progress tab's sequence notes also match `searchIndexStudentID` (one-child notes).
    - One "about her" predicate (a fetch predicate plus an in-memory check, with a switch for whole-class context notes) replaces the six copies: `StudentNotesViewModel`, `StudentAnalysisService`, `SequenceRecapDataLoader`, `ReportGeneratorService`, `StudentsViewModel+Caches`, `StudentProgressTabViewModel` and `TrackFilteredListLoader`.
    - Community-meeting and calendar notes count as context.
  - **A11:** "last observed" uses the creation date and leaves out notes the app writes itself.
  - **A10:** `TagHelper.canonicalTags(_:existing:)` (in `Models/TodoTag.swift`) for every note writer; Claude's tags gain the stored color.
  - **A17:** Siri's Log Observation posts `.noteDidSave`.
  - **A20:** check whether `update_observation` with no children widens a presentation note to the whole class; fix it if so.
  - **A12:** to-do chips come from student ids, not the stored name tag; renames and deletions follow.
  - **A8:**
    - Every level change writes a `CDLevelChange` through `StudentRepository`; one undone the same day removes the pair.
    - The promotion line reads the history.
    - Monthly reports read the level she had that month.
  - **A9:**
    - A launch step fills `Guardian.personID` where it is nil by matching email, then phone, across children, and runs after a restore too (Decision 19).
    - Editing a guardian updates every row with that id, and "receives reports" follows the person.
    - The guardian sheet names the siblings.
  - **A8 (rollover part):** rollover outcomes default from next year's grade (4th → Upper, 7th → Adolescent, from `SchoolYear/FloridaGradeCalculator.swift`, read only), with the session's first day (Phase 1's field, if set) as the default effective date.
- Files:
  - `ParentReports/`, `Notes/`, `Models/Note*.swift`, `Models/CDUnifiedNotes+Helpers.swift`
  - `Students/` (notes, progress, caches, overview level badge), `Students/…/StudentAnalysisService.swift` (the notes part)
  - `Topics/TopicDetailViewModel.swift`
  - `Students/Rollover/` (the report-note filter, and the rollover defaults)
  - `Repositories/StudentRepository.swift` (level writes)
  - `Todos/` (chips, `TodoTag`, `NewTodoForm`)
  - `Services/MCPServer/MCPNotebookTools+FollowUps.swift`, `+ObservationBatch.swift`, `+Writes.swift`
  - `Siri/LogObservationIntent.swift`
  - the launch steps and the after-restore hook
- Cost: $20–40, ~1–2% (nine items; A9 is M–L).
- Done when:
  - The iOS app and the Mac build.
  - The report generator, report draft, notes, progress, recap, insights, topics, to-do tag, MCP observation and follow-up, Siri observation, student repository and guardian suites pass.
  - New tests: Leo's name never reaches Maya's draft; a one-child lesson note counts in her sequence card; a typo fix doesn't move "last observed"; a mis-tap leaves no level history; editing a mother on one child changes her on the sibling; a 3rd grader in Lower defaults to Upper at rollover.
- By hand: none.

## Phase 9: School session, time zone and the front desk
- Who: `feature-phase` agent on Fable 5.2 (high), Decision 21. Day math everywhere, and both apps.
- Needs: 7 (and through it 1 and 2)
- Steps:
  - **A4:** `AppCalendar` (`AppCore/AppCalendar.swift`) uses the classroom time zone from the shared settings row, and falls back to the device's zone when unset. The zone is cached and read once the store has opened (it opens off the main thread); before that, and on a bad identifier, it is the device's zone. Attendance records, locks and sends match by the day's range instead of exact midnight (Apple guidance). The guide's Settings › Classroom sets it, defaulting to the Mac's zone on first save. Every `startOfDay` and day match follows from that. Watch days that start at 1:00 (DST); see Apple guidance.
  - **R20:**
    - Session first and last day go on the same row, set in Settings › Classroom.
    - `SchoolDayChecker.isNonSchoolDay` treats days outside the session as days off, and so do both apps' readers.
    - "Day N" (`AttendanceSchoolDayCount`), the share cutoff (`ClassroomShareScope`), the year start (`SchoolYear`, `ProjectActivity.currentYearStart`, `FloridaGradeCalculator.schoolYearStart`, made one) and the front-desk reminders (`FrontDeskEmailReminder`, the Assistant's `ArrivalReminder`) read them.
    - Unset keeps today's behavior.
  - **R18:** a derived "changed since reported": marks whose `modifiedAt` is after the day's latest send. Both apps show "2 changes since 9:02 · Send an update", and so does `attendance_for_day`.
  - **A5:** the shared row is the only source of the front-desk email's settings, and one report builder serves both apps.
  - **A1 (readers only, Decision 9):** every reader leaves an `arrivalClosed` channel row out of sends, and the Late rule can read a close time from it. Add a Tide row for the writer in the next release.
  - **A18:** age, grade and the birthday cake use the app's fixed Gregorian calendar.
- Files:
  - `AppCore/AppCalendar.swift`, `SchoolYear/`, `Services/Calendar/`, `Work/Support/SchoolDayChecker*.swift` (not `Students/Rollover/`, Phase 8's, which runs beside it)
  - `Attendance/Email/`, `Attendance/Rules/AttendanceSchoolDayCount.swift`, `AttendanceLatePhase.swift`, `Attendance/…/AttendanceRow.swift`
  - the ParentLocker files, `Sharing/ClassroomShareScope.swift`
  - `Settings/Classroom/`
  - `Services/MCPServer/MCPNotebookTools+Attendance.swift` (the `attendance_for_day` line)
  - `Daybook Assistant/FrontDesk/`, `Daybook Assistant/Reminders/`, `Daybook Assistant/Attendance/` (day-off rules)
- Cost: $20–40, ~1–2% (xhigh, both apps).
- Done when:
  - The iOS app, the Assistant and the Mac all build.
  - The calendar, school day, school year, attendance email, ParentLocker, front desk, reminder and share scope suites pass, plus the Assistant's FrontDesk, Reminders and Attendance suites.
  - New tests, the first two run with `TEST_RUNNER_TZ` set to another zone and asserting first that `TimeZone.current` is that zone: a device in another zone reads the same day; a fixed-zone day that starts at 1:00; a summer weekday is off once the session is set; a 10:30 Late after the 9:00 send shows one change; a close row isn't counted as a send.
- By hand: none.

## Phase 10: Final check
- Who: `feature-phase` agent (Opus 5.5, high); the conductor runs the full builds and whole suites itself (Decision 20). The cold review is a `general-purpose` agent on Fable 5.2 (Decision 21) over the combined diff `e25eb65d8..main` against this plan and the review.
- Needs: 1–9
- Steps:
  - The full iOS app, Assistant and Mac builds on main.
  - The whole notebook suite on the leased iOS simulator and the whole Assistant suite on the leased SE (iOS 26.5).
  - Fix what fails (the errors name files; the files map to phases).
  - Left over from Phase 3 (outside its files): `Students/Presentations/ScheduledDateEdits.swift` should use `awayDay.touches(children:)`, so the lesson sheet shows a turn or an Out day even when no child is away; the `WeekPlanHeader.swift` legend still says "Two lessons at the same time" (should match "lessons at overlapping times").
  - The cold review, and one round of fixes for what holds up.
  - Update `MCP_SERVER.md`, `Work_Models_Best_Practices.md`, `LESSON_PRESENTATION_WORK_INTEGRATION.md` and `SIRI.md` where behavior changed.
  - Set the review's status line ("Fixed <date> (<commit>)").
  - Tide rows: device checks (one row per phase's list); "Roll out schema 25 to every device in one sitting, after the Production deploy"; "Turn on the arrival-closed writer in the release after that".
- Cost: $15–35, ~1% (two whole suites, a cold review of the whole diff, one fix round).
- Done when: all three builds pass and both whole suites pass (counts in the final message), and the final message has a table of R1–R25 and A1–A20, each with its commit or the decision that settled it.
- By hand: none.

## Running a phase (phase sessions read this)
You were started by the conductor. Danny accepted this plan and is likely away. Don't ask him anything and don't wait on him. **Don't edit this plan file**: other phases are running beside you, and the conductor writes Progress and Decisions. Everything you'd add goes in your final message.
0. Get your session id: run `echo $CLAUDE_CODE_SESSION_ID` (it isn't filled in for you anywhere else). If your phase needs other phases, wait for them first: run `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/domain-logic --needs <their numbers, comma-separated, e.g. 1,2>` with `run_in_background`, and end your turn; you're woken when it exits. On "Go ahead" carry on. On anything else (a needed phase stopped, the run braked, a time-out), stop: mark yourself stopped (step 7) unless the run was braked, and report its line.
0b. Make sure your branch starts from local main, which holds every phase merged so far (nothing is pushed, so `origin/main` is behind): if `git merge-base --is-ancestor main HEAD` fails, run `git merge main`.
1. Do the phase's steps, building only its smallest target and running only its `-only-testing:` suites (`~/.claude/CLAUDE.md` › Xcode builds, and "Rules every phase follows" above). Test on simulators headless (`xcodebuild test`, `xcrun simctl io <udid> screenshot`). Leave tapping, clicking and screen-driving to the conductor: list what to check under "By hand" in your final message.
2. If a decision comes up that the plan didn't settle, take the safer option that's easier to undo, add a `Review choices` row in Tide for Danny, and put it under "Decided" in your final message.
3. Check every "Done when" item. Before each fix round, run `~/.claude/bin/plan-cost session`. If one item still fails after two tries, or the phase has cost more than twice the top of its estimate, stop.
4. Make every "not verified", "for your review" or "check on a device" item from this phase a row in the app's list in Tide (`Areas/App Development/Cosmic Daybook/To do.md`, `add_action`), skipping ones already there. Any repo doc line about it keeps one plain sentence plus the row's `tide://` link.
5. Update the build board, if the plan lists one (`build-board` skill, then `~/.claude/bin/board-touch <url>`).
6. Merge: read `~/.claude/skills/close-out/SKILL.md` and follow it (it can't be invoked as a skill). Danny's acceptance of the plan is his go-ahead. Make these changes to it:
   - In its step 2, bring the branch up to date with **local** `main` (`git merge main`), not `origin/main`.
   - Right after the squash commit, before releasing the lock, mark the phase merged: `~/.claude/bin/plan-wait --repo "/Users/dannydeberry/Developer/Maria's Notebook" --prefix plan/domain-logic --mark <N>`. Phases waiting on you start from that.
   - Before its step 4, take the merge lock: `~/.claude/bin/plan-merge-lock take "/Users/dannydeberry/Developer/Maria's Notebook"` (run it with `run_in_background` if it says it's waiting). Release it with `plan-merge-lock release "/Users/dannydeberry/Developer/Maria's Notebook"` right after the squash commit, and also if you stop before that commit.
   - Skip its step 4b (the conductor keeps the plan's status and the docs map) and its step 5 (no push).
   - Wherever it says "stop and ask", stop instead: release the lock, don't merge, and report it.
7. If you stopped without merging, mark it so the phases waiting on you stop too (`plan-wait … --mark <N> --stopped`), and shut down your simulators (`~/.claude/bin/sim-lease --done`). close-out releases them otherwise.
8. End with this line first, so the conductor's note shows it: `Phase <N> done (<commit>). Session <your id from step 0>. By hand: <list or none>.`, or `Phase <N> stopped: <plain reason>. Session <id>. Nothing merged.` Then, under it, any "Decided:" items and anything that differed from the plan.

## If you are a phase agent (Decision 20)
Follow "Running a phase" above, with these changes:
- **Step 0:** skip `plan-wait`. The conductor started you only after your needs merged. Run `git merge main` first (your worktree starts from the last *pushed* main, which lacks this plan and the earlier phases), then read this plan.
- **Effort:** if you are `feature-phase-deep` you already run at xhigh; do the delicate parts yourself (no nested agents). Use helper agents only if your tools offer them.
- **Step 3:** skip `plan-cost session` (inside an agent it measures the conductor's whole session). Keep "two tries, then stop".
- **Step 5:** skip the board; the conductor updates it.
- **Step 6 (Decision 22):** don't merge, and don't take the merge lock or mark the phase: a guard refuses agents' git commands in the primary checkout. Commit everything on your own branch, run `git merge main` so it contains local main, and end with `Phase <N> ready (<branch tip sha>)`. The conductor squashes it onto main and marks it. Use `--stopped` only for a real failure (step 3's two tries).
- **Step 8:** your reply is at most 15 lines, starting with the done or stopped line (no session id: write `Session: agent`). Then the files changed, build and test counts, Decided items, and what differed from the plan.

## Open questions
None. Everything left open is settled under Decisions; anything new goes to Tide as a `Review choices` row.
