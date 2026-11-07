# Assistant Today tab (2026-10-14)

> **Not started.** Written 2026-10-14 from Danny's answers and the approved mockup (session on branch `claude/assistants-today-view-efe5fa`).
> In short: a Today tab in Daybook Assistant with the school day, today's events, early pickups, class notes and to-dos anyone can add and check off (with an optional nudge), "watch for" lines the guide shares, a tomorrow peek and dots on Attendance tiles, plus a Class notes section in the notebook's Today; schema 19, backup v41.

**Numbers out of date (noted 2026-11-06, when this plan moved onto main):** the schema and backup numbers below were current on 2026-10-14. Main is now at schema 24 and backup format 46, so this work would be schema 25 and format 47, and the pinned-test list, line numbers and "the schema-N pattern" references need checking against main before Phase 1 starts.

Mockup (approved 2026-10-14): https://claude.ai/artifact/13wRHtr5MdKyg6DPF7Qj1L. It has four screens: Today (whole scroll, clickable), New Note, the 11:30 nudge, and Attendance tiles with dots.
Build board: https://claude.ai/artifact/WAKaFZGNPQsfKD4A5GbqsM (add a milestone for this plan when the build starts).

## Goal

An assistant opens the app after arrival and sees, on one screen, everything about the day that isn't the roll:
- Whether it's a school day.
- Today's events.
- Who leaves early.
- Notes and to-dos from anyone in the class ("Lucy is leaving at 2", "Make sure Ora takes her meds").
- The few social things Danny wants them to watch for.
- What's coming tomorrow.

Danny sees and adds the same notes from the notebook's Today.

## What Danny decided (2026-10-14)

- **Placement.** Today is the second tab: Attendance, Today, Restock.
  - The app opens to Attendance in the morning until attendance is closed, and after that it opens to Today.
- **Social issues.** Only the ones Danny chooses to share go to the assistants. Each appears as a short "watch for" line he writes. His Issue notes and history never go to the assistants' phones.
- **Class calendar.** Today's events from the notebook, meaning the Apple Calendar events the notebook already syncs.
- **Notes.** Anyone in the class can leave one, guide or assistant.
  - A note is either plain text or a to-do.
  - Anyone can check off a to-do, and it then shows who did it and when.
  - A to-do can have a time. If it isn't checked off by then, every assistant's phone gets a nudge.
- **Early pickups.** These show on Today by themselves, read from Leaving Early. Nobody has to type them as notes.
- **Children.** A note or a watch-for line can name children.
  - Each named child gets a dot on their Attendance tile.
  - Today has a filter by child.
- **Range.** Today in full, plus a short Tomorrow peek.
- **Leftovers.** A to-do that isn't checked off carries over to the next day, marked "From yesterday" (or the day it was written). Plain notes end with their day.
- **Danny's side.** A Class notes section in the notebook's Today, on Mac, iPad and iPhone, where he adds notes and sees check-offs.
- **Editing.** Assistants edit or delete the notes they wrote. Danny can edit or delete any note. Anyone can check off a to-do.

## Decisions (how it's built)

### Data: three new shared types (schema 19)

A shared record carries every field, so nothing private goes into the share. Calendar events and Issues stay private. The share gets small copies made for the assistants.

**`CDClassNote`**: a note or a to-do. The guide and assistants both write it.
- `id` UUID.
- `day` Date (start of the school day it was written for).
- `text` String.
- `isTodo` Bool.
- `nudgeAt` Date?: a full date-time on `day`. Only to-dos have one.
- `_studentIDsData` Data?: the same encoding as `CDIssue.studentIDs`.
- `addedAt`, `addedByID`, `addedByName`: the stamp pattern from `OrderItem.addedByID` / `addedByName` and `RestockService.stampAdded`.
- `doneAt` Date?, `doneByID` String?, `doneByName` String?: copies the pattern of `Supply.levelChangedAt` / `ByID` / `ByName`.
- `modifiedAt` and `changedByID`: the schema-17 pattern.

Carry-over is derived. No device ever moves a note's `day`:
- A to-do shows on day D when `day <= D` and `doneAt == nil`, or when it was done on D.
- "From yesterday" / "From Tuesday" is shown when `day < D`.

This follows the rule that year-plan completion is derived. Writing `day` forward from several devices would collide.

