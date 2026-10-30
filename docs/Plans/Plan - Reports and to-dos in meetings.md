# Reports and to-dos in meetings

> **Not started.** Written 2026-10-30 from Danny's talk-through (branch `claude/keep-working-practice-difference-35b458`); a mockup of the right column was shown in the session. Waiting for his go-ahead.
> In short: a child's reports get five stages, ending with presenting to the class, and are tracked as report work on the meeting's left column, on a new Reports view in Lessons & Work, and on Today on the day she presents. The meeting's right column gets a For Me to Do section for your own to-dos about her.

## What Danny wants
- Things he needs to do, in the meeting's right column.
- A way to see each child's reports and presentations in the meeting, and to track every child's reports and presentations at once.
- His answers on 2026-10-30:
  - A child's presentation is **the last stage of her report**, not a separate thing.
  - **Five stages for every report**, book reports included: Topic, Research, Writing, Ready, Presented.
  - Reports go **in the work cards on the left**, under a header of their own that separates them from her other work (not in the right column, as the first mockup had them).
  - A to-do typed in the meeting is **filed when the meeting is completed**, like lesson requests. Clear Meeting drops it.
  - There's a **Reports page** for the whole class.

## What's there today
- Report is already a kind of work (`WorkKind.report`). Elisheva and Avigail's trampoline report is one: report work from the Research Report lesson, with a linked copy for each girl. The notebook also has a Book Report lesson.
- Report work can carry ordered steps (`CDWorkStep`: title, order, completed date). The work detail shows them, but no report uses them yet.
- Toba's reports (fossils and birds with Maya, squishies with Leora) are written only in her September meeting reflection, not recorded as work. Other reports live in to-dos ("Help Ora and Avital set deadlines and checkpoints for the cats report"). So nothing tracks reports today.
- To-dos (`CDTodoItem`) already carry the children they're about. Every open to-do with no linked work and no Someday goes to Tide when Tide sharing is on.
- Check-ins (`CDWorkCheckIn`) have a day and a purpose, and show on Today and the Scheduled strip.
- Lessons & Work has a Presentations | Work picker (`WorkspaceKind`).
- The student page's Progress tab already lists her open reports.

## Words
In the app, "presentation" means a lesson you give. A child presenting her report is called **"presents to the class"** on screen ("Presents to the class Nov 12", stage "Presented"), so the two never mix.

## 1. A report's five stages
- The stages are the report's steps: Topic, Research, Writing, Ready, Presented. **The stage she's at is the first step not yet ticked.** Steps before it are ticked with the day they were passed.
- A new report gets the five steps when it's made. An existing report with no steps gets them the first time its stage is set. A report that already has steps of its own (made in the work detail) keeps them and shows them as its stages.
- **Setting a stage** ticks every step before it and unticks it and every step after it.
- **Presented** ticks all five and closes the report as Finished. Moving back from Presented reopens it.
- **Linked copies move together.** Toba's and Leora's copies of Squishies are one report, so a stage set in either child's meeting (or on the Reports view) sets it on every copy. This follows the way check-ins already go to every linked copy by default.
- **On hold** is Rest, as today.
- **The day she presents** is a check-in on the report with the purpose "Present to the class", on every linked copy. It shows on Today and the Scheduled strip like any check-in, and on the report's card and the Reports view. Setting it is offered once the report is at Writing or later.
- When that check-in is marked done (on Today or anywhere else), the report moves to Presented.

## 2. Reports on the meeting's left column
```
Needs a Decision · 1 of 3 done
  [work cards as today, without reports]

Reports · 3
  ✓ Squishies · with Leora                         ↗
    Working · 41 days · presents to the class Nov 12
    [Topic ✓] [Research ✓] [Writing] [Ready] [Presented]
    [ Rest… ]  [ Presents on… ]
    Note…
  ○ Fossils · with Maya  ...
  + Start a report

Open Work · 4
  [as today, without reports]
```
- Her open reports (open or resting) leave Needs a Decision and Open Work, and get their own **Reports · N** header right under Needs a Decision. Each is a full card (not a one-line row), since every report wants a look in the meeting.
- **The report card** shows the title, who she's writing it with, the stage chips, Rest… and Presents on…. Tapping the stage she's already at confirms she's still there. Tapping any stage, or Rest, counts as the card's decision (tick, note field), as the work cards do now. Mastered, Re-present and Ready for Next aren't offered on a report.
- A stage set in the meeting is saved right away, as a status choice is today. Clear Meeting leaves it, as it leaves Mastered. A Presented close keeps its receipt, so moving back or Clear takes it back, as Finished does today.
- **+ Start a report** opens a small sheet: the topic (which becomes the title), who she's writing it with (other children, optional), and the lesson it comes from. The lesson picker lists the lessons whose default kind of work is Report, plus "No lesson". It makes report work for her and each partner as linked copies, with the five steps, at Topic. It's made right away, not on Complete, so its card appears at once. A report started by mistake is deleted from its detail, as any work is.
- On the iPhone's meeting sheet (`MeetingCompactSheet`) the same Reports section appears, since it uses the same pane.

