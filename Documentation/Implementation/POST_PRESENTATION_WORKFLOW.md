# Post-Presentation Workflow

## Purpose

After a guide gives a presentation, the app must preserve the natural AMI cycle:

**present → observe independent work → interpret what was seen → decide what comes next**

Recording the presentation is immediate. Reflection is brief and optional. Follow-up is persistent and remains visible until the guide observes the child or explicitly plans the next action. The workflow does not ask for a compulsory score or developmental judgment at the moment of presentation.

The design follows these guardrails:

- observe each child individually, even after a group presentation;
- record objective evidence before deciding what it means;
- allow time for repetition and concentration instead of rushing to the next lesson;
- keep every planning decision with the guide;
- do not interrupt the work cycle with a forced deadline or notification.

## Default flow

1. The guide chooses **Just Presented**.
2. The app immediately records the exact lesson, children, and date. This action remains reversible through **Undo Presentation**.
3. The app creates one open follow-up for each child in the presentation. Every child begins at **Keep Watching**.
4. The optional **What Happened?** reflection opens. The guide can type or dictate a factual observation, organize it for review, save it, or continue without adding anything.
5. Finishing or dismissing the reflection does **not** close the presentation detail. It reveals **Follow This Presentation** in the same detail window or sheet.
6. The guide can optionally record the exact follow-up work invited for the child, such as **Practice Presentation**, **Write and Symbolize Four Sentences**, or **Biography on Stan Lee**. The work appears immediately in **Lessons & Work → Children Working**.
7. The guide can leave **Keep Watching** in place, choose a different guide follow-up for the whole group, or adjust children individually. The work invitation and the guide's follow-up are coordinated but independent: adding work does not silently decide what the guide should do next.
8. The guide chooses **Close** only when ready to leave. The app closes the presentation and opens the appropriate place in **Lessons & Work** so the saved next step is visible. **Back to Lesson** returns to the lesson detail without discarding the saved work or follow-up.

Only the explicit **Close** action dismisses the presentation detail after the normal **Just Presented** flow. Closing it does not remove the follow-up. If any child still has an open guide follow-up, the app opens **Needs Attention** and focuses that presentation. If all guide follow-ups are complete but the presentation has linked work, it opens **Children Working** and focuses that work. If neither remains, it opens **History**. On macOS this routing happens as the presentation window closes; on iPhone it happens as the presentation sheet closes.

The presentation remains recorded if the guide discards only the optional reflection. **Undo Presentation** reverses only the immediate presentation action and restores the prior per-child history; it leaves older presentation history untouched.

## Follow-up choices

### Child's Follow-Up Work

This optional section records what the child was invited to do after the presentation. It is not a required assignment and it is not created automatically.

The guide:

- chooses **All Children** or one child using the shared **Planning for** control;
- enters the exact, recognizable title of the work;
- chooses the work type;
- may start from an editable lesson suggestion or Sample Work template; and
- chooses **Add Work** to confirm it.

The app creates one real, active work record for each child in scope. Every record keeps the exact presentation and lesson links, so it appears immediately in **Lessons & Work → Children Working**, can be found by its title, and remains available from the presentation's related-work history. The work field remains available in the open sheet even if the guide finishes that child's separate guide follow-up first, so the result never depends on entry order. Reopening the follow-up shows the work already added for the current scope. **Review Work** closes the follow-up and opens **Children Working**, focused on the linked work, for any later editing or correction.

Typing a title does not create work until the guide chooses **Add Work**. While that text is unsaved, Close, Back to Lesson, Review Work, and interactive sheet dismissal are protected. The guide can keep editing or explicitly discard the unfinished invitation. The unfinished text is also retained locally for 30 days and restored for the same presentation and child scope if a Mac window closes unexpectedly; the recovery draft never creates child work on its own.

Several distinct invitations may be recorded for the same child and presentation. Re-entering the same title and work type does not create a duplicate. Choosing no follow-up work remains a valid choice.

### Keep Watching

This is the per-child default. It carries no due date and creates no extra work, lesson, reminder, or notification. It keeps the presentation visible so the guide can watch for spontaneous choice, repetition, concentration, accuracy, difficulty, and collaboration during later work cycles.

### Check Work

The guide may choose:

- **Next Work Cycle**, which keeps the item visible without adding a date;
- **Next School Day**; or
- a custom date.

A date is optional. Work entered in **Child's Follow-Up Work** remains visible in **Children Working** whether or not a date is chosen. After a review date exists, **Schedule Work Check-In** creates a check-in for each actual open work invitation linked to the selected child and presentation. The scheduled check-in also appears in the shared **Agenda**. If that work already has a pending check-in, the same check-in is reused or moved to the newly chosen date. It never fabricates a generic practice item. If a child has no linked work, the screen says so and leaves that child's work unchanged.