**`CDWatchItem`**: a watch-for line. Only the guide writes it.
- `id`, `text`, `_studentIDsData`.
- `untilDay` Date?: shown through that day; none means until Danny removes it.
- `issueID` String?: the private `CDIssue` it came from. This is an id string only, not a relationship, because Issue is private.
- `addedAt`, `addedByID`, `modifiedAt`, `changedByID`.

**Privacy rule:** the guide's devices delete a watch item from the share once it has expired or its Issue is resolved or closed. The Issue keeps the history; the share keeps only what is live.

**`CDSharedEvent`**: a copy of one calendar event for today or the next school day. Only the guide's devices write it.
- `id`.
- `eventKey` String: `eventKitEventID` plus the start date. This is the upsert and dedup key.
- `title`, `startDate`, `endDate`, `isAllDay`.
- `location` String?.
- `notes` is left out on purpose; event notes are often private.
- `modifiedAt`.

### Where the code goes

Every list a new shared type must join (the recipe from schema 16, `docs/Plans/Plan - Names you set yourself.md` Phase 1):
1. `CoreDataStack+Model.swift:81` `sharedEntityNames`. This puts the type in the `Shared` configuration. `ClassroomShareScope.alwaysSharedEntityNames` and `DedupShareBoundary` follow from it.
2. `ClassroomSharingService+Setup.swift:299` `orderedEntityNames`, and the wording at :339–351.
3. `ClassroomPermissions.swift:34` `assistantWritableEntities`: add `CDClassNote` **only**. Watch items and shared events stay guide-only.
4. `PersistentHistoryProcessor.swift:73` entity names, so screens refresh on imports.
5. The Assistant target's Sources in `project.pbxproj`, for each new shared model or service file.
6. Backup:
   - `BackupEntityTable`, `ModelRowKinds`, `BackupTypes`, `BackupPlainNames`, `BackupPreviewAnalyzer`, `BackupRestoreRun+LaterTypes`.
   - `BackupWriter.formatVersion` goes from 40 to 41; the reader accepts `17...41`.
   - **`CDSharedEvent` is not backed up.** It is rebuilt from the calendar. Say so in the table, the way skipped types are marked today.
7. `CoreDataStack+SchemaVersion.swift:121` `currentSchemaVersion` goes from 18 to 19, with a changelog line.
8. The pinned tests: `Phase8PreTests`, `Phase5PostTests`, `StoreMigrationTests`, `ClassroomShareShrinkMigrationTests`, `RestockShareMigrationTests`, `PersistentHistoryEntityNotificationTests`, `BackupSparseRowTests`, `BackupFieldCoverageTests`, `BackupRestoreFixtures`, `AssistantSplitStoreTests`, `CoreDataSchemaVersionTests.expectedModelDigest`. Also a new golden backup JSON.
9. The entity counts in `Cosmic Daybook/CLAUDE.md` (89 → 92 entities, 11 → 14 shared). Also `docs/Technical notes/BACKUP_SYSTEM.md`, `CLOUDKIT_GUIDE.md` and `DATA_MODELS.md`.

**Who did it.** Notes reuse the `RestockAuthor` wording:
- `current(role:)` and `stampedName` produce the stamp.
- `reads(changedByID:name:)` turns a stamp into "You", the assistant's current name, or "your guide".
- Danny's own notes read "Danny" by using the guide name that `ClassroomNames` already carries.
- Move `RestockAuthor` into a neutral name (`ClassroomAuthor`) only if the code reads badly otherwise. A typealias keeps Restock's call sites.

**Edit rule** (app convention; CloudKit only knows read-write):
- An assistant can edit or delete a note whose `addedByID` is her own.
- The guide can edit or delete any note.
- Anyone can check off a to-do or undo a check-off.

There is no per-category permission; those toggles were removed on 2026-09-30.

**Retention.** `ClassroomShareRelease` only plans Student and Attendance today. Add the three types:
- `CDClassNote` older than the school year leaves the share at the year's release. The notebook keeps its copy.
- `CDSharedEvent` copies before today are deleted daily by the publisher.
- `CDWatchItem` follows the privacy rule above.

### The calendar copies