## 3. For Me to Do on the meeting's right column
- A new section after Lesson Requests and before Private Notes: **For Me to Do**, captioned "What you owe her. New lines go to your to-dos when you complete."
- It lists her open to-dos (any open to-do naming her), each with a tick box, and a field to add a new line with an optional due day.
- **On Complete**, in the meeting's one save: each new line becomes a to-do naming her, tagged with her name the way follow-ups are, with "From her meeting on Oct 30" in its note. Each ticked to-do is marked done. If the save fails, none of it is filed.
- **Clear Meeting** drops new lines and ticks.
- The new to-dos have no linked work, so they go to Tide like your other to-dos.
- The draft keeps new lines and ticks (`MeetingPersistenceService.CurrentMeetingData`), so they survive closing the window and merge between two open windows the way the other draft fields do.

## 4. Reports view in Lessons & Work
- A third choice in the picker: **Presentations | Work | Reports**.
- **Presenting soon**: the next two weeks' "Present to the class" days, by day.
- Then every open report, one row per report (linked copies folded into one row naming everyone), grouped by stage: Topic, Research, Writing, Ready. Resting reports sit in their own group at the end. Each row shows the children, days since it started, and its present day if it has one.
- Tapping a row opens the work detail. A stage can also be set from the row (the same chips, in a menu on the Mac and a swipe or menu on the iPhone).
- **Presented this year**: a folded list of finished reports with the day they were presented.
- The student page's Progress tab shows each report's stage beside its name.

## Code
- **Stages**: a small `ReportStages` helper in `Work/Steps/` (the five titles, current stage, set stage across linked copies through `WorkGrouping`, adding the steps to a report that has none), built on `WorkStepService`. Presented closes through `WorkLogService` (the only status writer) and in a meeting through `MeetingDraftModel.decide`, so it gets a receipt.
- **Present day**: `WorkCheckInService` with the purpose "Present to the class" on every linked copy. Hook the check-in's done path so it moves the report to Presented.
- **Meeting left column**: `MeetingContextPane` splits reports out of `stuckWork` and `openWork` into a Reports section. A new `ReportDecisionCard` (beside `WorkDecisionCard`) holds the stage chips, Rest and Presents on. `MeetingDraftModel+Decisions` gets `setStage(_:for:)`. A `StartReportSheet` for + Start a report.
- **Right column**: `MeetingFormPane` gets a `ForMeToDoSection`. The draft gets `newTodos` and `doneTodoIDs` (stored, merged, cleared). `MeetingDraftModel+Complete` files them inside the existing transaction. The to-do is made the way `MCPNotebookTools+FollowUps` makes one (student IDs, student tags).
- **Reports view**: `WorkspaceKind.reports`, a `LessonsAndWorkReportsView` in `Work/Agenda/`, and the picker on the Mac toolbar and iPhone header.
- **Progress tab**: the stage beside each active report.
- **No schema, backup or CloudKit change**: steps, check-ins and to-dos all exist, and the draft is stored on the device. No MCP change is needed: `work_detail` already lists a report's steps and check-ins.

## Checks
- Tests: setting a stage ticks and unticks the right steps on every linked copy; a report with no steps gets the five; Presented closes as Finished with a receipt and moving back reopens; Rest still works on a report; Start a report makes linked copies at Topic; marking the present-day check-in done moves the report to Presented; reports leave Needs a Decision and Open Work; For Me to Do files on Complete, rolls back on a failed save, clears on Clear, and survives the two-window merge; the Reports view's grouping folds linked copies into one row.
- iOS build and those suites; a macOS compile; the left column, the right column and the Reports view drawn at phone and Mac widths, light and dark, with the Sample Class.
- Whole suite once at the end.

## Open questions
1. Linked copies move together (section 1). If Leora is at a different stage from Toba on the same report, should they ever be set apart?
2. Marking the "Present to the class" day done moves the report to Presented (section 1). Should that need a tap in the meeting instead?

## Data steps for Danny (after it's built)
- Set the Research Report and Book Report lessons' default kind of work to Report, so they're offered in Start a report.
- Start Toba's three reports (and the other children's) from their next meetings, or ask a session to add them over MCP.
