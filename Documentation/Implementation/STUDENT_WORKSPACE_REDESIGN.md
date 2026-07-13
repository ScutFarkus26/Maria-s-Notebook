# Student Workspace Redesign

## Purpose

Make **Students** a calm workspace for a Montessori Guide: observe first, decide
second, and keep the day-to-day next action visible without removing the deeper
record-keeping tools already in Maria's Notebook.

This is a presentation and workflow redesign. It does not change the Student,
Note, Work, Lesson Assignment, Meeting, Document, Track, or Year Plan data
models.

## Information Architecture

Each student's record has four plain-language sections:

| Section | Purpose | Existing material that belongs here |
| --- | --- | --- |
| Overview | What matters now | identity, enrollment, current work, next lessons, attendance, recall status |
| Observe | Factual classroom observation | notes timeline, tags, developmental characteristics, reports, optional Guide Review |
| Learning | Current path and longer planning | tracks, projects, reports, curriculum history, year plan |
| Meetings | Individual conversation work | next meeting, current meeting session, meeting history |

Documents are a record-level command, not a peer section. Lesson Recall remains
a class-wide review queue; a student's overview may link to it but does not
duplicate the queue.

## Platform Layout

### macOS

Use a three-column `NavigationSplitView` when the window has room:

1. **Collections** — All Students, Here Today, level filters, and Withdrawn.
2. **Roster** — remembered Cards or sortable Table view.
3. **Student record** — the selected child's workspace.

The main window is for fast browsing. Separate windows are for sustained work:

- Student record
- Presentation or work record
- Active meeting
- Long observation edit
- Student report
- Student documents

Those windows use a value-based `WindowGroup`, so reopening the same record
brings its existing window forward instead of creating duplicates. Add/import,
pickers, short quick capture, and confirmations remain sheets or inline actions.

### iPad and iPhone

iPad retains the roster-and-detail split view. iPhone remains a straightforward
list-to-detail flow. A compact student record uses one standard section menu
instead of a horizontally scrolling strip of custom tabs.

## AI and Montessori Guardrails

- Observation is always available without AI.
- AI work is explicitly started by the guide. It never auto-generates merely
  because a record or history row appeared.
- “Guide Review” makes it clear that an output is a draft, shows its source
  range, and requires human review before a parent-facing export.
- Existing Apple Intelligence routing remains on-device first, then Apple
  Private Cloud Compute when available. A third-party model remains an explicit
  opt-in choice; there is no hidden fallback.

## Preference Migration

The old stored detail values map without losing context:

| Previous tab | New section |
| --- | --- |
| Overview | Overview |
| Notes, Traits | Observe |
| Progress, History, Year Plan | Learning |
| Meetings | Meetings |
| Files | Overview, with Documents opened on demand |

The remembered roster Cards/Table selection and manual classroom order remain
unchanged.

## Completion Checks

### Completed in this change

- Built the macOS target with Xcode 27 and the macOS 27 SDK.
- Built and ran the iOS test suite on the iPhone 17 (iOS 27) simulator.
- Kept the existing value-based record, work, presentation, report, note, and
  meeting windows; added the same identity-based behavior for student documents.
- Added visible labels to the new student-section picker and Mac toolbar
  commands, so they remain clear with VoiceOver and keyboard navigation.

### Before release

- Manually test Mac three-column, two-column, and narrow-window states; iPad
  mini; and iPhone compact navigation with real classroom data.
- Test VoiceOver, Dynamic Type, Reduce Motion, contrast, and all destructive
  actions.
- Confirm that a child, report, note, meeting, work item, and document reopen
  their existing Mac window by identity.
- Update the user manual whenever a visible label or route changes.