`SharedEventPublisher` runs on the guide's devices after `CalendarSyncService` finishes a sync, at launch, and at the first foreground of a new day. Each run:
- Upserts today's and the next school day's `CDCalendarEvent`s into `CDSharedEvent` by `eventKey`.
- Deletes copies whose event is gone or whose day is past.

Each device syncs its own choice of calendars (`syncCalendarIdentifiers`, kept per device), so two devices could publish different sets.
- **Decision:** a "Share today's events with assistants" switch in Calendar settings, per device. It is on by default only on the Mac.
- Upserting by `eventKey` makes a second device harmless.
- A dedup pass keeps the newest copy per key. This uses the same idea as `DedupShareBoundary`; CloudKit can still produce two records for one key when two devices publish at once.

### Watch-for lines

The notebook has **no Issue editor screen**. Issues are made and edited over MCP (`update_issue`, `list_issues`). So:
- **In the notebook**, the Class notes section has "Add Watch For…". Its sheet takes a line, the children involved, an until-day, and an optional link to an open Issue (a picker of open Issues; Social first).
- **Over MCP**, `update_issue` gains `watch_for` (text, or empty to stop sharing) and `watch_until`. These create, update or delete the linked `CDWatchItem`.
- A new read tool, `class_notes` (a date range), gives Claude the notes, check-offs and watch items. A write tool, `add_class_note`, lets Claude file "Make sure Ora takes her meds at 11:30" from Danny's words. These follow the existing MCP write rules: annotations, the write journal and confirm wording.
- Ruled out: building a full Issue editor for this. That's its own plan if Danny wants one.

### Assistant app

**Tab.** Add `.today` to `AssistantTabs.Choice`, between Attendance and Restock. The new folder is `Daybook Assistant/Today/`:
- `AssistantTodayView`: the sections as in the mockup.
- `AssistantTodayModel`: an `@Observable` that loads one day and follows remote imports, like `AssistantRestockModel`.
- `AssistantNoteSheet`: new and edit.
- `AssistantTodayFilter`: the child chips.

**Which tab it opens to.** Add a pure helper, `AssistantOpeningTab.choice(now:…)`. It returns `.today` when any of these is true, otherwise `.attendance`:
- It's a day off.
- `CDAttendanceStore.arrivalClosed(on:)` reads true.
- `AttendanceLatePhase.isLate` is true.
- `ArrivalReminder.isRollComplete` is true.
- `AttendanceEmailLog.latestSend(on:)` returns a send.

Apply it at launch and when the app comes back from the background after five minutes or more, so the tab never switches while she's using the app. Copy the scene-phase handling in `RestockFollowsScene`.

Then rename `assistantShowToday` to `assistantShowAttendanceToday`, because it means "show today in the Attendance grid". Notification taps go to:
- An arrival tap: Attendance.
- A pickup tap or a nudge tap: Today.

**Sections, top to bottom** (as the mockup):
1. **The day card.**
   - "A full school day", or the day off and its `reason`, from `SchoolCalendarService`.
   - The line "Attendance closed at 9:02 · 20 of 22 here", taken from the counts the Attendance view model already has.
2. **The child chips:**
   - "Everyone" first.
   - Then every child named today in a note, a watch item or a pickup.
   - Choosing a child filters every section.
3. **Schedule.** Shared events and early pickups in one list sorted by time.
   - Pickups come from `EarlyPickupReminder.pendingPickups(in:now:)`.
   - Past items fade.
4. **Notes.**
   - To-dos first: open ones, then carried-over ones marked "From yesterday", then done ones, each showing "Done by Ana at 11:32".
   - Plain notes after the to-dos.
   - A swipe gives Edit and Delete when the edit rule allows.
5. **Watch for.** Live watch items, with "Danny · until Friday".
6. **Tomorrow.** Next school day's name, plus:
   - Its day-off status.
   - Its shared events.
   - To-dos written for it.

   If tomorrow isn't a school day, the peek names the next school day.

**New Note sheet.** As the mockup:
- Text.
- A "Something to do" switch.
- "Nudge if not done by" (a time; to-dos only).
- About (children).
- The day it's for: today by default; tomorrow can be picked.

**Saving.** Saves go through `AssistantSave`, which already files inserted share types into the classroom share by `sharedEntityNames`. Errors show in plain English ("Couldn't save the note. Try again."), using the `AppErrorMessages` tools.

