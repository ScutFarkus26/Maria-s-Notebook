# Work Models Best Practices Guide

## Overview
This document provides best practices for working with the Work-related models in Cosmic Daybook. It reflects improvements made through systematic refactoring to eliminate redundancy and confusion.

## Quick Reference

### ✅ Use These (Recommended)

**For Work Completion:**
```swift
// Create completion with history
try WorkCompletionService.markCompleted(workID: work.id, studentID: student.id, in: context)

// Check completion (with context)
let isComplete = try work.isCompleted(by: studentID, in: context)

// Get completion history
let records = try work.completionRecords(for: studentID, in: context)
```

**For Work Type:**
```swift
// Use WorkKind enum (unified system)
let work = CDWorkModel(kind: .practiceLesson, ...)
work.kind = .followUpAssignment

// Access colors and icons
let color = work.kind?.color
let icon = work.kind?.iconName
```

**For Work Status:**
```swift
// Set status directly
work.status = .active
work.status = .review
work.status = .complete

// Check status
if work.isActive { ... }
if work.isComplete { ... }
```

### ❌ Removed (No Longer Available)

These old APIs have been removed. Use the recommended patterns above instead:

```swift
// REMOVED: work.markStudent(studentID, completedAt: Date())
// Use: WorkCompletionService.markCompleted() instead

// LEGACY: work.workType (still available for migration compatibility)
// Prefer: work.kind instead
```

### ✅ Still Valid (No Context Needed)

```swift
// Quick boolean check (reads from participant.completedAt)
if work.isStudentCompleted(studentID) {
    // ...
}
```

---

## Model Descriptions

### CDWorkModel
The core work assignment model.

**Key Fields:**
- `id: UUID` - Unique identifier
- `title: String` - Work title/description
- `kind: WorkKind?` - Type of work (practice, followUp, research, report)
- `status: WorkStatus` - The row's one verdict (active, review, mastered, keepPracticing, incomplete, done)
- `dueAt: Date?` - A due date the guide set (optional), and nothing else. Since 2026-11-21 scheduling a check no longer copies its day here; the next check is the earliest scheduled check-in (`WorkCheckInService.nextCheckDay`)
- `assignmentID: String?` - The assignment this row is a copy of (schema 25). Every child's copy of work given to a group carries the same id; a row given to one child carries its own. Nil on older rows until `WorkAssignmentFill` stamps it, at launch and after a restore
- `isSharedRow: Bool` - The row is one its children share (a project's work), not one child's copy (schema 25)
- `assignedAt: Date` - When assigned
- `completedAt: Date?` - When work was fully completed
- `completionOutcomeRaw: String?` - **Legacy.** Folded into `status` by `WorkStatusMigration` (launch repair + backup importer); nothing else reads it

**Relationships:**
- `participants: [WorkParticipantEntity]` - Students assigned to this work
- `checkIns: [WorkCheckIn]` - Scheduled check-ins
- `steps: [CDWorkStep]` - For report-type work
- `unifiedNotes: [CDNote]` - Associated notes

**Best Practices:**
- Always set `kind` when creating new work
- Give work through `WorkAssignmentService.create`, for one child or several: it makes one row per child through `WorkRepository.createWork`, gives a group's copies one `assignmentID`, makes the first check-in through `WorkCheckInService.addCheckIn` (a closed day moves to the next school day), and links the copies to each other once. Quick New Work and Claude's `assign_work` both use it
- Change `status` only through `WorkLogService.log` — it stamps `completedAt`, writes the `CDWorkCompletionRecord`, settles the row's check-ins (today's → completed, later ones on a closed row → skipped, dates kept) and files the note; every in-app control and `update_work` go through it
- Set `dueAt` only for a real due date. Put work on a day with a check-in (`WorkCheckInService.addCheckIn`, or `scheduleCheck` to move the earliest one), never by writing `dueAt`

### WorkKind Enum
Describes the type of work assignment.

**Values:**
- `.practiceLesson` - Practice a specific lesson/skill
- `.followUpAssignment` - Follow-up work after a lesson
- `.research` - Student research/project work
- `.report` - Multi-step report with defined steps

