# Work Models Best Practices Guide

## Overview
This document provides best practices for working with the Work-related models in Maria's Notebook. It reflects improvements made through systematic refactoring to eliminate redundancy and confusion.

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
- `status: WorkStatus` - Lifecycle status (active, review, complete)
- `dueAt: Date?` - Due date (optional)
- `assignedAt: Date` - When assigned
- `completedAt: Date?` - When work was fully completed
- `completionOutcome: CompletionOutcome?` - How it went (mastered, needsMorePractice, etc.)

**Relationships:**
- `participants: [WorkParticipantEntity]` - Students assigned to this work
- `checkIns: [WorkCheckIn]` - Scheduled check-ins
- `steps: [CDWorkStep]` - For report-type work
- `unifiedNotes: [CDNote]` - Associated notes

**Best Practices:**
- Always set `kind` when creating new work
- Use `WorkRepository.createWork()` for consistent initialization
- Use `WorkCompletionService` for marking completions
- Set `dueAt` for time-sensitive work

### WorkKind Enum
Describes the type of work assignment.

**Values:**
- `.practiceLesson` - Practice a specific lesson/skill
- `.followUpAssignment` - Follow-up work after a lesson
- `.research` - Student research/project work
- `.report` - Multi-step report with defined steps

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
Describes the lifecycle status of work.

**Values:**
- `.active` - Work is currently in progress
- `.review` - Needs teacher review
- `.complete` - Fully completed

**UI Properties:**
- `color: Color` - Status color (blue, orange, green)
- `iconName: String` - SF Symbol icon

**When to Use:**
- Set to `.active` when work is assigned
- Move to `.review` when student submits for feedback
- Set to `.complete` when fully done

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
- Don't directly set `completedAt` - use WorkCompletionService instead
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
    scheduledDate: tomorrow
)
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