**Nudges.** Each assistant's phone schedules a local notification at `nudgeAt` for each of today's open to-dos.
- **Identifier:** `classnote-<id>`.
- **Rebuilt** with the other reminders in `EarlyPickupReminderUpkeep.refresh` (:99–100). That runs after every remote change, so a check-off arriving by import withdraws the nudge on every phone.
- **Text:** title "Ora B's meds", body "Nobody has checked this off yet. Danny asked for 11:30."
- **Actions:** register a `UNNotificationCategory` with two actions in `AssistantApp`:
  - **Done** checks the to-do off in the background, through `AssistantSave`.
  - **In 10 minutes** reschedules on this phone only.

  `ArrivalReminderTaps.didReceive` handles them. This is the app's first notification category.
- **The guide's devices don't get nudges.**
- **Known limit:** silent CloudKit pushes aren't guaranteed. A phone that hasn't imported the check-off can still ring. This is the same caveat as `FrontDeskEmailReminder.swift:24`. Say it in the note sheet's footnote only if it turns out to happen in practice.

**Tile dots.**
- `AttendanceRow` gains `todayMarks` (`hasNote`, `hasWatch`), defaulted to none so the notebook's grid is unchanged.
- The Assistant's view model fills it.
- `AttendanceTile` draws a round accent dot for a note and a square orange dot for a watch item, top right. Their shapes differ, so color isn't the only cue. Put them beside the existing `cornerGlyph`, and check they don't collide with the pickup glyph.
- The long-press preview lists that child's note and watch lines under the existing note preview.

### Notebook

**Class notes section.**
- A new `TodaySectionVisibility` case, `.classNotes`, between `.dayCards` and `.todos`. On the Mac that puts it in the right column above Todos.
- The section has today's notes and to-dos with check-off and who-did-it, Add Note, the live watch items with Add Watch For…, and a one-line "Sharing today's events: 2" status.
- It is hidden when the classroom isn't shared.
- The pinned order tests change with it.

**Calendar setting.** "Share today's events with assistants" goes in Calendar settings, using `SettingsCopy` wording.

**MCP.** As above: `class_notes` read, `add_class_note` write, and the `update_issue` watch fields. Update the tool count in the MCP docs.

## Phases

The models below are from the agent list. Every phase uses the build queue and runs only its own `-only-testing:` suites. Phase 6 is the one full build and the one whole-suite run.

- **Phase 1: Schema 19 and the shared services** (`feature-phase-deep`, Opus). Branch from main.
  - Covers:
    - The three entities and every list above.
    - Backup v41 with a golden file.
    - `ClassNoteService`: add, edit, delete with the edit rule, check off, undo, `notes(for day:)` with derived carry-over, and the children filter.
    - `WatchItemService`, with the privacy cleanup.
    - The `ClassroomShareRelease` additions.
    - Tests for carry-over (including a weekend and a day off), the edit rule, author wording, the backup round trip, and routing to the `Shared` configuration.
  - **Don't run a schema-19 build on the Mac.** It opens the live notebook, and the installed Release copy can't open it afterward (the schema-18 lesson). Live checks go on the leased simulator.
  - Done when: the notebook iOS and Assistant builds are clean, and the named suites plus the new ones pass.
- **Phase 2: Calendar copies** (`feature-phase-deep`, after Phase 1).
  - Covers:
    - `SharedEventPublisher`: upsert by key, daily delete, dedup.
    - The per-device setting, on by default only on the Mac.
    - The hook in `CalendarSyncService`.
    - Tests with a fake event list: two devices publishing the same events produce one copy after dedup, and yesterday's copies are gone after a run.
- **Phase 3: Assistant Today tab** (`feature-phase`, Opus; after Phase 1, parallel with Phase 2).
  - Covers:
    - The tab, the opening rule and its tests (each closed signal and a day off), and the renamed notification.
    - The sections, the chips filter, the note sheet, swipe edit and delete, and plain-English errors.
    - Sample Class data for a day that looks like the mockup.
    - Screenshots on the leased simulator, as `sim-lease` tells it.
  - Done when: screenshots of Today (filtered and unfiltered), the note sheet, and a checked-off to-do match the mockup.