**Default:** `createWork` with no kind makes Practice when the row can follow a presentation of the lesson naming the child (given ones first, else a plan), and Follow-Up when there is none. It reads the presentation it resolves, not the argument, so work made without one is still Practice (2026-11-21).

**UI Properties:**
- `color: Color` - Standard color for this kind
- `iconName: String` - SF Symbol icon name
- `displayName: String` - User-facing label

**Example:**
```swift
let kind = WorkKind.practiceLesson
let color = kind.color // .purple
let icon = kind.iconName // "pencil.circle"
```

### WorkStatus Enum
The one verdict a work row carries, per child. Until 2026-09-15 a row had a
lifecycle status *and* a completion outcome that were only ever set together.

**Open (`isOpen`):** the status alone, on the row as in every fetch (`CDWorkModel.isOpen` is `status.isOpen` since 2026-11-21; it used to read a shared row as closed once every child was stamped done).
- `.active` - "Working"
- `.review` - "Needs Review": the guide has to look before it moves on

**Closed (`isClosed`):**
- `.mastered` - the practice evidence `mastery_candidates` weights 3
- `.keepPracticing` - this invitation is done, the child is not there yet
- `.incomplete` - set aside unfinished
- `.done` - raw value `"complete"`; legacy closed-with-no-verdict, never offered in a picker

**Helpers:** `pickable` (the five a picker offers), `openCases` / `closedCases`,
`openRawValues` / `closedRawValues`, and `openPredicate` / `closedPredicate`
(`statusRaw IN %@`) — the one spelling of "open work" for a fetch. Never
compare `statusRaw` to a string literal.

**Migration:** `WorkStatusMigration.merged(statusRaw:outcomeRaw:)` is the
single table: `complete` + `mastered` → `mastered`, + `needsMorePractice` →
`keepPracticing`, + `incomplete` → `incomplete`, anything else → `complete`
(Done). `DataCleanupService.mergeWorkCompletionOutcomes` runs it every launch
(not flag-gated — CloudKit can deliver an old-shape row late) and
`BackupEntityImporter.importWorkModels` runs it on restore.

### Save on the work page (bug hunt 2026-11-03)

Save writes only the header fields she changed in this sitting. The page remembers whether she touched the status pill or the title (`WorkDetailViewModel`); Save logs a status through `WorkLogService`, or writes a title to every copy, only for a touched field. An untouched field is reloaded when the stored row changes underneath (`refreshHeaderFromStore`), so a Mastered set from the Checklist while the page was open survives a Save that only adds a note. The note, check-in and step trash buttons ask first; a check-in Delete goes through `WorkCheckInService.unschedule`, which skips the check-in and keeps its note. Unlock Next Lesson saves at once (it is an action, not an edit of the page).

### WorkLogService
Logging a work check is the only way a row's status changes.

```swift
let receipt = try WorkLogService.log(
    [.init(work: row, status: .mastered, note: "Matched every card")],
    on: day, context: context, saveCoordinator: saveCoordinator
)
// receipt.token → WorkLogService.undo(token, context:, saveCoordinator:)
```

An entry with `status: nil` means "seen, unchanged": the day's check-in is
still marked completed. `WorkLogTargets.resolve(work:students:in:)` turns a
gesture into rows — everyone on a fan-out group, or the copies a set of
children own; a `.shared` row refuses a subset rather than being split.
Since 2026-11-21 "everyone" leaves out the copy of a child who has left the
class (`CDStudent.hasLeft(by:)`): it is her record and stays as she left it.

**The check happened (2026-11-21).** Done on Today, Done on the work page and
Claude's `complete_check_in_on` pass the check-in as `checked:` with a
"seen, unchanged" entry. It is dated the day it was checked (never later than
today), every earlier check-in still waiting is settled with it, and Undo puts
it back. The work page and Claude used to mark that one check-in alone, so
Monday's missed check stayed overdue.

**One child's part of a shared row (2026-11-21).** `WorkLogService.finishPart(of:for:)`
stamps her participant row and writes her completion; the row stays open for
the others. When hers was the last part open, the row closes through `log`
(as Finished unless a closing status is given), so its check-ins and linked
todos settle like any other close. Claude's `completed_by` and a mastery mark
on a shared row use it. For a row that is hers alone, log a closing status
instead.

