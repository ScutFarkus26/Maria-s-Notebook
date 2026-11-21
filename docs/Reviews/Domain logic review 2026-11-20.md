# Domain logic review 2026-11-20

> **Fixed 2026-11-21** (4d5eb1c9c). Found at main e25eb65d8 (2026-11-20); fixed by <../Plans/Plan - Domain logic fixes.md>. Where each item landed is at the end.
> In short: the top 25 ways to improve the app's classroom rules. Most come from one pattern: a rule that lives in a screen's view model gets copied by Claude's tools, Siri or the command bar, and the copies drift.

**Scope.** "Domain logic" here means the classroom rules and how they are kept: lessons and mastery, work, attendance, the school calendar, students and meetings, notes, schedules, Restock and to-dos. It leaves out UI, sync plumbing, build and speed. This is not a bug hunt, but it includes real bugs, marked **BUG**. Five read-only reviewers each took one area, and a sixth compared Claude's tools, Siri, the command bar and restore against the screens. Each of the 25 was then checked by hand at the cited lines; #25 is the one marked Plausible, and the "Also found" list rests on the reviewers' reading. Nothing was built or run. Paths are under `Cosmic Daybook/`.

**Already decided, so left out:** year-plan completion is derived; Planned only on the next lesson; checklist Clear is a full reset; sections follow the earliest lesson; the week strip anchors on today; no blanket autosave; reopen can't restore check-ins a close skipped (needs a schema change, already open); a year-plan entry hides a child from Ready; AI planning treats confirmation as proficient.

## The pattern behind most of these

Where a shared service already exists (`WorkLogService.log`, `RestockService`, `StudentRepository.updateStudent`), Claude, Siri and the screens agree. Where the rule lives in a view model (the year-plan cascade, the Present-a-lesson follow-ups, "Here" and "Absent" on the attendance grid, mastery), every other path writes its own copy. So the biggest single improvement is a habit: **an action's rule goes in one domain function, and every path calls it.** Items 2, 5, 6, 7, 11, 12, 16 and 17 are that habit applied.

## The top 25

Ranked by how much each affects the teacher's records and her trust in them. Size: S (an hour or two), M (a day), L (several days). "Schema" means a Core Data model change (and a new backup format). Shared-store schema changes are the most expensive: they need Production CloudKit and both apps.

### 1. Parent reports can name other children
`ParentReports/Services/ReportGeneratorService.swift:44-47` gives each child's report every flagged whole-class note and every group note that names her. The note text goes into the draft prompt word for word, and the prompt only forbids comparing children, not naming them. "Maya and Leo argued over the bead frame" can reach both families. **Fix:** before drafting, swap other enrolled children's names out (the name matcher already finds them), or ask per note whether a group note may go home. One helper, which the school-year rollover's copy of the filter also uses. S–M, no schema.

### 2. Mastery has three writers that disagree
Claude's `mark_mastered` (`Services/MCPServer/MCPNotebookTools+Mastery.swift:196-214`) flips the latest row only and leaves the child's work open. The Checklist closes the work, but as Finished rather than Mastered (`Lessons/Checklist/Model/ChecklistCellRecords.swift:42-60`). The presentation sheet's pill does neither. Some readers count only the state, others the date too. The same-id merge copies `masteredAt` without raising the state (`Services/Migrations/DataCleanupService+DeduplicateLessons.swift:132-138`). Closing work as Mastered writes no mastery mark. And outside the presentation sheet, mastery can't be taken back. **Fix:** one `MasteryMarking.mark/unmark` that marks every row she has, closes her open work, and is called by the Checklist, the pill, work completion and Claude. Your call: whether that close is Mastered or Finished (Finished was made deliberately on 2026-10-13 and never counts as mastery), and whether closing work as Mastered should offer the mark at the time (never backfilled). Also: "already mastered" means any mastered row, and one rule for reading it (`SequenceStanding.isMasteryMark`). S–M, no schema.