### Plan Support

The guide may plan to:

- re-present the lesson;
- give a follow-up presentation; or
- confer with the child.

Re-presentation and follow-up presentation are added to **On Deck** only after the guide chooses **Add Support Presentation to On Deck**. A conference remains in the follow-up queue until it is observed or recorded.

### Plan Next Presentation

The app may resolve the related or next lesson from the curriculum sequence, but it does not create or schedule it automatically. **Keep Watching** remains the planning default. The guide must choose an Inbox or Schedule action and then explicitly select **Apply Next Lesson Plan**.

The action choices apply to all open children by default. Choosing **Plan for [child]** in the **Each Child** menu focuses the same controls on only that child; **All Children** returns to group planning. This prevents a next lesson or support plan for one child from being applied to the rest of the group.

## Recording an observation

**Record Observation** opens a child-specific sheet for the exact presentation. The guide can select objective evidence:

- chose the work independently;
- returned to or repeated it;
- concentrated;
- used the material accurately;
- encountered difficulty; or
- sought help or collaborated.

The guide may also write a brief factual note. An outcome is optional; saving with no outcome keeps the child in **Following Presentations**.

The explicit outcomes are:

- **Continue Independent Work** — completes this follow-up without planning another action;
- **Offer Support or Re-present** — keeps the follow-up open as **Plan Support**;
- **Ready for a Related or Next Lesson** — keeps the follow-up open as **Plan Next Presentation**; and
- **No Further Follow-Up Needed** — completes this follow-up.

Support and next-presentation outcomes are transitions into planning, not permission for the app to fabricate or create a plan. The guide still reviews and applies the plan.

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
- `CDLessonPresentation` stores one child’s history and follow-up for that exact presentation. The `(presentationID, studentID)` pair is the stable identity.
- The child row stores the open action, optional review date, objective evidence, factual note, optional support plan, and explicit resolution.
- `CDNote` stores shared and child-specific reflection notes linked to the exact presentation.
- `CDWorkModel` is created only after the guide enters or selects a follow-up-work title and chooses **Add Work**. It stores the exact child, lesson, presentation, title, and work type shown in **Lessons & Work → Children Working**.
- `CDWorkCheckIn` is created only after the guide chooses **Check Work**, selects a date, and explicitly schedules a check-in for the already-entered open work.
- A support or next-lesson `CDLessonAssignment` is created only after the guide explicitly applies that plan.

There is no compulsory 1–5 understanding rating. The normal **Just Presented** flow captures only the recognizable work title and type; detailed work fields remain available in the work editor without interrupting the presentation workflow.

## Apple Intelligence boundaries

Apple Intelligence may:

- organize the guide’s spoken or typed reflection into shared and child-specific factual observations;
- retain the guide’s original words for comparison;
- present an editable proposal before anything is saved; and
- fall back to a deterministic, editable draft when the model is unavailable.

It may not:

- invent an observation or developmental conclusion;
- infer readiness silently;
- choose a follow-up action from the reflection;
- save records before the guide confirms the proposal; or
- create work, support, or a next lesson as a side effect of organizing text.

Reflection and planning are intentionally separate moments. Any follow-up suggestion produced while organizing a **What Happened?** reflection is removed before review; the persistent follow-up screen owns every planning choice.

Spoken observations in this classroom-data flow require on-device speech recognition. If the device cannot provide it, the app asks the guide to type instead of sending speech for server transcription.

## Persistence and migration rules

- Recording is immediate and uses a scoped Undo transaction.
- New **Just Presented** events open **Keep Watching** for every child in that presentation.
- Reopening an assignment with an open follow-up returns directly to **Follow This Presentation**.
- The optional reviewed reflection is a second, atomic save attempt: either its reviewed notes save together or that attempt is rolled back.
- Saving reviewed reflection retires the presentation-only Undo so dependent records can never remain attached to a reverted presentation.
- Failure recovery must not roll back unrelated edits already present in the shared Core Data context.
- Reopening **Just Presented** for an assignment already presented today reuses the exact presentation instead of creating a duplicate event.
- **Previously Presented** remains an undated historical fact; the app does not substitute today’s date when the original date is unknown.
- Existing and backfilled legacy presentation rows are not automatically added to **Following Presentations**. This prevents an upgrade from filling the guide’s queue with old work.
- Undated historical presentations are excluded from future **Upcoming** planning candidates.
- Sequence-track enrollment and the complete per-child follow-up state are restored exactly by Undo.
- Follow-up fields are included in backup, restore, and duplicate-row merging as one consistent bundle.