**Linked copies (2026-10-10, revised the same day; `assignmentID` since
2026-11-21).** A row that carries its `assignmentID` is matched by it: its
copies are the rows with the same id, whatever their titles, days or
presentations have become. The rule below is now the fallback for a row not
filled yet, and what `WorkAssignmentFill` writes down. `WorkGrouping` treats
two such rows as copies of one assignment only when:
- their owners name each other,
- they match on lesson and kind,
- they were created within 60 seconds of each other, and
- neither is a project-session row (those are shared rows by design).

The presentation and the title don't count when both rows have a
`createdAt`. `createWork` links each copy to *that child's* latest
presentation of the lesson, so children who had the lesson on different days
get copies with different presentations; and a copy renamed before renames
carried to the others has a different title. Both used to split the group,
leaving each copy reading as one shared row for every child on it.

One fan-out never gives a child two copies. When the rows linked this way
include two owned by one child, two assignments of the lesson were made in
the same minute; then each child's copy is her row that best matches (the
same title, then the same presentation, then the closest creation time), kept
only when the match holds both ways. A pair with no `createdAt` keeps the old
rule: the same title and the same presentation.

The work editor carries a new title or kind to every linked copy. Status
logs, removal, delete clean-up, the grid menu and MCP check-ins all go
through this rule.

**Whose work it is (2026-11-21).** `WorkOwnership` is the one rule. A row is
a child's when she owns it (her own work, or her copy of work given to a
group), or when she is named on it and owns no copy of its assignment (a row
its children share, or a classmate's row she is on with none of her own). A
classmate's copy that names her is not hers while she has her own. It
replaced five rules (`WorkGrouping.visibleWork`, `WorkVisibility`, the Class
Grid's `ownWork`, readiness's `gatingWork` and `workInvolvesStudent`) and the
owner-only reads in Today and the meetings. Use `WorkOwnership.work(of:among:in:)`
for a list, or a `WorkOwnership.Reader` over rows in hand.

**How long work has gone quiet (2026-11-21).** `WorkNeglect` is the one clock:
school days since the latest meaningful touch, the latest of a log
(`lastTouchedAt`), a completed check-in on or before today, a note, the
completion, and the day a rest ended; with none of these, the day it was
assigned. Triage, Today's Gone quiet, the card's age bar, the Checklist's dot
and the meeting's stuck list all read it, so work set aside for a month no
longer wakes up as a month untouched.

**Practice (2026-11-21).** A practice is a completed check-in that has
minutes or the practice purpose (`CDWorkCheckIn.isPractice`, and
`practicePredicate` for a fetch); a practice still on the calendar, or skipped
when its work closed, isn't one. Three Years, the Checklist and the timeline
hand the ladder the same input (`LadderInput`), and a Practicing or Ready for
Assessment state the guide stored by hand is a floor the mark never reads
below.

**Undo from a meeting.** A meeting card's choice (Keep Working or Keep
Practicing, Finished, Mastered, Re-present) sets the work's status at once;
Ready for Next is a switch beside it that sets no status (2026-10-30). Since
2026-11-21 Re-present and Ready for Next also plan at the tap, not when the
meeting is filed: Re-present plans the lesson again as a second pass, and
Ready for Next confirms her on the lesson and puts the next one On Deck. The
draft keeps a receipt of what the tap made and changed (`MeetingTapPlan`), so
the card, Rest or Clear can take it back after a relaunch; taking back
refuses once anything has moved since. The meeting keeps each
close's `UndoToken` with its stored draft (`MeetingCloseToken`, object IDs as
URIs), so Rest or another choice can undo it after a relaunch, and Clear can
undo a Re-present. Before undoing, it checks the work is still as
the meeting left it, because `undo` itself only checks the rows still exist.

### WorkCompletionRecord
Historical record of work completion events.

**Key Fields:**
- `workID: String` - Reference to CDWorkModel
- `studentID: String` - Reference to CDStudent
- `completedAt: Date` - When completed
- `note: String` - Completion notes

**Purpose:**
- Preserves full history (multiple completions possible)
- Used for progress tracking and analytics
- Single source of truth for completion data

