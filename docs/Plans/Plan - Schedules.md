# Schedules: the class day, the adolescent room, and who is where, in both apps

> **Not started.** Written 2026-10-23 from Danny's talk-through (session on branch `claude/schedules-section-design-e82913`). Approved by Danny 2026-10-23; the build starts after the weekly reset on Sunday 25 October.
> In short: one Schedules page in the notebook and a read-only Schedule tab in the Daybook Assistant, showing our class's day, the adolescent room's day with whose turn each block is, Danny's planned lessons, and Morah Devora's schedule, with changes for one day.

Mockups: drawn inline in the talk-through session (a four-lane day view, and the Assistant tab both ways). There is no canvas. Phase 2A and 2B follow the descriptions below.

## Progress
- [ ] Phase 1: Data layer, schema 20 (`feature-phase-deep`)
- [ ] Phase 2A: Notebook Schedules page (`feature-phase`) ‖ 2B ‖ 2C
- [ ] Phase 2B: Daybook Assistant Schedule tab (`feature-phase`)
- [ ] Phase 2C: MCP tools (`feature-phase-light`)
- [ ] Phase 3: Merge, full checks, review (build session)
- [ ] Phase 4: Ship (fresh session; Danny's steps go in Tide)

## What Danny wants
- One place, in the notebook and on the assistants' phones, that shows four things side by side:
  our classroom's schedule, the adolescents' schedule, his lessons as planned in the daybook, and
  Morah Devora's schedule, which he types in.
- The adolescents (the adolescent-level children on his roster, 7 in October 2026) spend the day in
  another room, where the Upper Elementary teachers take turns giving lessons. He needs their timetable
  and to see when he or Morah Devora is booked in that room.
- Morah Devora is the kodesh teacher, his co-teacher (see the co-teacher app talk of 2026-10-14; that app
  isn't planned yet).
- School runs Monday to Friday. Fridays are shorter. The timetable mostly stays the same all year, but he
  needs a way to mark a change for one day.
- Assistants see which children are with him and when, **never the lesson names**.
- Lessons whose children are all adolescents are given during his turn in the adolescent room.

## Decisions (Danny, 2026-10-23)
1. **It replaces the old Schedules page.** The existing page (`Schedules/`: `CDSchedule`,
   `CDScheduleSlot`) holds recurring per-child slots for pull-outs. His live notebook had none on
   2026-10-23. The new page keeps the sidebar item's place and name. A second schedules page was ruled out.
2. **Four lanes: two rooms and two people.** Our class and the adolescent room are rooms. Danny and Morah
   Devora are people. The lane names are whatever Danny types (he has written both Devorah and Devora).
3. **Rooms have a weekly timetable.** Each block has a weekday, a start time, a length, a title and an
   optional note. Friday is simply its own day with its own blocks. The Week view shows the school
   calendar's school days (Monday to Friday unless the calendar adds a day).
4. **Adolescent-room blocks name who teaches.** The teacher is a person lane (Danny or Morah Devora) or a
   typed name for anyone else. A turn belonging to a person lane also shows in that person's lane
   ("In the adolescent room"). It is one record, shown in two places, so it's never typed twice.
5. **Morah Devora's lane is typed by Danny.** Blocks with a title, a time, a length and, optionally, the
   children she takes. Her turns in the adolescent room come from that room's timetable.
6. **Danny's lane is read from the notebook, not typed.** His planned lessons (scheduled, not yet given):
   - A lesson planned for the morning or afternoon shows in an ordered list for that half, in his order.
     A lesson with a set time shows at that time. Lessons have no length (see Deferred).
   - **All-adolescent lessons go inside his turn.** A lesson whose children are all adolescent-level
     children is placed in his turn in the adolescent room in the same half of the day (or the turn that
     contains its set time). With no turn in that half, it shows in his list with a note: "You have no turn
     in the adolescent room this morning." A lesson that mixes levels stays in his list.
7. **Changing a day.** Editing a block asks **Only This Day** or **This Day and After**, the way Calendar
   asks about a repeating event.
   - Only This Day records a change for that date: a new time, length, title or children, or Cancelled.
   - This Day and After ends the block the day before and starts a copy with the new values on that day,
     so earlier weeks still read as they were. That covers a new timetable partway through the year.
   - **Add to This Day** makes a one-off block on a date: an assembly, a trip, an early dismissal.
   - **Out Today** on a person lane cancels that person's blocks for the day and shows their turns in the
     adolescent room as "Out".
   - A changed day gets a marker in the Week view, the Day view's header ("1 change today") and on the
     Assistant.
   - A no-school day on the school calendar shows "No school" for the whole day, in every lane.
8. **Warnings are gentle and never block.** Shown in the Schedules Day view only, in this plan:
   - A child in one of Morah Devora's blocks is also in one of your lessons in the same half: "Lucy T is
     with Morah Devora 9:00–9:45 this morning."
   - An all-adolescent lesson with no turn in that half (decision 6).
   - A lesson with a set time that falls during your turn in the adolescent room, when it isn't an
     all-adolescent lesson.
9. **The Assistant gets a third tab, Schedule, that only reads.** It shows today, with previous and next day.
   - A **Now** card at the top says who is where right now ("Danny is in our room", "Morah Devora is in
     the adolescent room until 10:30").
   - Then the day's blocks for the rooms and Morah Devora, and Danny's lane as **children only**: each
     planned lesson becomes a "With Danny" row with its children and its time or half. A turn in the
     adolescent room shows its children. **No lesson names, ever.**
   - Morah Devora's block titles show as Danny types them. Her lane is a timetable, not a lesson plan, so he
     can keep titles generic if he wants.
10. **What goes in the classroom share.** The lanes, blocks and changes, so the Assistant can read them.
    Danny's planned lessons stay private: the guide's devices publish a trimmed **booking** for each one,
    carrying the day, the half or time, the order and the children. A booking has no lesson name and
    nothing that leads to one. Its key is the planned presentation's ID, which the Assistant can't look
    up, since presentations and lessons aren't in the share. Bookings cover today through 13 days ahead,
    and older ones are removed.
11. **Only Danny edits.** Assistants can't change the schedule. Later, Morah Devora's own app (the
    co-teacher plan) may take over her lane.
12. **Hebrew date and parsha in the header, in both apps.** "Monday, October 26 · 15 Cheshvan · Vayera".
13. **MCP.** `weekly_schedules` is rewritten to read the new timetables and any day's resolved schedule,
    with lesson names, since MCP is Danny's own. Two write tools let Claude enter a pasted timetable and
    one-day changes, so Danny can paste or photograph Morah Devora's schedule and have it typed in for him.
14. **Today's Schedule section switches to the new timetable.** It reads the old per-child slots now
    (Simplify plan, Phase 7). It becomes today's blocks from all four lanes, in time order, except Danny's
    lessons, which Today already lists. Changed blocks are marked. So Today shows "Your turn in the
    adolescent room 10:30–11:45" and "Early dismissal 2:00 (today only)".
15. **The old types stay in the model, unused.** CloudKit's schema only grows, and old backups still
    restore `Schedule` and `ScheduleSlot`. The page, Today's slot reader and the MCP tool stop using them.
    Their entity files, `ScheduleSlotWriter` (its `ScheduleTime` is used by `CDSchedule`) and their backup
    code stay. Making them dormant tombstones (`CoreDataStack+Model.swift:204`) is a later cleanup.

## The model: schema 20, backup v42
Use the next free numbers when Phase 1 starts. Today's are schema 19 (`CoreDataStack+SchemaVersion.swift:124`)
and backup v41 (`BackupWriter.swift:114`). The Simplify plan notes that a not-yet-started Hebrew
birthdays plan also wants schema 20 and v42. Whichever lands second takes 21 and v43.

The precedent for adding shared types is Restock, schema 15 (`a97b3439`), and ClassroomPerson, schema 16
(`f8cf505b`). Read both diffs and `Plan - Restock.md` › "Schema 15 / backup v37" first.

**Four new shared types.** Files in `Cosmic Daybook/Schedules/Model/`, hand-written `*Entity.swift` as the
model has no codegen. Every attribute optional or defaulted. Foreign keys are Strings. No relationships:
a relationship would take linked records along when the row is shared, and an already-shared record must
never be shared again. Children are a JSON string array through `CloudKitStringArrayStorage`, the way
`CDLessonAssignment._studentIDsData` stores them.

- **`TimetableLane`** (`CDTimetableLane`): `id`, `name` (""), `kindRaw` ("room" or "person"), `isGuide`
  (false; true for the one person lane that reads the guide's lessons), `sortOrder`, `colorRaw` (""),
  `createdAt`, `modifiedAt`.
- **`TimetableBlock`** (`CDTimetableBlock`):
  - `id`, `laneID`
  - `weekdayRaw` (a `Weekday` raw value; nil for a one-off), `onDay` (a one-off's day; nil otherwise)
  - `startMinute` (minutes after midnight), `lengthMinutes` (default 30)
  - `title` (""), `note` ("")
  - `teacherLaneID` (optional; a person lane), `teacherName` (""; anyone else)
  - `_studentIDsData` (optional; the children, for Morah Devora's groups)
  - `validFrom`, `validUntil` (optional days; nil means open-ended). This Day and After sets the old
    block's `validUntil` to the day before and makes a copy with `validFrom` set to that day.
  - `createdAt`, `modifiedAt`
- **`TimetableChange`** (`CDTimetableChange`): one day's change.
  - `id`, `day`, `kindRaw` ("cancelled", "changed" or "out")
  - `blockID` (for cancelled or changed), `laneID` (for out)
  - For "changed", the replacement values in full, copied from the block and then edited: `startMinute`,
    `lengthMinutes`, `title`, `note`, `teacherLaneID`, `teacherName`, `_studentIDsData`
  - `createdAt`, `modifiedAt`
- **`TimetableBooking`** (`CDTimetableBooking`): one planned lesson, trimmed.
  - `id`, `presentationID`, `day`, `halfRaw` ("morning" or "afternoon"), `minute` (-1 when only a half
    was planned), `order` (its place in that half)
  - `_studentIDsData`, `sourceModifiedAt` (the presentation's `modifiedAt` when written)
  - `createdAt`, `modifiedAt`
  - **No text attribute at all.** A test lists the entity's attributes against an allowlist, so a
    lesson's name can never be added by accident.

**Lists to extend** (the Restock and ClassroomPerson commits show each one):
- `CoreDataStack.sharedEntityNames` (`CoreDataStack+Model.swift:81-108`), the schema history and
  `currentSchemaVersion`, and the digest in `CoreDataSchemaVersionTests.swift:36`.
- `ClassroomSharingService+Setup.swift`: the order list (`:297-306`) and `recordNames` (`:339-351`).
- `PersistentHistoryProcessor.presentationEntityNames` (`:73-78`), so screens refresh on remote changes.
- **Not** `ClassroomPermissions.assistantWritableEntities`: assistants only read.
- `ClassroomShareScope` needs nothing. Every shared type but Student and AttendanceRecord is always
  shared (`ClassroomShareScope.swift:59`). Bookings stay small because the publisher prunes them.
- Tests with hard-coded entity lists: `Phase8PreTests`, `Phase5PostTests`, `StoreMigrationTests`,
  `ClassroomShareShrinkMigrationTests`, `RestockShareMigrationTests`, `ClassroomPersonMigrationTests`
  (old-model fixtures filter later types out by name), `PersistentHistoryEntityNotificationTests`,
  `Daybook Assistant Tests/AssistantSplitStoreTests`.
- Shared/private counts and the schema line in `Cosmic Daybook/CLAUDE.md` (Phase 3 does this).

**Where inserts land.** Only the guide's devices write these types. Insert into the private store
(`RestockService.destinationStore(for:near:in:)`, then `context.assign(_:to:)`) and save on the
**view context**, so `SharedStoreOrphanGuard` shares the new rows. It watches view-context saves only.

**Backup v42.** All four types are model-driven `ModelRow`s. Each needs:
- its lines in `ModelRowKinds.swift`, `BackupTypes.swift` (coding key and payload field), `BackupEntityTable.swift`
- an `importVxxEntities` step in `BackupRestoreRun+LaterTypes.swift`, called from `BackupService+Restoration.swift`
- its plain name in `BackupPlainNames.swift` and `BackupPreviewAnalyzer.swift`

Bookings are backed up too. They're derived, but restoring them is harmless, since the publisher prunes
and rewrites them. Bump `BackupWriter.formatVersion` and the reader's range. Re-record the goldens
(`TEST_RUNNER_RECORD_BACKUP_GOLDEN=1`, `TEST_RUNNER_RECORD_BACKUP_SPARSE=1`; `docs/Technical
notes/BACKUP_SYSTEM.md:251`), update `BackupFieldCoverageTests`, `Phase7PostTests`' registry count,
`BackupSparseRowTests` and `BackupRestoreFixtures`, and add a round-trip test.

## The day, worked out once: `ScheduleDayResolver`
Plain Swift with no Core Data. It takes value snapshots in and gives a resolved day out, so the notebook,
the Assistant and MCP show the same day, and the rules are testable. It must build for iOS 18.

Inputs: the lanes, the blocks, the day's changes, the day's lessons (with titles in the notebook and MCP,
from bookings without titles on the Assistant), each child's level, and whether school is in session.

Rules, in order:
1. No school (the school calendar, via `SchoolDayChecker`): the whole day reads "No school", and nothing
   else is shown.
2. A block applies on day D when it is a one-off with `onDay == D`, or its weekday is D's and
   `validFrom ≤ D ≤ validUntil` (each end open when nil).
3. Changes for D: cancelled hides a block; changed replaces its values for D; out cancels every block in
   that lane on D and marks that person's turns elsewhere "Out". Any change, or any one-off block, marks
   the day changed.
4. Turns: an adolescent-room block whose `teacherLaneID` is a person lane also appears in that lane as
   "In the adolescent room · <title>". It is the same block, not a copy, so a change to it shows in both.
5. The guide's lessons go in the `isGuide` lane. A morning or afternoon lesson joins that half's ordered
   list, and a set-time lesson sits at its time (`DayHalfPlanner.moment(of:)`).
   - A lesson whose children are all adolescent-level (`CDStudent.Level.adolescent`) goes into the
     guide's turn in the same half, or the turn containing its set time. With no such turn, it stays in
     the list with the note "No turn in the adolescent room this morning" (or "this afternoon").
   - A mixed-level lesson stays in the list.
6. Warnings (decision 8):
   - A child in a block of a person lane other than the guide's, also in a guide lesson in the same half.
     Morning is before noon.
   - An all-adolescent lesson with no turn (rule 5).
   - A set-time lesson, not all-adolescent, that falls inside a guide turn.

Output: the lanes in `sortOrder`, each with items in time order. An item is a block, a turn, a lesson or
an ordered half-list. Plus the day-changed flag, the warnings, and a "now" helper: what each lane has at a
given minute.

## The booking publisher: `ScheduleBookingPublisher`
Notebook only (not compiled into the Assistant). It keeps the share's bookings in step with the guide's
planned lessons. Every guide device runs it, so the Assistant stays current whichever device Danny plans
on. Mac-only was ruled out: the Assistant would go stale whenever the Mac is closed.

- **When it runs.** Copy `TideSyncService.observeTodos` (`Services/Tide/TideSyncService.swift:128-157`):
  - the view context's ObjectsDidChange for `LessonAssignment`
  - `.presentationDataDidChange` for remote changes
  - a short wait before running
  - an `isWriting` flag so it ignores its own saves, and one more run if a change arrives mid-run
  - it also runs at launch **after this launch's iCloud catch-up** (`ImportWatermark`, as
    `CalendarNotePadCopy` waits), at day change, and on return to the foreground
- **What it writes.** One booking per planned presentation in the window (today through today + 13;
  `scheduledFor` set, not presented): day, half or minute, order within the half, children,
  `sourceModifiedAt`. Fetch with `TodayDataFetcher.fetchLessons` / `TodayLessonsLoader` and filter
  `!isPresented`, as `schedule_for_range` does.
- **Never backwards.** Update a booking only when the presentation's `modifiedAt` is newer than its
  `sourceModifiedAt`, so a device that hasn't caught up can't undo a newer plan.
- **Removing.** Remove a booking when:
  - its day is before today
  - this device knows the presentation and it was given, unscheduled or moved out of the window
  - the presentation is unknown here and the booking is over an hour old (a new one may still be on its
    way from another device)
- **Doubles.** Two devices may both make a booking for one presentation. Copy `ClassroomNames`' upsert
  and fold (`ClassroomNames.swift:384-412`, `ClassroomNames+Zones.swift:110-137`):
  - keep the row made first (`createdAt` to the millisecond, then `id`; `ScheduleSlotWriter.madeFirst`)
  - carry over the newest values
  - never delete another copy with the same `id`, and check a row's zone before deleting it
  - readers on both apps also group by `presentationID` and take the newest
- Saves on the view context (see "Where inserts land").

## Phases

### Phase 1: Data layer
- **Who:** `feature-phase-deep` (Opus · xhigh): schema, sharing, backup and a mirroring service.
- **Worktree:** this plan's branch, or a fresh one from main with this plan merged.
- **Files:** the model; `Cosmic Daybook/Schedules/Model/`, `Schedules/Services/` (`TimetableService`,
  `ScheduleDayResolver`, `ScheduleBookingPublisher`); the lists in "The model"; backup; a
  `HebrewDateText` helper beside `Parsha/`; tests under `Cosmic Daybook Tests/Schedules/`.
- **Steps:**
  1. The four types, schema bump and every list in "The model", with the share and migration tests passing.
  2. **`TimetableService`, the only writer** (like `RestockService`):
     - make the starter lanes (Our class, Adolescent room, and the guide's lane named from
       `ClassroomNames.myName(role: .leadGuide, in:)`), and add a person
     - add a block on one or more weekdays
     - edit or delete a block for Only This Day, This Day and After, or every week (every week edits the
       block itself; delete ends it rather than erasing weeks already past)
     - add a one-off, cancel on a day, Out Today and back in, undo a day's change
     - copy one weekday's blocks to other weekdays
     - rename and reorder lanes
  3. `ScheduleDayResolver` with the rules above.
  4. `ScheduleBookingPublisher`, started from `AppBootstrapper` on the guide's devices, never in the
     Sample Class.
  5. `HebrewDateText`: "15 Cheshvan" from `HebrewParshaService.hebrew` with English month names,
     including Adar I and II, plus a header line "Monday, October 26 · 15 Cheshvan · Vayera" from
     `TodayHeaderText.subtitle(for:)` and `HebrewParshaService.currentParshaKey(on:)` /
     `displayName(forKey:)`. Pin a few dates checked against a published Hebrew calendar. It must build
     for iOS 18, since the Assistant shows it too.
  6. Backup v42.
- **Done when:**
  - The iOS build is clean, and a macOS compile-only build is clean.
  - The schema, migration, share-list and backup suites pass with counts, including the re-recorded goldens.
  - New tests pass:
    - resolver: each rule, Friday as its own day, both edit modes across weeks, Out Today, no-school,
      adolescent placement and its note, the three warnings
    - publisher: the window, never backwards, removal cases, folding doubles
    - the booking attribute allowlist
    - `TimetableService` edit modes
    - `HebrewDateText`
  - Swift Testing; watch for vacuous `#expect`.
- **Hand off:** no. Phase 2 starts from its commit.

### Phase 2A: Notebook Schedules page
- **Who:** `feature-phase` (Opus · high).
- **Files:** `Cosmic Daybook/Schedules/` (views), `Today/` (the Schedule section), `RootView` (label
  and icon only).
- **The page** replaces `SchedulesView` at `RootDetailContent.swift:102`. The `.schedules` case,
  its sidebar place and the iPhone More tab stay. Delete `SchedulesView`, `ScheduleEditorSheet` and
  `ScheduleDetailSheet` (decision 15).
- **Header:** the `HebrewDateText` line; previous day, Today and next day; Day and Week; a "1 change
  today" chip when the day is changed.
- **Day view on Mac and iPad:** the four lanes side by side, with the time down the left and a now line
  on today, as in the mockup.
  - A turn shows outlined in the room's color inside the person's lane.
  - The guide's ordered half-lists show as one band with numbered lessons.
  - Changed blocks get a dashed outline.
  - Warnings show as a line under the header, and a tap scrolls to the item.
- **Day view on iPhone:** one list in time order, each row tagged with its lane's color and name, with a
  lane filter menu.
- **Week view:** one lane at a time, with a lane picker.
  - Mac and iPad: school days as columns.
  - iPhone: a list by day.
  - Changed days marked.
- **Editing.**
  - Block sheet: lane, days (several for a new block), start, length in 5-minute steps, title, note.
    For the adolescent room, a teacher picker: person lanes plus "Someone Else…" with a name. For person
    lanes, optional children through the usual student picker.
  - Editing a block that repeats asks Only This Day or This Day and After, as a confirmation dialog.
  - Day menu: Add to This Day…, and Out Today on a person lane's header.
  - Week view: Copy Day To….
  - First run: an empty state, "Set up your schedules", makes the starter lanes. Then Add a Person… for
    Morah Devora.
- **Today:** the Schedule section reads the resolver for today (decision 14). Replace
  `TodayScheduleSlots` and the "Schedule"/"ScheduleSlot" names in `TodayViewModel+Refresh.swift:30-35`
  with the new types. Keep the section's visibility key and place.
- **Done when:**
  - The iOS build is clean, and a macOS compile-only build is clean.
  - The Schedules and Today suites pass.
  - Rendered screenshots, made with the Sample Class seeded with lanes, of: the iPad Day view, the
    iPhone Day list, the Week view, the block sheet and the Only This Day dialog.
  - Plain-English copy everywhere.
- **Hand off:** no.

### Phase 2B: Daybook Assistant Schedule tab
- **Who:** `feature-phase` (Opus · high): new tab, hand-edited `project.pbxproj`.
- **Files:** `Daybook Assistant/Schedule/`, `Daybook Assistant Tests/`, `project.pbxproj`. Compile-only
  fixes (iOS 18 fallbacks) in Phase 1's files are allowed, with no behavior change; list each one.
- **Tab.** `AssistantTabs.Choice` gains `.schedule`, a third `Tab("Schedule", …)` after Restock (an SF
  Symbol available on iOS 18).
- **Model.** `AssistantScheduleModel`, `@Observable`, shaped like `AssistantRestockModel`:
  - a `RemoteImportReloader` built in `init`
  - `load()` reading only the shared store
  - `followRemoteImports` and a scene-phase modifier like `RestockFollowsScene`, without the save parts
  - it reads the lanes, blocks, the day's changes, the day's bookings (grouped by `presentationID`,
    newest taken), children's short names and levels, and the school day
    (`AssistantAttendanceViewModel.dayOff(on:in:)`), then runs `ScheduleDayResolver`
- **View**, as in the "Children only" mockup, and it must fit an iPhone SE (375 pt):
  - the header line, with previous and next day and Today
  - a Now card on today: who is where ("Danny is in our room", "Morah Devora is in the adolescent room
    until 10:30"). The guide's name comes from `AssistantBootstrapper.guideNameToShow`, falling back to
    "Your guide".
  - the day as one list in time order, rows tagged by lane
  - the guide's lessons as "With Danny" rows: children's short names, and the time or half
  - turns showing their children
  - a lane filter menu, and a "Changed today" line
  - no lesson text anywhere
- **Plumbing.** Add to the Assistant's Sources in `project.pbxproj`, by hand:
  - Phase 1's four entity files, `ScheduleDayResolver` and `HebrewDateText`
  - the Parsha files they need
  - `Models/Schedule.swift` (`Weekday`)
  - `CloudKitStringArrayStorage`, if it isn't there already
  - anything those pull in
  Everything must build for iOS 18. Seed lanes, blocks and two bookings in `AssistantSampleClass.fill`.
- **Done when:**
  - The `Daybook Assistant` and `Cosmic Daybook` schemes both build clean.
  - The full Assistant test target passes on a leased iPhone simulator, including new tests: the load
    and reload, the Now card, adolescent placement from bookings, and that no lesson title can reach the
    view model.
  - Screenshots with `-AssistantSampleClass` on the iPhone SE (iOS 26.5).
- **Hand off:** no.

### Phase 2C: MCP tools
- **Who:** `feature-phase-light` (Sonnet · medium).
- **Files:** `Services/MCPServer/MCPNotebookTools+Planning.swift` (or a new `+Timetable.swift`),
  `MCPNotebookTools.swift`, `MCPToolRegistryTests.swift`, `docs/Technical notes/MCP_SERVER.md`.
- **`weekly_schedules`, rewritten:**
  - the lanes and their weekly blocks (optionally one lane or one weekday)
  - with `date:`, that day resolved: changes, turns, the guide's lessons by name, warnings
  - read-only, as now
- **`set_timetable`** (write): a lane, a "from" day (default today), and blocks (weekdays, start, length
  or end, title, teacher, children by name). It replaces the lane's weekly blocks from that day, This Day
  and After style, through `TimetableService`. It follows the existing write tools' patterns: annotations,
  the confirm step, the write journal.
- **`change_schedule_day`** (write): a day, and one of: cancel a block, change it, add a one-off, Out Today
  for a person, undo the day's change.
- The registry count goes 92 → 94, and the write tools go in the test's literal sets.
- **Done when:** the iOS build is clean; the MCP suites pass, including a round trip of each tool against
  an in-memory store.

### Phase 3: Merge, full checks, review
- **Who:** the build session (Opus · medium).
- **Steps:**
  1. Merge 2C, then 2B, then 2A onto Phase 1's branch. A clash goes to the side whose file boundary it is.
  2. Full notebook iOS suite, full Assistant suite, a macOS compile-only build, and a macOS Release
     compile-only build.
  3. Update `Cosmic Daybook/CLAUDE.md`: the shared/private counts, the schema and backup numbers, the
     Assistant's three tabs, and the Schedules folder note.
  4. `/code-review high` on the branch against its base; fix what holds up, and re-run the touched suites.
  5. Remove the phase worktrees, release their simulators (`sim-lease --release <path>`) and trash their
     DerivedData.
- **Done when:** step 2 is green with counts, the review's kept findings are fixed, and Danny has the
  screenshots.
- **Hand off:** yes, to Phase 4.

### Phase 4: Ship (fresh session; Danny's steps go in Tide)
- **Who:** a fresh session (Opus · medium) with the `roll-out` skill.
1. Danny backs up the live notebook.
2. CloudKit: Claude runs the Development schema init (a Debug build with `CLOUDKIT_ENVIRONMENT=Development`
   and `-InitializeCloudKitSchema` on a leased simulator, never the Mac). Danny checks CD_TimetableLane,
   CD_TimetableBlock, CD_TimetableChange and CD_TimetableBooking in the Console and clicks **Deploy to
   Production**. **Nothing built from this branch runs on a Production device before that deploy.**
3. Merge to main (with Danny's OK). Roll out the notebook (Mac, iPad, iPhone) and an Assistant TestFlight
   together.
4. Danny sets up on the Mac: Schedules › Set Up. He enters our class and the adolescent room, with Friday,
   then adds Morah Devora. Or he pastes or photographs the timetables to Claude, which enters them with
   `set_timetable`.
5. Device checks:
   - the Assistant shows children only
   - a turn shows in both the room and the person's lane
   - an Only This Day change shows its marker on the Assistant
   - an all-adolescent lesson lands in Danny's turn
   - Today's Schedule section shows the turn
- **Done when:** the schema is deployed, both builds are installed or on TestFlight, and step 5 passes.

## Running it

### Who runs each phase
Launch the user-level agents with `subagent_type`, and don't pass `model`. A phase agent that stalls or
reports a design question comes back to the build session.

| Phase | Runs as | Model · effort | Parallel with |
|---|---|---|---|
| 1, data layer | `feature-phase-deep` | Opus · xhigh | — |
| 2A, notebook page | `feature-phase` | Opus · high | 2B, 2C |
| 2B, Assistant tab | `feature-phase` | Opus · high | 2A, 2C |
| 2C, MCP | `feature-phase-light` | Sonnet · medium | 2A, 2B |
| 3, merge + review | the build session | Opus · medium | — |
| 4, ship | fresh session | Opus · medium | — |

### The build session's steps
1. Phase 1 in one worktree made from the commit with this plan:
   `git worktree add .claude/worktrees/schedules-1 -b claude/schedules-1 <commit>`. Don't use the Agent
   tool's `isolation: worktree`: it starts at the last-pushed main.
2. Phases 2A, 2B and 2C in three worktrees made from Phase 1's commit, launched in one message, each told
   its worktree path, its section of this plan and its file boundary.
3. Phase 3 here, when all three report. Then print Phase 4's starter prompt.

### Every agent brief includes
- read this plan (its own phase, "The model", "The day, worked out once" and "The booking publisher"),
  `Cosmic Daybook/CLAUDE.md` and, for 2A–2C, Phase 1's commit
- in a new worktree, build once before editing, with the three prefix-mapping settings
- build only through `Scripts/locked_xcodebuild.sh`; only the phase's own scheme and `-only-testing:`
  suites (the full suites are Phase 3's)
- test on the iOS Simulator with `-destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)"`,
  `-parallel-testing-enabled NO`; never the macOS test destination or a Debug Mac launch (both open
  Danny's live store); `~/.claude/bin/sim-lease --done` before replying
- Swift Testing; watch for vacuous `#expect` on optional chains
- main-actor-default: Core Data types and their extensions are `nonisolated`
- American spelling and plain-English UI copy
- nobody edits `Cosmic Daybook/CLAUDE.md` or this plan; only Phase 1 edits `TimetableService`,
  the resolver and the publisher (2B's compile-only exception aside)
- one commit with the `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` trailer
- reply in at most 15 lines: commit, files changed, build and test results with counts, anything decided
  differently from the plan or left unresolved

## Ending a phase
1. Check every "Done when" item for the phase.
2. Tick the phase under Progress and note anything that differed from the plan.
3. Update the build board (https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM) with the `build-board` skill.
4. Danny's steps and device checks become rows in Tide's `Areas/App Development/Cosmic Daybook/To do.md`,
   with a short line and the row's link here.
5. After Phase 3, print Phase 4's starter prompt: "Model: Opus 5.5, effort: medium" on the first line,
   then "In Maria's Notebook, read docs/Plans/Plan - Schedules.md and do Phase 4. Follow its Ending a
   phase steps when done."

## Cost
A rough guess, about 15–23% of the weekly all-models limit (Max plan):
- Phase 1 ~5–7%
- 2A ~3–5%
- 2B ~2–4%
- 2C ~1%
- Phase 3 with its review and fixes ~3–5%
- Phase 4 ~1%

At planning time (2026-10-23) 78% was used, with the reset on Sunday 25 October at about 4 pm. **Start
after the reset.** Phase 1 alone could fit before it, but Phases 2–3 can't.

## Deferred
- Real lesson times with a length (start + length, snapping to 15 minutes). The co-teacher plan needs
  them too. They would make clash warnings exact ("9:00–9:45") instead of "this morning".
- Warnings in the Lessons & Work planner itself, not only on the Schedules page.
- Morah Devora editing her own lane from her own app (the co-teacher plan).
- Notifications ("Your turn in the adolescent room in 5 minutes").
- A Schedules widget, or a now-and-next line in the Assistant's Attendance tab.
- Retiring `Schedule`/`ScheduleSlot` as dormant tombstones (decision 15).

## Open questions
None blocking. Phase 2A keeps the sidebar item in its current group (Classroom). Moving it is a one-line
change if Danny wants it somewhere more prominent.
