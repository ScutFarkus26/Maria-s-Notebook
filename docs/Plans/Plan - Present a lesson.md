> Archived 2026-10-04: built and on main.

# Post-Presentation Workflow

> **Done 2026-10-01** (6948166c).
> In short: Present a lesson: one sheet, three beats, and its validation checklist.
> "Present a lesson: one sheet, three beats" is on main; this file is the design and its manual validation checklist.

## Purpose

After a guide gives a presentation, the app must preserve the natural AMI cycle:

**present → observe independent work → interpret what was seen → decide what comes next**

Recording the presentation is immediate. Noticing is brief and optional. Each child's next step is the guide's own choice, one tap per child, and stays visible until it is resolved. The workflow never asks for a compulsory score or developmental judgment at the moment of presentation.

The design follows these guardrails:

- observe each child individually, even after a group presentation;
- record what was seen before deciding what it means;
- allow time for repetition and concentration instead of rushing to the next lesson;
- keep every planning decision with the guide;
- do not interrupt the work cycle with a forced deadline or notification.

## One sheet, three beats (2026-10-01)

The presentation sheet replaced three surfaces (the planning sheet's Just Presented / Previously Presented pills, the stacked **What Happened?** reflection, and **Follow This Presentation**) and the separate three-panel workflow. The design board is the "Present a Lesson Redesign" canvas.

### 1. Who was there → Record

- The header band names the lesson, its area and sequence, and when it is planned or was given. Everything about planning it (Change Lesson, Reschedule, Find or Move Students, Open Lesson File, Delete) lives in the header's ⋯ menu.
- The sequence recap folds to one line and opens to the full grid. Its rows are where one child's mastery of a lesson is set.
- **Who was there?** shows a tile per child, ticked from that day's attendance. A child marked absent starts unticked with "stays on the plan". Tapping a tile changes it.
- The pinned footer has the day (Today ▾ / Yesterday / Pick a Day… / Earlier, Date Unknown), Cancel, Save (plan edits only, ⌘S) and **Record Presentation · N children** (⌘↩).
- Record takes the unticked children off onto a plan of their own for the same lesson (their promoted year-plan entries follow them), then records the rest (`PresentationRecorder` → `ImmediatePresentationRecordingService`). **Earlier, Date Unknown** marks it given without a date, never today's.

### 2. How it went (the same sheet)

- The header says **Recorded · today** with **Undo**, which reverses the recording for as long as the sheet is open.
- **What did you notice?** takes one note for the group, typed or dictated. **Split by Child** sorts the guide's words into a note on each child; the organizer's follow-up guesses are ignored.
- **What's next for each child** uses one vocabulary, the command bar's (`CaptureFollowUp`): Practice · Follow-up work · Re-present · Ready for next · Keep watching. The **Everyone** row sets the default from the lesson's progression rule (practice required → Practice, otherwise Keep watching). Tapping a child's chip overrides only that child. With one child there is one row.
- **Check the work**: Next work cycle (no date), the next school day, or Pick a Day…. It shows only when a decision gives work.
- **When you press Done** lists in plain words what Done will write. Nothing is written before Done.
- **Done** (⌘↩) applies notes and decisions in one save (`PresentationSessionCommit`). **Later** files the notes now (they are facts) and keeps the decisions as a draft (`PresentationSessionDraftStore`); the presentation stays in Following. Closing the sheet acts as Later, with no dialog.

### 3. One click from the list

A Ready row in **Lessons & Work** has **Presented** on hover (Mac) and **Presented Today** in its context menu (all platforms). It records today for the children who are there, applies the lesson's rule, and shows a toast with **Undo** (which also removes the work it created) and **Details…** (which opens How It Went on the same record). `PresentationQuickRecord`.

## What Done writes, per decision

| Decision | Writes | Follow-up row |
|---|---|---|
| Practice | `CDWorkModel` "Practice: <lesson>" (kind practice), check-in on the chosen day | open, **Check Work**, review day = check-in day |
| Follow-up work | `CDWorkModel` "Follow up: <lesson>" | open, **Check Work** |
| Re-present | flags the presentation `needsAnotherPresentation`; a new plan On Deck for that child | resolved **Offer Support or Re-present** |
| Ready for next | confirms the child on this presentation; the next lesson in the sequence goes On Deck once | resolved **Ready for a Related or Next Lesson** |
| Keep watching | flags the child's note for follow-up when there is one | open, **Keep Watching** |

Work, re-presentations and confirmations go through `CaptureFollowUpPersistence`, the same code as the command bar's capture review and MCP `record_presentation`. Observations go through `PresentationOutcomePersistenceService`. Reopening a presentation reads each child's standing decision back from her row and work (`PresentationSession.appliedState`); Done applies only what changed.

## Lessons & Work workspace

**Lessons & Work** is the single planning workspace for the presentation-to-practice cycle. The former presentation planner, follow-up queue, and Open Work destination are available as four guide-facing views:

- **Needs Attention** combines open presentation follow-ups with work that is due, overdue, ready for review, or stale. Presentation follow-ups appear under **Observe or Decide** and actionable work appears under **Check Work**. These remain separate, directly clickable responsibilities even when they belong to the same learning cycle, so one child's unresolved observation cannot hide another child's overdue work.
- **Upcoming** contains presentations that are ready or scheduled and the students who may need a lesson. It reuses the presentation planner without creating a second calendar.
- **Children Working** contains all active child work, with work-type filters, search, sorting, scheduling, completion, and new-work actions.
- **History** contains recorded presentations and completed child work. A small switch inside History moves between those two records. The Agenda is intentionally unavailable in this view.

Search follows the selected view. On macOS the four views appear in the window toolbar. On iPhone they appear in the **Lessons & Work** view menu so only one major work surface is shown at a time.

### Shared Agenda

The shared **Agenda** shows scheduled presentations and work check-ins together across the next school days. It is the only calendar in **Lessons & Work**: **Upcoming** supplies presentations to it, and **Children Working** supplies check-ins and work that can be scheduled into it.

On macOS the Agenda is a resizable lower pane that can be shown or hidden. On iPhone it is hidden initially; the calendar button swaps the current work surface for the Agenda. The Agenda is available from **Needs Attention**, **Upcoming**, and **Children Working**, but not **History**. Opening an item returns to its exact presentation or work detail.

## Where open follow-ups appear

All three surfaces read the same per-child follow-up records:

- **Today → Following Presentations** shows the first three open presentations. **View All** opens **Lessons & Work → Needs Attention**.
- **Lessons & Work → Needs Attention** shows the complete grouped queue together with work that currently needs a guide check.
- **Student → Current Learning → Following Presentations** shows only that child’s open presentation follow-ups.

Opening a queue item returns to the exact presentation detail and its persistent follow-up. A presentation leaves these surfaces only when every included child’s follow-up has been resolved.

## Data ownership

- `CDLessonAssignment` identifies the exact presentation and stores its lesson, participants, presented state, and presentation date.
- `CDLessonPresentation` stores one child's history and follow-up for that exact presentation. The `(presentationID, studentID)` pair is the stable identity. It stores the open action, optional review date, and explicit resolution.
- `CDNote` stores shared and child-specific notes linked to the exact presentation.
- `CDWorkModel` is created only by Done (or one-click Presented) for a Practice or Follow-up work decision.
- `CDWorkCheckIn` is created only by Done, for a chosen check-in day; one already scheduled on the work is moved rather than duplicated.
- A re-presentation or next-lesson `CDLessonAssignment` is created only by Done, for those decisions.
- The Later draft is one JSON blob per presentation in UserDefaults (`PresentationSession.draft.<id>`), removed by Done.

There is no compulsory rating and no group-wide mastery control.

## Apple Intelligence boundaries

Apple Intelligence may sort the guide's spoken or typed note into notes on each child (**Split by Child**), keeping the guide's words, and falls back to leaving one group note.

It may not invent an observation, infer readiness, choose a decision, or save anything. Every decision on the sheet is the guide's tap, and nothing is written before Done or Later.

Spoken notes require on-device speech recognition.

## Persistence rules

- Recording is immediate and uses a scoped Undo transaction; Undo stays available until the sheet closes.
- New recordings open **Keep Watching** for every child recorded.
- Reopening a presentation with an open follow-up or a Later draft returns to How It Went.
- Done is one atomic save: notes, work, check-ins, row changes and plans land together or not at all, without rolling back unrelated edits in the shared context (`ContextMutationTransaction`).
- An earlier presentation with an unknown date remains undated.
- Existing and backfilled legacy rows are not added to Following on upgrade.

## Manual validation checklist

- A lesson planned for three children, one marked absent today: the absent child starts unticked; Record makes a plan of her own and records the other two.
- How It Went: set Everyone to Practice, one child to Re-present, pick a check-in day; the summary lists exactly that; Done creates two practice works with check-ins, one re-presentation plan, and the row states in the table above.
- Later with a note and an override: the note is saved at once; reopening from Following restores the override.
- Undo right after Record returns to Who was there with nothing recorded.
- One-click Presented on a Ready row (practice-required lesson): works are created; Undo in the toast removes them and the recording; Details… opens How It Went.
- Mac: ⌘↩ records and finishes; Esc is Later in How It Went and Cancel in Who was there.