**Access via:**
```swift
// Get all completion records for a work/student pair
let records = try WorkCompletionService.records(for: workID, studentID: studentID, in: context)

// Get latest completion
let latest = try WorkCompletionService.latest(for: workID, studentID: studentID, in: context)
```

### WorkParticipantEntity
Links students to work assignments.

**Key Fields:**
- `studentID: String` - Which student
- `completedAt: Date?` - Legacy completion date (kept in sync with WorkCompletionRecord)
- `work: CDWorkModel?` - Back-reference to work

**Best Practices:**
- Don't directly set `completedAt` - `WorkLogService` sets it when a row closes, and `WorkLogService.finishPart` for one child's part of a shared row
- Used primarily for determining which students are assigned to work
- The completion date is automatically synced from WorkCompletionRecord

### WorkCheckIn
Scheduled check-in for work progress tracking.

**Key Fields:**
- `workID: String` - Reference to CDWorkModel
- `date: Date` - Check-in date
- `status: WorkCheckInStatus` - scheduled, completed, or skipped
- `purpose: String` - Why this check-in exists
- `note: String` - Check-in notes

**Lifecycle:**
```swift
// Create scheduled check-in
let checkIn = work.scheduleCheckIn(on: date, purpose: "Progress check", in: context)

// Mark completed
checkIn.markCompleted(note: "Good progress", in: context)

// Reschedule
checkIn.reschedule(to: newDate, in: context)

// Skip
checkIn.skip(note: "Student absent", in: context)
```

### CDWorkStep
Individual steps for report-type work.

**Key Fields:**
- `orderIndex: Int` - Step ordering
- `title: String` - Step title
- `instructions: String` - What to do
- `completedAt: Date?` - When step was completed

**Best Practices:**
- Only use for `kind == .report` work
- Keep steps focused and actionable
- Use `work.orderedSteps` to get sorted steps
- Check `work.allStepsCompleted` for overall progress

---

## Common Patterns

### Creating New Work

```swift
let repository = WorkRepository(context: context)

try repository.createWork(
    studentID: student.id,
    lessonID: lesson.id,
    title: "Practice multiplication",
    kind: .practiceLesson,
    scheduledDate: dueDay // the due date the guide set, never a check day
)
```