No follow-up selection forces a notification. **Keep Watching**, **Plan Support**, and **Plan Next Presentation** have no required date. **Check Work** may also remain undated.

## Manual validation checklist

### Shared setup

- Use a lesson assigned to two children so group and per-child behavior can both be checked.
- Confirm the assignment has not already been marked presented today.

### macOS

- Open the presentation in its normal Mac detail window and choose **Just Presented**.
- Confirm the presentation records immediately and **What Happened?** appears.
- Choose **Continue** or **Continue to Follow-Up** with no reflection. Confirm the reflection closes but the presentation window stays open and shows **Follow This Presentation**.
- Confirm both children show **Keep Watching** and appear in Today, **Lessons & Work → Needs Attention**, and each child’s **Current Learning** view.
- With **All Children** selected, add **Write and Symbolize Four Sentences**. Confirm one active work record appears for each child in **Children Working**, both records retain the exact presentation, and searching that view for **symbolize** finds them.
- Select one child and add **Biography on Stan Lee**. Confirm it appears only for that child and remains a separate item from the sentences work in **Children Working**.
- Re-enter the same title and type for that child. Confirm no duplicate is created. Close and reopen the presentation; confirm both existing titles appear under **Already Added** for the appropriate scope.
- Choose **Check Work → Next Work Cycle**. Confirm the presentation remains open with no date and no linked work check-in; the entered work remains in **Children Working**.
- Choose **Next School Day** or a custom date. Confirm the review date is shown. Confirm no work check-in exists until **Schedule Work Check-In** is selected.
- Schedule the check-in. Confirm every distinct open work item for the selected child receives a check-in on that date and no generic **Practice [lesson]** item is created.
- Set one child to **Plan Support** from the child menu while leaving the other at **Keep Watching**. Confirm their queue rows remain independent.
- Record objective evidence and a factual note for one child with no outcome. Close and reopen the presentation; confirm the note is saved and the child remains open.
- Record **Offer Support or Re-present**. Confirm it changes to **Plan Support** but creates no On Deck lesson until the explicit add button is selected.
- Record **Ready for a Related or Next Lesson**. Confirm it changes to **Plan Next Presentation** but creates or schedules nothing until **Apply Next Lesson Plan** is selected.
- Show the shared **Agenda** and confirm it contains scheduled presentations and work check-ins together. Resize and hide it, then confirm the selected **Lessons & Work** view remains unchanged.
- Use **Back to Lesson** and confirm the follow-up is preserved. Return to the follow-up and select **Close**; confirm only **Close** dismisses the detail window and that unresolved children route to **Needs Attention**, focused on this presentation.
- Resolve every child while leaving linked work. Select **Close** and confirm it routes to **Children Working**, focused on the linked work. Repeat with a presentation whose children are resolved and that has no linked work; confirm **Close** routes to **History**.

### iPhone

- Repeat **Just Presented** in the compact presentation detail and confirm dismissing the reflection reveals the follow-up inside the still-open presentation sheet.
- Check the reflection and follow-up layouts with Dynamic Type enlarged. Confirm all actions scroll into view and no action is hidden behind the keyboard or bottom controls.
- Close the presentation sheet and confirm the app opens **Lessons & Work → Needs Attention**, focused on the presentation. Open **Today** and confirm **Following Presentations** also shows the new item; tap it and confirm it returns to the exact presentation.
- If more than three items are open, confirm Today shows three and **View All** opens **Lessons & Work → Needs Attention**.
- Use the **Lessons & Work** view menu to open **Upcoming**, **Children Working**, and **History**. Use the calendar button to swap the current view for the shared **Agenda**, then return without losing the selected view.
- Open each child’s **Current Learning** view and confirm only that child’s open row is shown.
- Resolve one child as **Continue Independent Work** or **No Further Follow-Up Needed**. Confirm the other child remains visible in all applicable queues.
- Resolve the final child. Confirm the presentation disappears from Today, **Needs Attention**, and Current Learning.

### Regression and upgrade checks

- Use **Undo Presentation** before saving reflection details. Confirm only the new presentation and its new follow-up rows are removed or restored; older history is unchanged.
- Save a reflection, then close and reopen the presentation. Confirm it reopens the persistent follow-up instead of creating a duplicate presentation.
- Leave every action at its default and confirm no notification, date, work, support assignment, or next lesson was created.
- Add no work, choose a dated **Check Work** follow-up, and confirm the app explains that actual work must be entered rather than creating a placeholder item.
- Open an existing data store that contains historical presentation rows. Confirm those legacy rows do not suddenly appear in **Following Presentations**.
- Export and restore a backup containing an open follow-up. Confirm its action, date, evidence, note, support choice, and resolution state survive the round trip.