- **Phase 4: Nudges and tile dots** (`feature-phase`; after Phase 3, since it touches the same Assistant files).
  - Covers:
    - The notification category and both actions.
    - Scheduling in the reminder upkeep, and withdrawal on check-off and on leaving the class.
    - `todayMarks`, the dots, and the long-press lines.
    - Tests: a nudge is scheduled only for open to-dos with a time today; it is withdrawn when `doneAt` arrives; Done from the action saves and files.
- **Phase 5: Notebook side** (`feature-phase` for the Today section and settings; `feature-phase-light` for the MCP tools; after Phase 1, parallel with Phases 2–4 because it touches only notebook files).
  - Covers:
    - The Class notes section on Mac, iPad and iPhone.
    - The Add Watch For… sheet with the Issue picker.
    - The calendar setting.
    - `class_notes`, `add_class_note`, and the `update_issue` watch fields, with MCP tests.
- **Phase 6: Combine, review, schema, merge** (main session).
  1. Merge Phases 2–5.
  2. One full build: notebook iOS and Mac, and the Assistant.
  3. One whole-suite run each.
  4. `/code-review`, then fix what holds up, test-first.
  5. The Development schema init for schema 19: a Debug build with `CLOUDKIT_ENVIRONMENT=Development` and `-InitializeCloudKitSchema` on the leased test-account simulator, as for schema 16. Confirm `CD_ClassNote`, `CD_WatchItem` and `CD_SharedEvent` in CloudKit Console's Development environment.
  6. **Ask Danny in chat before Deploy Schema Changes to Production.** It's hard to undo, and it needs his yes each time.
  7. Merge to main and push with Danny's OK.
  8. **No roll-out until Production has schema 19.** When it ships, the Mac, iOS and the Assistant go together. The assistants update first.
- **Phase 7: Danny's steps.** These become Tide rows in `Areas/App Development/Cosmic Daybook/To do.md`. This plan links to each row with one line.
  - Deploy schema 19 to Production (if it wasn't done in Phase 6 with him).
  - Roll out: the Assistant to the Assistants group first, then the notebook.
  - Check on a device: write a meds to-do with a nudge on the Mac, check it off on one assistant phone, and confirm the other phone doesn't ring.
  - Check: a watch-for line disappears from the phones after its until-day.

## Cost

This plan is roughly the size of the ParentLocker plan: a schema change, both apps, and MCP. Estimate about 15–25% of the weekly all-models limit:
- Phase 1: ~4–6%.
- Phases 2, 4 and 5: ~2–3% each.
- Phase 3: ~3–4%.
- Phase 6: ~3–5%.

Check usage before starting. If less than 25% is left before the weekly reset, run Phases 1 and 3 first. They are the part the assistants will see.

## Open questions for Danny

1. **Early dismissal.** The school calendar has no early-dismissal or half-day field; the mockup's "Early dismissal at 12:30" was a guess. **Proposed:** put it on the calendar as an event, and it shows in the Schedule and Tomorrow sections like any other event. Adding a dismissal time to the school calendar would be its own small schema change.
2. **Nudges on your devices.** Should your Mac or iPhone also get a nudge when a to-do goes unchecked? **Proposed:** no; only the assistants' phones.
3. **Dots in the notebook.** Should the notebook's own iPhone attendance grid show the dots too? **Proposed:** not now. The value is there (`todayMarks`), so switching it on later is one line.

## Ruled out

- **Sharing `CDCalendarEvent` or `CDIssue` themselves.** A shared record carries every field: event notes, Issue descriptions and history.
- **Reusing `CDTodoItem` or `CDNote`.** Both are private and heavily used. Sharing `CDTodoItem` would put every one of Danny's to-dos in the share, and `CDNote` hangs off about ten parents.
- **Moving a to-do's `day` forward to carry it over.** Several devices would write the move at once. Carry-over is derived instead.
- **A per-child note on `CDAttendanceRecord.note`.** It's one note per child per day, not class-wide, and it has no to-do or check-off.
- **A full Issue editor.** A separate plan if Danny wants one.

## Progress

- [ ] Phase 1: Schema 19 and the shared services
- [ ] Phase 2: Calendar copies
- [ ] Phase 3: Assistant Today tab
- [ ] Phase 4: Nudges and tile dots
- [ ] Phase 5: Notebook side
- [ ] Phase 6: Combine, review, schema, merge
- [ ] Phase 7: Danny's steps (Tide rows)