To give work to one child or a group with a first check-in, use the one path
Quick New Work and `assign_work` use (it doesn't save; the caller does):

```swift
let assigned = try WorkAssignmentService(context: context).create(.init(
    lessonID: lesson.id,
    studentIDs: [maya.id, leo.id],
    title: "Practice multiplication",
    kind: nil, // Practice when it follows a presentation of the lesson
    dueDate: nil,
    checkIn: .init(day: tomorrow, purpose: "Progress check")
))
// assigned.works: one row per child, sharing one assignmentID
// assigned.checkInAskedFor: set when the day wasn't a school day and moved
```

### Marking Work Complete

```swift
// Single student
try WorkCompletionService.markCompleted(
    workID: work.id,
    studentID: student.id,
    note: "Great job!",
    in: context
)

// Multiple students (bulk)
try work.markCompleted(
    for: [student1.id, student2.id],
    note: "Completed together",
    in: context
)
```

### Checking Completion Status

```swift
// Quick check (no context needed)
if work.isStudentCompleted(student.id) {
    print("Already done!")
}

// Detailed check (with history)
if let latest = try? work.latestCompletion(for: student.id, in: context) {
    print("Completed on \(latest.completedAt)")
    print("Note: \(latest.note)")
}
```

### Scheduling Check-Ins

```swift
// Schedule a future check-in with status tracking
let checkIn = work.scheduleCheckIn(
    on: nextWeek,
    purpose: "Review progress on multiplication",
    in: context
)
```

### Working with Report Steps

```swift
// Create a report-type work
let work = CDWorkModel(context: context)
work.kindRaw = WorkKind.report.rawValue

// Add steps
let step1 = CDWorkStep(context: context)
step1.title = "Research"
step1.instructions = "Find 3 sources"
step1.work = work

let step2 = CDWorkStep(context: context)
step2.title = "Outline"
step2.instructions = "Create outline"
step2.work = work

// Check progress
let (completed, total) = work.stepProgress
print("\(completed) of \(total) steps complete")

// Mark step complete
try WorkStepService.markCompleted(step: step1, in: context)
```

---

## Current Data State

All historical data migrations are complete. The current state:

- **Completion system**: `WorkCompletionRecord` is the primary source of truth. `WorkParticipantEntity.completedAt` is kept in sync for backwards compatibility.
- **Work types**: `WorkKind` is the canonical type system. Legacy `workType` property reads from `kind`.
- **Check-ins**: Single unified `WorkCheckIn` system with status tracking (scheduled, completed, skipped). Legacy check-in model has been fully removed.
- **Persistence**: Core Data with `NSPersistentCloudKitContainer` (two-store architecture: private + shared).

---

## Performance Tips

### Indexed Queries
CDWorkModel has compound indexes for common queries:

```swift
// Efficiently fetch active work for a student
let fetchRequest: NSFetchRequest<CDWorkModel> = CDWorkModel.fetchRequest()
fetchRequest.predicate = NSPredicate(format: "studentID == %@ AND statusRaw == %@", studentIDString, "active")
let results = try context.fetch(fetchRequest)
// Uses index: [studentID, statusRaw]
```

### Batch Operations
For bulk completion, use the batch method:

```swift
// ✅ Efficient: Single transaction
try work.markCompleted(for: studentIDs, in: context)

// ❌ Inefficient: Multiple transactions
for id in studentIDs {
    try work.markCompleted(for: [id], in: context)
}
```

### Prefetching Relationships
For UI displaying work with participants:

```swift
let fetchRequest: NSFetchRequest<CDWorkModel> = CDWorkModel.fetchRequest()
fetchRequest.relationshipKeyPathsForPrefetching = ["participants", "checkIns"]
let works = try context.fetch(fetchRequest)
// Participants and checkIns are already loaded
```

---

## Testing Guidelines

### Unit Tests
```swift
@Test("Work creation sets correct defaults")
func workCreation() {
    let work = CDWorkModel(kind: .practiceLesson)
    #expect(work.status == .active)
    #expect(work.kind == .practiceLesson)
    #expect(work.isActive == true)
}

@Test("Completion creates record and updates participant")
func completion() throws {
    let work = CDWorkModel(kind: .practiceLesson)
    let student = CDStudent(context: context)
    context.insert(work)
    
    // Mark complete
    try WorkCompletionService.markCompleted(
        workID: work.id,
        studentID: student.id,
        in: context
    )
    
    // Verify both systems updated
    #expect(work.isStudentCompleted(student.id))
    let records = try work.completionRecords(for: student.id, in: context)
    #expect(records.count == 1)
}
```

### Integration Tests
```swift
@Test("Work completion persists across context saves")
func persistence() async throws {
    // Create and complete work
    let work = CDWorkModel(kind: .practiceLesson)
    context.insert(work)
    try WorkCompletionService.markCompleted(
        workID: work.id,
        studentID: student.id,
        in: context
    )
    try context.save()
    
    // Fetch in new context
    let newContext = coreDataStack.newBackgroundContext()
    let fetchRequest: NSFetchRequest<CDWorkModel> = CDWorkModel.fetchRequest()
    fetchRequest.predicate = NSPredicate(format: "id == %@", work.id as CVarArg)
    let fetched = try newContext.fetch(fetchRequest).first!
    
    // Verify completion persisted
    #expect(fetched.isStudentCompleted(student.id))
}
```

---

## Summary

**Key Takeaways:**
1. Use `WorkKind` for work types (not `WorkType`)
2. Use `WorkCompletionService` for completions (not `markStudent`)
3. Both completion systems stay in sync automatically
4. WorkCheckIn offers richer tracking than WorkPlanItem
5. All entity classes use the `CD` prefix (e.g., `CDWorkModel`, `CDStudent`)
6. Use `NSFetchRequest` + `NSPredicate` for queries (not `FetchDescriptor` / `#Predicate`)

**When in Doubt:**
- Check deprecation warnings - they point to the right API
- Use the service layers (WorkCompletionService, WorkStepService, etc.)
- Prefer computed properties over direct field access
- Use Core Data patterns (`NSFetchRequest`, `NSManagedObjectContext`) not SwiftData

---

*Last Updated: 2026-04-01 (Updated for Core Data migration)*
