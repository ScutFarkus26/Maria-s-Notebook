# Plan - Next lesson row when presenting

> **Not started.**
> In short: when a child is marked Ready for next in the present-a-lesson sheet, a "Next lesson" row shows where the next lesson will go (the Inbox by default) and lets you put it on a day, with an optional start time, before you press Done.

Written 2026-11-11. Branch `claude/lesson-auto-inbox-scheduling-286848`, starting from main `e3549bb6f`.

## Why

Danny asked: "When I present a lesson and mark the student ready for next, I'd like for it to be automatically put into the inbox with the option to schedule."

Half of this already happens, quietly. On Done, `PresentationSessionCommit.planNextLesson` makes one unscheduled plan for the next lesson in the sequence for every newly ready child. The sheet calls that "On Deck"; the Checklist and the week call the same list "the Inbox". What is missing is:

1. the sheet saying, in the app's usual word, that the lesson goes to the Inbox, and
2. a way to put it on a day (and a start time) right there, instead of opening the week afterwards.

Three mockups were drawn (canvas: https://claude.ai/artifact/LGNvb4cBi7SFjBroZTM5xb). Danny chose **Option A**.

## What it looks like (Option A)

In the How It Went step, under the Everyone row (or under the only child's row when one child was there), a row appears as soon as anyone is newly Ready for next and there is a next lesson to plan:

```
Next lesson    Collective Nouns
               [ Inbox ]  [ Thursday ]  [ Pick a Day… ]
               For Maya and Leo. Waits in the Inbox until you give it a day.
```

After choosing a day:

```
Next lesson    Collective Nouns
               [ Inbox ]  [ Thursday ]  [ Pick a Day… ]  [ Set time ]
               For Maya and Leo. Goes on the week for Thursday, Nov 12.
```

- **Inbox** is chosen to begin with.
- **Thursday** is the next school day (the same one the "Check the work" row offers).
- **Pick a Day…** opens the same small calendar the check-in row uses; its button reads "Schedule on This Day". A picked day shows as its own chosen chip ("Mon, Nov 16").
- **Set time** is a dashed chip that appears only once a day is chosen. It opens the lesson time picker from the lesson-times work; with a time set it reads "10:00" and is drawn chosen. Removing the time in the picker returns it to "Set time".
- The caption names who the plan is for and where it goes.
- The "When you press Done" card says the same thing:
  - "Maya and Leo are ready for the next lesson: Collective Nouns goes in the Inbox"
  - "…: Collective Nouns is scheduled for Thursday, Nov 12"
  - "…: Collective Nouns is scheduled for Thursday, Nov 12 at 10:00"

The row is hidden when nobody is newly ready, when the lesson is the last in its sequence, and when every newly ready child is already on a plan for the next lesson that has not been given yet (nothing new would be made).

## Decisions, and why

1. **The word is "Inbox".** The Checklist ("Add to Inbox"), the week ("Clear All to Inbox") and the lesson's sheet ("Inbox Status") already say Inbox for unscheduled plans. The five places that still say "On Deck" change with this work so one sheet never uses both words:
   - `Cosmic Daybook/Presentations/Session/PresentationSessionSummary.swift:60` → "…will see it again: a re-presentation goes in the Inbox"
   - `…/PresentationSessionSummary.swift:84` → the new lines above
   - `Cosmic Daybook/Students/Presentations/PresentationDetailView+PlanningSections.swift:31` → "In the Inbox, not yet scheduled"
   - `Cosmic Daybook/Students/Meetings/Tab/WorkDecisionCard.swift:170` → "Puts the next lesson in the Inbox when you complete the meeting"
   - `…/WorkDecisionCard.swift:173` → "Goes in the Inbox when you complete the meeting"

   Code comments and identifiers that say "On Deck" are left alone.

2. **Nothing is created until Done.** The row is a choice held in the sheet, like every other decision there. Later keeps it in the draft; Cancel and Undo make nothing. This is why the scheduling is not a second step after Done (Option C).

3. **One plan for the group, on one day.** As now: the newly ready children share one plan. There is no per-child day.

4. **When the year plan already has a day for it, the row starts on that day.** Today, if any of the ready children has a year-plan entry for the next lesson dated today or later, the "unscheduled" plan is silently put on the earliest such day (`YearPlanPromotionService.autoPromoteIfPlanExists`). The sheet has been saying "goes On Deck" while that happened. Now the row shows what will happen: that day is the chosen chip, with the caption "For Maya. The year plan has it on Monday, Nov 16." Tapping Inbox overrides it and the plan really does wait in the Inbox (the year-plan entry stays Planned on its day, exactly as an entry that is behind pace does today, and is promoted when the plan is later given a day).

5. **A day with no time joins the end of the morning.** `DayHalfPlanner.slot(DayHalfPlanner.lastSlotRank, in: .morning, on: day)`, the idiom `MCPNotebookTools+ScheduleWrites.swift` uses. A new lesson should not jump ahead of what is already planned that morning. There is no morning/afternoon choice in the row: a set time in the afternoon puts it in the afternoon, and the week can move it otherwise.

6. **A set time is written the way the card's picker writes one.** `DayHalfPlanner.settingTime(hour:minute:on:using:)` then `assignment.schedule(for:using:)`, so 9:00 and 2:00 on the hour stick (lesson-times plan, decision 4).

7. **Scheduling moves the year plan with it and lays nothing after.** With a day chosen, `YearPlanPromotionService.promoteMatchingEntries(into:scheduledFor:context:)` runs inside the same transaction. No sequence is laid out on the later lessons (removed 2026-11-03; must not come back).

8. **Any day can be picked,** as with the check-in row. The quick chip is always a school day; the calendar does not block weekends or days off. (If Danny wants a "No school that day" note under the row, it is a small addition: see Open questions.)

9. **Old drafts still open.** The new draft field is optional. A saved day that has passed by the time the sheet is reopened is dropped and the row goes back to its starting choice.

## Ruled out

- **Option B, a card that shows the week** in the sheet: more to read at the moment of recording, and it duplicates the week view.
- **Option C, a banner after Done** with a Schedule… button: a second step, easy to miss, and the plan would exist before the choice was made.
- **A day per child**, and a morning/afternoon picker in the row: the week does both already.
- **The same row in meetings** ("Ready for next" on a meeting's work card, `MeetingLessonDecisions.planNextLessons`): only its wording changes here. Worth doing later if the row proves useful.
- **MCP `record_presentation` and the command bar:** they confirm the child as ready and make no plan today (`CaptureFollowUpPersistence.persist`). Unchanged.
- **Quick record** (`PresentationQuickRecord`): only ever records Practice or Keep watching. Unchanged.

## How it is built

All source paths are under `Cosmic Daybook/`. No Core Data model change, no backup format change, no new MCP tool.

### 1. The choice: `Presentations/Session/PresentationNextLessonPlace.swift` (new)

```swift
/// Where the next lesson goes when a child is marked Ready for next.
nonisolated enum PresentationNextLessonPlace: Codable, Equatable, Sendable {
    case inbox
    /// `day` is a start of day; `minute` is minutes after midnight, nil for no set time.
    case on(day: Date, minute: Int?)
}
```

Plus small helpers: `day`, `clockTime: LessonClockTime?`, `withTime(hour:minute:)`, `withoutTime`, and a `phrase` used by the caption and the summary ("goes in the Inbox" / "is scheduled for Thursday, Nov 12 at 10:00"), formatted with the app's existing date and time styles.

### 2. What the sheet needs to know: `Presentations/Session/PresentationNextLessonContext.swift` (new)

A value loaded once when the How It Went step appears:

```swift
struct PresentationNextLessonContext {
    let lessonID: UUID
    let lessonName: String
    /// Children already on a plan for it that has not been given.
    let alreadyPlanned: Set<UUID>
    /// Each child's year-plan day for it, today or later.
    let yearPlanDays: [UUID: Date]

    static func load(after lesson: CDLesson, lessons: [CDLesson], studentIDs: [UUID],
                     context: NSManagedObjectContext, today: Date = Date()) -> Self?
    func recipients(newlyReady: Set<UUID>) -> Set<UUID>          // newlyReady − alreadyPlanned
    func startingPlace(for recipients: Set<UUID>) -> PresentationNextLessonPlace   // earliest year-plan day, else .inbox
}
```

`load` uses `PlanNextLessonService.findNextLesson(after:in:)`, the same unpresented-plans fetch `planNextLesson` does now (moved here so the sheet and the commit share it), and a new read-only `YearPlanPromotionService.plannedDay(lessonID:studentID:context:)` lifted out of `autoPromoteIfPlanExists` (which then calls it, behavior unchanged).

### 3. The session: `Presentations/Session/PresentationSession.swift`

- `var nextLessonPlace: PresentationNextLessonPlace?` — nil means "not chosen; use the starting place".
- `newlyReady(for:)` — the children newly Ready for next, alone or alongside work (from `pendingDecisions(for:)` and `newlyAlsoReady(for:)`).
- `commitInput(...)` passes `nextLessonPlace` through.
- `draft` saves it; `loadDecisions(...)` restores it, dropping a day before today.
- `forgetHowItWent()` clears it.

`PresentationSessionDraftStore.Draft` gains `nextLessonPlace: PresentationNextLessonPlace?` (optional, so an older draft still reads).

### 4. The commit: `Presentations/Session/PresentationSessionCommit.swift`

`Input` gains `nextLessonPlace: PresentationNextLessonPlace?`. `planNextLesson` becomes:

| Choice | What happens |
| --- | --- |
| nil (nothing chosen) | Exactly today's behavior: `planLesson(...)` with year-plan auto-promotion. |
| `.inbox` | `planLesson(..., autoPromoteFromYearPlan: false)`. The plan is unscheduled. |
| `.on(day, minute)` | `planLesson(..., autoPromoteFromYearPlan: false)`, then schedule the returned plan (decisions 5 and 6), then `YearPlanPromotionService.promoteMatchingEntries(into:scheduledFor:context:)`. |

All of it stays inside the existing `ContextMutationTransaction` and its single save. `Receipt` gains `nextLessonScheduledFor: Date?` for the tests. `commitDone` already calls `PresentationDetailUtilities.notifyInboxRefresh()`.

The sheet always sends a concrete choice when the row is showing (the starting place if untouched), so what the row says is what the commit does. The nil case is kept for callers and tests that do not use the row.

### 5. The summary: `Presentations/Session/PresentationSessionSummary.swift` and `PresentationHowItWentView+Summary.swift`

`Input` gains `nextLessonPlace: PresentationNextLessonPlace` and `nextLessonAlreadyPlanned: Bool`. The readiness line ends with the place's phrase; when nothing new will be made it reads "…ready for the next lesson: already planned for Collective Nouns". The re-present line says "goes in the Inbox".

### 6. The row: `Presentations/Session/PresentationNextLessonRow.swift` (new) and `PresentationHowItWentView.swift`

A small view of its own (its own state for the calendar popover and the time picker), built from the pieces the check-in row uses: `PresentationDecisionChip` (`.chosen`, `.plain`, and the dashed `.inherited` look for "Set time"), the 130-point label column, and the graphical `DatePicker` popover. The time chip uses `.lessonTimePicker(item:)` with `LessonTimePicker(lessonTitle:current:takenMinutes:startingHalf:set:remove:)`; `takenMinutes` comes from `ScheduledDateEdits.takenMinutes(on:excluding:in:)` so times already used that day are dimmed. The picker needs no saved plan, so it works before Done.

`PresentationHowItWentView` loads the context in its existing `.task`, and shows the row in `everyoneRow` and `onlyChildRow` after the check-in and follow-up rows when `recipients` is not empty. `PresentationDetailView+Recording.swift` passes `lessons` in place of the `nextLessonName` it computes on every redraw.

Accessibility: each chip carries its meaning in its label ("Schedule for Thursday", "Start time, 10:00"); the caption is read with the row. Same view on iPhone, iPad and Mac; on the iPhone the time picker is the half-height sheet the presenter already provides.

### 7. Tests (`Cosmic Daybook Tests/Presentations/`)

- `PresentationSessionTests.swift`: the place starts nil; draft round trip with Inbox, a day, a day and time; a draft saved before the field existed still reads; a past day is dropped on load; `newlyReady` with Ready alone and alongside work.
- Summary: the three destination lines, the already-planned line, the re-present wording.
- `PresentationSessionCommitTests.swift`:
  - Inbox chosen → plan has no `scheduledFor`, even when a child has a year-plan entry next week, and that entry stays Planned.
  - A day → plan is scheduled on that day at the end of the morning, reads as no set time, and the year-plan entry is promoted and moved to that day.
  - A day and 10:15 → `ScheduledDateEdits.clockTime(of:)` reads 10:15; 9:00 exactly reads back as 9:00.
  - nil → unchanged behavior (existing tests keep passing untouched).
  - A child already on an ungiven plan is not planned twice; with every child already planned nothing is made.
  - No year-plan entries appear on later lessons of the sequence.
- `PresentationNextLessonContext`: recipients and starting place (year-plan day wins; a past day does not).
- A render test (`ImageRenderer`, as in earlier work when the simulator can't be tapped) draws the row in its three states for Danny to look at.

## Checks before calling it done

From the repo root, on this checkout's simulator:

```bash
Scripts/locked_xcodebuild.sh build-for-testing -project "Cosmic Daybook.xcodeproj" -scheme "Cosmic Daybook" -destination "platform=iOS Simulator,id=$(~/.claude/bin/sim-lease)" COMPILER_INDEX_STORE_ENABLE=NO SWIFT_ENABLE_PREFIX_MAPPING=YES SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES CLANG_ENABLE_PREFIX_MAPPING=YES
```

then `test-without-building` through `~/.claude/bin/build-turn` with `-parallel-testing-enabled NO` (one simulator) and `-only-testing:` for `PresentationSessionTests`, `PresentationSessionCommitTests`, the new suites, and the lesson-time suites (`LessonTimePickerTests`, `DayHalfTests`); confirm each ran a non-zero number of tests. Then the Mac build (build only; Mac tests open the live notebook), the whole iOS suite once, zero warnings, SwiftLint clean, and `sim-lease --done`.

Not checked by this plan, and to be added to the Cosmic Daybook list in Tide under "Check on a device" when the work lands: the row on the Mac sheet, the iPad sheet and the iPhone (time picker as a sheet), with VoiceOver on one of them.

## Open questions

None that block the build. Two things Danny may want different, both small to change afterwards:

- "On Deck" becomes "Inbox" in the meeting card and the lesson's sheet too (decision 1). Say so to keep "On Deck" there.
- A day off picked from the calendar is accepted without comment (decision 8).

## Progress

- [ ] The choice, the context, the session and draft
- [ ] The commit and its tests
- [ ] The summary wording and the five "On Deck" strings
- [ ] The row in the sheet, with the time picker
- [ ] Pictures of the row
- [ ] Full checks; Tide rows; build board