### 3. BUG: a status pill on a lesson she never had records it as "given today"
In the sequence recap, tapping a status on another lesson the child has no record for creates one with no presentation and today's date (`Students/Presentations/PresentationDetailViewModel+MasteryTracking.swift:156-165`). The parent report then says she received the lesson this month, and Three Years dates it today. The Checklist's version of this was fixed on 11-03 (#8); this path wasn't. **Fix:** use the Checklist's undated attachment, and make `PresentationRecordIndex.given` the one answer to "was it given". S, no schema.

### 4. BUG: the due date doubles as the next check day, so logged work stays in Attention
Quick New Work and Claude's `assign_work` store the guide's due date in `dueAt`. Every scheduling path overwrites the same field with the check day (`Work/CheckIns/WorkCheckInService.swift:62` and four others). Logging the work never clears it (`Work/Completion/WorkLogService.swift:95-121`), and triage sends any past `dueAt` to Attention (`Work/Triage/LessonsAndWorkTriage.swift:168`). The guide logs Keep Working on Monday, and the work sits in Attention every day after. A "due Friday, check Wednesday" loses Friday the moment Wednesday is dragged. **Fix:** derive the next check from the earliest scheduled check-in; keep `dueAt` only for a due date the guide set; triage reads the two separately. S–M, no schema.

### 5. One attendance "mark" function in the store, so Claude can't get around the rules
The store checks only role and lock (`Attendance/Store/CDAttendanceStore.swift:245-250`). Everything else lives in the callers, and Claude's `mark_attendance` (`Services/MCPServer/MCPNotebookTools+Attendance.swift:186-226`) skips it:
- **BUG:** Claude's "unmarked" goes through `updateStatus`, not `unmark`. A duplicate copy's mark then wins back, as the store's own comment warns (`:252-258`), so Claude says "unmarked" and she stays marked.
- It marks days in the future, and children who have left or are test students. A record puts a child on that day's roll, so a girl who left in October reappears on the grid, the here count, the front-desk email and ParentLocker.
- "Absent" for a child Close Arrival already marked absent changes nothing, so undoing Close Arrival later wipes the guide's absence.
- Days off get four different answers (grid warns, Assistant hides, Siri asks, Claude is silent).

**Fix:** `CDAttendanceStore.mark(student:status:reason:on:)` checks the roll, the lock and the role; it routes Unmarked to `unmark` and claims an automatic absence. One day-off policy for every path. M, no schema.

*A decision to revisit:* `docs/Technical notes/SIRI.md` says the ahead-of-the-day rule (absences and notes only) sits in the screens, not the store, **on purpose**, so Claude and restore stay free. Restore should stay free; the question is only whether Claude should follow the screens' rule.

### 6. Present-a-lesson decisions filed by Claude or the command bar leave the child on Keep Watching
The sheet's Done writes each child's follow-up row for every decision (`Presentations/Session/PresentationSessionCommit.swift:182-238`). Claude and the command bar stop at `CaptureFollowUpPersistence.persist` (`Presentations/Workflow/CaptureFollowUpPersistence.swift:36-63`): Ready only confirms her, and Practice only makes the work. Her row keeps the "watch" default, so she stays in Following as Keep Watching. **Fix:** move the sheet's private follow-up-row writing into `persist`. M, no schema.

### 7. "Was she in the class then?" has four answers
- `isEnrolled` reads the status alone.
- `AttendanceRoster.wasEnrolled` treats a departed child with no date as gone (`Attendance/Rules/AttendanceRoster.swift:44-47`).
- `isActive(in:)` treats the same child as present (`SchoolYear/SchoolYearScoping.swift:14-18`), and the attendance status report uses it.
- The departure cascade runs only in the view and the rollover, not in `StudentRepository`.

Record on Monday that Maya leaves Friday: she vanishes from the roster, Meetings and work assignment that day but stays on attendance until Friday. The monthly-report queue lists children enrolled *today*, not that month. Claude's `update_work` closes departed children's linked copies, and departed children stay in co-teacher groups. **Fix:** one `CDStudent.isInClass(on:)` / `(during:)` that every reader uses, and the repository writes status and date together and runs the cascade. M, no schema.

### 8. Meeting decisions are half on one device
Re-present closes the work as Incomplete in the synced store at once (`Students/Meetings/Workflow/MeetingDraftModel+Decisions.swift:24-31`). But planning the lesson again happens only at Complete, from a draft kept in that device's settings (`Students/Meetings/Data/MeetingPersistenceService.swift:104-130`). The same goes for Ready-for-Next and the undo tokens, and backups don't carry any of them. Tap Re-present on the iPad, finish on the Mac (or never finish), and the work stays closed with nothing planned and no undo. **Fix:** carry out Re-present and Ready at the moment of the tap, or keep an unfinished meeting as a synced record. M (tap-time) or L (synced draft, needs a schema change).

### 9. BUG: lesson notes about one child never reach her Progress tab, and "is this note about her?" is written six ways
Sequence notes are found only through note-student links (`Students/Progress/StudentProgressTabViewModel.swift:229-236`), and links exist only for notes about two or more children (`Models/CDUnifiedNotes+Helpers.swift:238-244`). So a Quick Note about Maya alone, tagged with a lesson, never counts in her sequence card. The same "about her" question is written separately in at least six files. Whole-class context notes (community meeting lines, calendar notes) land on all 30 children's Notes tabs and feed Writing Help. **Fix now:** also match `searchIndexStudentID`. **Then:** one shared "about her" predicate with a switch for context-only notes. S, then M; no schema.

### 10. Lesson notes from the sheet are dated the day they're written, not the day it was given
The sheet offers Yesterday and Pick a Day, but `persistObservations` takes no date (`Presentations/Workflow/PresentationOutcomePersistenceService.swift:27-33`), and Done never re-dates. Claude and the command bar each re-date afterwards with their own code. Friday's lesson recorded on Monday files its notes on Monday, which can be the wrong month for the parent report. **Fix:** give `persistObservations` an `observedOn:` and drop the two after-the-fact copies. S, no schema.

### 11. "The check happened" has three writers
The work page's Done and Claude's `complete_check_in_on` call `WorkCheckInService.markCompleted` (`Work/CheckIns/WorkCheckInService.swift:39-48`). It touches only that one check-in. It doesn't settle earlier missed ones, update linked copies or offer undo, and it redates to now (Claude keeps the planned date, and can stamp a future day). Today's Done and the strip go through `WorkLogService`. Done on the work page leaves Monday's missed check-in Scheduled, so the work stays overdue. **Fix:** route both through `WorkLogService` as a "seen, unchanged" entry, with one rule for the date. S, no schema.

### 12. Four copies decide which presentation a lesson lands on
Claude matches the exact set of children and treats the same day as an edit. The command bar uses the same match but has no same-day check, so saving one capture twice makes two presentations. Siri takes any waiting plan holding the child and has no same-day check either. The sheet records the plan for the children there and moves absent ones to their own plan (`Presentations/Session/PresentationRecorder.swift:57-68`). **Fix:** one `PresentationRecorder.resolvePlan(lesson:present:on:)` for all four. M, no schema.

### 13. One clock for "how long since"
Work "gone quiet" is measured five ways:
- `AgingPolicy`, which calls itself "the single stale threshold": 10 school days since the latest touch, check-in or note.
- The Checklist dot: 14 weekdays from `lastTouchedAt ?? createdAt`, with holidays counted and notes and check-ins ignored (`ClassGrid/Engine/ClassGridEngine+Staleness.swift:7-27`).
- Meetings: days since created.
- Meeting insights: a hard-coded 14 days.
- Meeting cadence: calendar days, while "due for a lesson" uses school days.

Resting doesn't pause the clock either: `lastMeaningfulTouchDate` ignores `restingUntil` (`Work/Support/WorkAging.swift:43-68`), so work set aside for a month wakes up at the top of Gone Quiet. **Fix:** one `WorkNeglect` rule in school days, with the end of a rest counted as a touch. Anything that really means "age since assigned" gets its own name. M, no schema.

### 14. "Practice" and "Practicing" mean different things in different places
- **BUG:** `createWork` picks the default kind from the `presentationID` *argument* before it resolves one (`Work/Support/WorkRepository.swift:119-120`). The Checklist's Practicing step, its mastery close and `assign_work` pass none, so practice work is labeled Follow-Up and missing from Record Practice.
- `isPractice` counts a *scheduled* check-in with purpose "Practice" before it happens, and after a close skips it (`Work/CheckIns/WorkCheckInEntity.swift:120-133`). That predicate is copied as a string in four files.
- Three Years counts practice on the ladder; the Checklist and the timeline don't. The recap pill writes a stored "Practicing" state that the ladder never reads.

**Fix:** default the kind from the resolved presentation; one practice predicate that requires a completed check-in; and one ladder input everywhere. Either drop Practicing from the pill or let the ladder treat the stored state as a floor. S–M, no schema.

### 15. BUG: an "every week" schedule edit misses days that have their own change
An every-week edit updates the block and only the chosen day's change (`Schedules/Services/TimetableService+Blocks.swift:143-149`). This Day and After moves later changes to the new copy without applying the edit (`:316-337`). A "changed" change stores the block's values in full. So if Nov 24 has a one-day time move and Danny adds Lucy to the group every week from Nov 17, Nov 24's group shows without her and gives no away warning. **Fix:** apply the edit's changed fields to each later change, wherever that change still holds the old value. S–M, no schema.

### 16. One "busy" picture for the schedule
- The planner's "Everyone's free" reads only other people's groups and Danny's own lesson starts (`Schedules/Services/AwayTimes.swift:119-131`). It ignores his adolescent-room turn, so it can offer 10:45 while the Schedules page flags the same lesson.
- The clash badge flags only lessons at exactly the same minute (`Presentations/Planning/DayHalfPlanner.swift:203-219`), while free times treat lessons within 30 minutes as busy. The exact-minute rule is the co-teacher plan's decision 7; an overlap rule would change that decision, now that `LessonLength.assumedMinutes` exists.
- On Danny's Out day his lessons are still placed and warned about everywhere but the Assistant.
- Children leaving early and overlapping blocks (a child in two groups at 9:15) aren't checked at all.

**Fix:** one per-day busy model built from the resolved `ScheduleDay` (groups, turns, Out Today, leaving early, lesson-on-lesson overlap). The picker, the cards, the day badge, the Schedules warnings and Claude all read it. M, no schema.

### 17. Year-plan moves live in a view model
The year plan's reschedule shifts every later entry in the sequence and keeps their spacing (`Students/YearPlan/StudentYearPlanViewModel.swift:203-239`). Claude's `update_year_plan_entry` moves only the one entry (`Services/MCPServer/MCPNotebookTools+YearPlanWrites.swift:102-112`), so its successors stay ahead of it. `schedule_presentation` uses the undated promotion (11-03 #20 again; that fix only reached `reschedule_presentation`), and roster edits over Claude never promote an added child's entry. The promotion repair runs on one screen only. **Fix:** move the cascade into `YearPlanPacing.reschedule` and use the dated promotion everywhere. Later, derive promotion from the record, as completion already is. S–M, then L; no schema.

### 18. A day already reported can drift from what the school was told
A send records only when it happened and who sent it (`Attendance/Email/AttendanceEmailSendEntity.swift`). ParentLocker follows today only, by design. Assistants can still change any unlocked day, and locks are set only by hand. The 9:00 email says Maya is absent, she arrives at 10:30, and nothing says the school's copy is now wrong. **Fix:** a derived "changed since reported" (marks whose `modifiedAt` is after the day's latest send). Show "2 changes since 9:02 · Send an update" in both apps and in `attendance_for_day`. S–M, no schema.

### 19. Attendance totals ignore the school calendar and enrollment
The status report counts every record in the range (`Attendance/Reports/AttendanceStatusReport.swift:106-120`). The class summary's "school days" means days that have marks, and making a day off leaves its records in place. A vacation marked absent ahead, then a storm day, gives 5 absences over 4 school days. There is no days-present-out-of-days-enrolled figure, which is what schools ask for. **Fix:** one tally that counts a record only on a school day she was enrolled, and reports days enrolled, present, absent and late. Say so when a day with marks becomes a day off. S–M, no schema.

### 20. The school year has a start date but no real first and last days
The year is a month and day on the guide's devices (`SchoolYear/SchoolYear.swift:40-52`), which the Assistant can't read. Summer weekdays count as school days, so both apps schedule the 8:50 and 9:00 front-desk reminders through the summer. "School days since" counts summer, and one stray August mark becomes Day 1. **Fix (cheap):** a "Summer break" action that writes non-school days, which every reader already honors. **Full fix:** session dates on the shared settings row. M (cheap) or L (shared schema).

### 21. Six rules for lesson order in a sequence
- `PlanNextLessonService.findNextLesson` sorts by order only (`Planning/Services/PlanNextLessonService.swift:39-45`). It drives plan-next, Unlock, the meeting's Complete and the work page.
- Groups and the ready queue break ties by name (`Presentations/Planning/BlockingAlgorithmEngine+SequenceOrder.swift:59-75`).
- The Checklist breaks ties by `sortIndex` and then name; the Lessons screens by name and then id.
- Claude and Meetings each have their own.

Two lessons can share an order (older lessons took 0, and two devices can each take max+1). When they do, plan-next can skip one while Groups names it as next. **Fix:** one `LessonOrder` (sort, next, previous) used everywhere, and renumber a sub-area when a tie turns up. S–M, no schema.

### 22. Linked work copies need a real assignment id
"Whose work is this?" has five rules (`WorkGrouping`, `WorkVisibility`, the Class Grid's `ownWork`, readiness `gatingWork`, and Today/Meetings reading the owner only). All of them rest on the 60-second same-title guess for which copies belong to one assignment (`Work/Support/WorkGrouping.swift:321-354`). Shared project work never shows for the other children on it. **Fix:** an `assignmentID` that every copy from one assignment shares, plus a "shared row" flag, both filled once at launch by running today's guess. One ownership rule is then built on them. M–L, **schema** (two optional attributes, private store only).

### 23. Two meanings of "open work"
`CDWorkModel.isOpen` treats a row as closed once every participant is stamped done (`Work/Models/WorkModelEntity.swift:147-152`). Triage and fetches go by status only. Claude's `completed_by` stamps one child at a time and never closes the row. A shared project finished child by child over Claude still reads Working, goes stale, and refuses Add Check-in as "closed". **Fix:** when the last participant finishes, close the row through `WorkLogService`; then `isOpen` means the status. S, no schema.

### 24. Taking a child off a presentation keeps her confirmation
"Confirmed children ⊆ children on the presentation" is kept by Claude, student deletion and year-plan release. The detail sheet's Save and the Checklist's removal don't keep it, and the year-plan release's comment says they do. Take her off and add her back, and she reads as confirmed and ready for the next lesson. **Fix:** enforce it in the `studentIDs` setter (`Models/LessonAssignmentEntity.swift:107`). S, no schema. (The wider point is that `needsPractice`, `needsAnotherPresentation`, `manuallyUnblocked` and confirmations are all facts about one child stored on the shared group record. Moving them onto her history row is M–L and needs a schema change.)

### 25. A repeating to-do has no series identity
The next occurrence gets a random id (`Todos/Services/TodoCompletionService.swift:72-80`). The series is found by matching title, repeat and a 2-second window (`:148-159`), and duplicate cleanup folds only rows with the same id. Tick a weekly to-do on the iPhone while a Tide tick completes it on the Mac, and two next occurrences appear, both sent to Tide. **Fix:** derive the next occurrence's id from the completed one's, as `splitCopyID` does for blocks. The existing same-id cleanup then folds the pair, and a rename no longer breaks the series. S, no schema. *(Plausible; needs two devices completing it before they sync.)*

## Also found (worth doing, lower on the list)

- **A1.** **Arrival closed is worked out per device.** What counts as Late depends on memory each phone keeps, and a close with nobody unmarked writes nothing shared. The schema-free route is a channel row on `AttendanceEmailSend`, like `notExpected`, shipped in two releases. M–L.
- **A2.** **Restock stores "needed" twice.** The staple's level and its open needs. A Stocked staple with an open need is left alone, so the shelf says Stocked while the badge counts one to order. Let the later of the two win in `reconcile`. S.
- **A3.** **BUG: Quick New Work puts check-ins on closed days.** It calls `CDWorkCheckIn.make` directly (`AppCore/RootView/QuickNewWorkItemSheet+Actions.swift:67-73`); `assign_work` lands on the next school day. One `WorkAssignmentService.create`. S.
- **A4.** **Day-only dates use the device's own midnight.** A device in another time zone shows dates a day off and starts duplicate attendance days. Pin `AppCalendar` to a classroom time zone on the shared settings row. M, shared schema; ride the next one.
- **A5.** **The front-desk email's settings live in two places.** iCloud key-value storage for the notebook, the shared row for the Assistant. Make the shared row the only source. S.
- **A6.** **Prerequisites across sequences.** `prerequisiteLessonIDs` exists, shows and is backed up, but has no editor, no Claude field and no part in readiness. M.
- **A7.** **The adolescent room is found by its name** containing "adolescen". Give it its own lane kind (older builds read unknown kinds as a room). S–M, no CloudKit schema change.
- **A8.** **Level history keeps one step.** A mis-tap overwrites the real promotion date, and rollover defaults everyone to Stay though the app knows each child's grade. M, schema for real history.
- **A9.** **Guardians are stored per child,** so siblings carry separate copies of each parent. M–L, schema.
- **A10.** **Note tags from Claude lose their `|color` suffix,** which splits one tag into two in the filter. S.
- **A11.** **"Last observed" uses the note's last edit,** so fixing a typo in a September note clears a stale flag. S.
- **A12.** **To-dos keep a child's full name as a tag** beside her id, so renames and deletions leave the old name. S–M.
- **A13.** **An attendance record's paired fields** (left-early status, return time, reason) are enforced only by `mark`, so restores can write odd pairs. A `normalize()` on save and restore, plus a `data_checks` line. S.
- **A14.** **The Assistant's Schedule shows "Nothing for this day"** outside the 14-day booking window. Say why instead. S.
- **A15. The lesson editor doesn't rebuild `sortIndex`** (`LessonEditDraft.swift:114-126`); Claude's tools and the drag do. S.
- **A16. Remove on the year-plan calendar deletes the entry** (`StudentYearPlanViewModel.swift:193-196`), against the skip-never-delete rule. S.
- **A17. Siri's Log Observation doesn't post `.noteDidSave`** (`Siri/LogObservationIntent.swift:58-63`); the other four note writers do. S.
- **A18. Age, grade and the attendance birthday cake use the device's calendar,** while birthday countdowns use the app's fixed Gregorian one; they differ on a device set to the Hebrew calendar. S.
- **A19. Meetings: a child who never met isn't counted late,** though `isLate`'s comment says she is (`MeetingQueueModel.swift:117-119`), and a meeting saved "not finished" still counts as met. S.
- **A20. Claude's `update_observation` with no children may widen a presentation note to the whole class** (reported by a reviewer's helper, not checked by hand). Check first; fix if real. S.

## Where each one landed

Checked 2026-11-21 against main 4d5eb1c9c: the iPhone, Mac and Assistant builds succeed, 5,166 notebook tests, 20 time-zone tests and 650 Assistant tests pass. "Mostly" lines name what's left; each is in the plan's Phase 10 leftovers.

| Item | Where | Result | Notes |
|---|---|---|---|
| R1 | Phase 8 (2379fb21d), fix A (b5e057e89) | Fixed | Report drafts call other children "a classmate", in work titles too. |
| R2 | Phase 4 (ee5314e55), fix C (b96b2ceea) | Fixed | One mastery mark everywhere; the last separate copies read the one rule. |
| R3 | Phase 4 (ee5314e55) | Fixed |  |
| R4 | Phase 5 (778d586cc), fix C (b96b2ceea) | Fixed | The due date stands apart from the next check. |
| R5 | Phase 2 (2adf0ebd2) | Fixed |  |
| R6 | Phase 4 (ee5314e55) | Fixed |  |
| R7 | Phase 3 (208cd6aa3), Phase 7 (feddeb717), fix A (b5e057e89) | Mostly | One in-class rule; a departure now finishes after her last day. A few screens still read the raw status. |
| R8 | Phase 7 (feddeb717) | Fixed | Older meeting drafts are still carried out at Complete. |
| R9 | Phase 8 (2379fb21d) | Mostly | One "about her" rule on five readers; "last observed" and two loaders aren't on it yet. |
| R10 | Phase 4 (ee5314e55) | Fixed |  |
| R11 | Phase 5 (778d586cc) | Fixed |  |
| R12 | Phase 4 (ee5314e55) | Fixed |  |
| R13 | Phase 5 (778d586cc), Phase 7 (feddeb717) | Fixed |  |
| R14 | Phase 5 (778d586cc), fix C (b96b2ceea) | Fixed | Practice only after a giving. |
| R15 | Phase 3 (208cd6aa3) | Fixed |  |
| R16 | Phase 3 (208cd6aa3), fix A (b5e057e89) | Fixed |  |
| R17 | Phase 6 (1be26969b), fix A (b5e057e89) | Fixed | The entry repair doesn't run after a restore, so restores stay exact. |
| R18 | Phase 9 (96a376623) | Fixed |  |
| R19 | Phase 2 (2adf0ebd2) | Fixed |  |
| R20 | Phase 9 (96a376623) | Fixed | The days-off grid doesn't shade summer. |
| R21 | Phase 6 (1be26969b) | Fixed |  |
| R22 | Phase 5 (778d586cc), fix C (b96b2ceea) | Fixed | A child's meeting still lists only the work she owns. |
| R23 | Phase 5 (778d586cc) | Fixed |  |
| R24 | Phase 4 (ee5314e55), fix C (b96b2ceea) | Fixed |  |
| R25 | Phase 3 (208cd6aa3) | Fixed |  |
| A1 | Phase 9 (96a376623) | Readers only | Decision 9: the writer comes in the release after schema 25 (Tide row). |
| A2 | Phase 3 (208cd6aa3) | Fixed |  |
| A3 | Phase 5 (778d586cc) | Fixed |  |
| A4 | Phase 9 (96a376623), fix B (a8926521f) | Mostly | Attendance, locks, sends and reminders follow the class's zone, set only from the picker. Time pickers and Claude's date parsing still use the device's. |
| A5 | Phase 9 (96a376623) | Mostly | The email reads the shared row; Settings still shows this device's copy. |
| A6 | Phase 6 (1be26969b) | Mostly | "Check first" shows in the ready queue, Today, Groups, Claude and the Checklist, not the Inbox planner. |
| A7 | Phase 3 (208cd6aa3) | Fixed |  |
| A8 | Phase 8 (2379fb21d) | Fixed |  |
| A9 | Phase 8 (2379fb21d) | Fixed | Matched by email and name; guardians have no phone field. |
| A10 | Phase 8 (2379fb21d) | Fixed |  |
| A11 | Phase 8 (2379fb21d) | Mostly | Reads the creation date and skips app-written notes; still reads student links. |
| A12 | Phase 8 (2379fb21d) | Fixed |  |
| A13 | Phase 2 (2adf0ebd2) | Fixed |  |
| A14 | Phase 3 (208cd6aa3) | Fixed |  |
| A15 | Phase 6 (1be26969b) | Fixed |  |
| A16 | Phase 6 (1be26969b) | Fixed |  |
| A17 | Phase 8 (2379fb21d) | Fixed |  |
| A18 | Phase 9 (96a376623) | Fixed |  |
| A19 | Phase 7 (feddeb717) | Fixed |  |
| A20 | Phase 8 (2379fb21d) | Fixed |  |
