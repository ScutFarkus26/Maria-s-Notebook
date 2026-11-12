# Lesson → Presentation → Work Integration

## Overview

This document describes the cohesive integration between Lessons, Presentations, and Work in Cosmic Daybook. The integration creates a complete journey from curriculum content through teaching sessions to student practice and follow-up work.

## Architecture

### Data Model Relationships

```
Lesson
  ├── LessonAssignment (Presentation)
  │   ├── WorkModel (via presentationID)
  │   │   └── PracticeSession (via workItemIDs)
  │   └── Students (via studentIDs)
  └── Notes
```

### Key Connections

1. **Lesson → Presentation**: One lesson can have multiple presentations to different student groups
2. **Presentation → Work**: Each presentation can spawn multiple work items (one per student)
3. **Work → Practice Sessions**: Multiple work items can be practiced together in group sessions
4. **Bidirectional References**: Work items store `presentationID` and `lessonID` for easy traversal

## Implementation Components

### 1. Model Extensions (`Cosmic Daybook/Models/ModelExtensions.swift`)

Provides convenience methods for traversing relationships:

```swift
// CDWorkModel extensions
work.fetchPresentation(from: context) -> CDLessonPresentation?
work.fetchLesson(from: context) -> CDLesson?
work.fetchStudent(from: context) -> CDStudent?
work.fetchPracticeSessions(from: context) -> [CDPracticeSession]

// CDLessonPresentation extensions
presentation.fetchRelatedWork(from: context) -> [CDWorkModel]
presentation.fetchStudents(from: context) -> [CDStudent]
presentation.fetchRelatedPracticeSessions(from: context) -> [CDPracticeSession]
presentation.workCompletionStats(from: context) -> (completed: Int, total: Int)

// CDLesson extensions
lesson.fetchAllPresentations(from: context) -> [CDLessonAssignment]
lesson.fetchAllWork(from: context) -> [CDWorkModel]
lesson.fetchAllPracticeSessions(from: context) -> [CDPracticeSession]
lesson.getLessonStats(from: context) -> LessonStats
```

### 2. Enhanced WorkDetailView

**Location**: `Cosmic Daybook/Work/Detail/WorkDetailView.swift`

**New Features**:
- Displays presentation context section showing:
  - When the lesson was presented
  - Presentation flags (needsPractice, needsAnotherPresentation, followUpWork)
  - Other students who received the same presentation
  - Presentation notes

**Added State**:
```swift
@State private var relatedPresentation: CDLessonPresentation? = nil
```

**Benefits**:
- Teachers can see the full context of why work was assigned
- Easy access to presentation notes while reviewing student work
- Visibility into group dynamics (who else is working on this)

### 3. Presentation Detail with Work Summary

**Location**: `Cosmic Daybook/Presentations/Assignments/LessonAssignmentDetailSheet.swift`

**New Features**:
- Work summary section showing:
  - All work items spawned from this presentation
  - Work completion statistics (X/Y complete)
  - Practice sessions involving this presentation's work
  - Visual status indicators for each work item

**Benefits**:
- Complete visibility into outcomes of a presentation
- Track which students have completed their follow-up work
- See practice session history related to the presentation

### 4. Enhanced GroupPracticeSheet

**Location**: `Cosmic Daybook/Work/GroupPracticeSheet.swift`

**New Features**:
- Presentation & lesson context section showing:
  - The lesson being practiced
  - Subject and group information
  - When the lesson was presented
  - Presentation status (presented vs scheduled)

**Added State**:
```swift
@State private var relatedPresentation: CDLessonPresentation? = nil
@State private var relatedLesson: CDLesson? = nil
```

**Benefits**:
- Teachers see the complete educational context during practice
- Links practice sessions back to original presentations
- Better understanding of the lesson's instructional history

### 5. LessonJourneyTimeline Component

**Location**: `Cosmic Daybook/Lessons/Detail/LessonJourneyTimeline.swift`

**Purpose**: Visual timeline showing the complete journey from lesson to outcomes

**Features**:
- Horizontal scrollable timeline
- Each presentation shown as a node
- Connecting lines to related work items
- Practice sessions linked to work
- Visual indicators for completion status

**Usage**:
```swift
LessonJourneyTimeline(lesson: lesson, context: context)
    .frame(height: 350)
```

**Benefits**:
- At-a-glance view of lesson usage over time
- Understand the complete flow from teaching to practice
- Identify patterns in lesson effectiveness

### 6. LessonProgressView

**Location**: `Cosmic Daybook/Lessons/LessonProgressView.swift`

**Purpose**: Unified view showing complete progress and usage for a lesson

**Features**:
- **Overview Tab**: Statistics cards, journey timeline, insights
  - Total presentations (scheduled vs presented)
  - Work completion rate
  - Active work count
  - Practice session count
  - Smart insights based on data

- **Presentations Tab**: List of all presentations
  - Status indicators (draft/scheduled/presented)
  - Student count
  - Related work summary

- **Work Tab**: All work items for this lesson
  - Status indicators
  - Student assignments
  - Work type (practice, follow-up, etc.)

- **Practice Tab**: All practice sessions
  - Solo vs group indicators
  - Duration tracking
  - Student participants

**Stats Provided**:
```swift
struct LessonStats {
    let totalPresentations: Int
    let presentedCount: Int
    let scheduledCount: Int
    let totalWorkItems: Int
    let completedWorkItems: Int
    let activeWorkItems: Int
    let totalPracticeSessions: Int
    let lastPresentedDate: Date?
    var workCompletionRate: Double
}
```

**Usage**:
```swift
LessonProgressView(lesson: lesson) {
    // onDone callback
}
```

### 7. FollowUpWorkService

**Location**: `Cosmic Daybook/Services/FollowUpWorkService.swift`

**Purpose**: Automate creation of follow-up work from presentation flags

**Key Functions**:

```swift
// Generate work from presentation flags
FollowUpWorkService.generateWorkFromPresentation(
    presentation,
    context: context
) -> [CDWorkModel]

// Analyze what follow-up is needed
FollowUpWorkService.analyzePresentation(presentation) -> PresentationFollowUp

// Find presentations needing follow-up
FollowUpWorkService.findPresentationsNeedingFollowUp(
    in: context
) -> [CDLessonPresentation]

// Get suggestions without creating work
FollowUpWorkService.suggestWork(
    for: presentation,
    in: context
) -> [WorkSuggestion]
```

**Convenience Extensions**:
```swift
// On CDLessonPresentation
presentation.generateFollowUpWork(in: context) -> [CDWorkModel]
presentation.analyzeFollowUp() -> PresentationFollowUp
presentation.getSuggestedWork(from: context) -> [WorkSuggestion]
```

**Follow-Up Actions**:
- `createPracticeWork`: When `needsPractice` flag is set
- `createFollowUpWork`: When `followUpWork` description is provided
- `scheduleRepresentation`: When `needsAnotherPresentation` flag is set

**Benefits**:
- Automates tedious work creation from presentations
- Ensures follow-up actions aren't forgotten
- Provides suggestions before committing to database
- Priority system helps teachers focus on urgent items

## Usage Examples

### Example 1: View Work Context

When viewing a work item, teachers now see:
1. The lesson being practiced
2. When it was presented
3. Presentation notes and flags
4. Other students working on the same material

### Example 2: Track Presentation Outcomes

When viewing a presentation, teachers see:
1. All work items spawned from it
2. Completion status per student
3. Practice sessions involving this work
4. Overall progress metrics

### Example 3: Lesson Journey

When viewing a lesson, teachers can:
1. See all presentations over time
2. Track work completion rates
3. View practice session history
4. Get insights on lesson effectiveness

### Example 4: Automated Follow-Up

After presenting a lesson:
1. Mark `needsPractice` flag in presentation
2. Use `presentation.generateFollowUpWork(in: context)`
3. Practice work items automatically created for each student
4. Work items linked back to presentation via `presentationID`

## Data Flow

```
Teacher presents lesson
  ↓
Presentation created with flags
  ↓
FollowUpWorkService generates work items
  ↓
Work items assigned to students
  ↓
Students practice together (PracticeSession)
  ↓
Work completed
  ↓
Stats visible in LessonProgressView
```

## Benefits

1. **Complete Visibility**: See the entire journey from lesson to outcomes
2. **Context Preservation**: Work items remember their presentation context
3. **Automated Workflows**: Follow-up work generation from presentation flags
4. **Group Practice**: Track collaborative learning sessions
5. **Progress Tracking**: Comprehensive statistics and insights
6. **Educational Continuity**: Clear links between teaching and practice

## Future Enhancements

Potential additions to consider:

1. **Work Templates**: Pre-defined work templates for common lesson types
2. **Outcome Analysis**: ML-based insights on lesson effectiveness
3. **Student Grouping**: Intelligent suggestions for practice partners
4. **Time Tracking**: Detailed analytics on time-to-completion
5. **Parent Visibility**: Share lesson journey with parents
6. **Curriculum Mapping**: Link lessons to standards and objectives

## Technical Notes

- All relationships use CloudKit-compatible string IDs (UUID.uuidString)
- Query helpers use `@MainActor` for UI safety
- Extension methods provide clean API for relationship traversal
- Components are reusable across different views
- Service layer separates business logic from UI

## Testing Recommendations

1. **Unit Tests**: Test relationship traversal methods
2. **Integration Tests**: Test work generation from presentations
3. **UI Tests**: Test timeline and progress view rendering
4. **Performance Tests**: Test query performance with large datasets

## Persistence Layer

This integration works with the Core Data persistence layer (`NSPersistentCloudKitContainer`). All entity classes use the `CD` prefix (e.g., `CDWorkModel`, `CDLessonPresentation`, `CDLesson`). Key fields used by this integration:
- `CDWorkModel.presentationID`
- `CDWorkModel.lessonID`
- `CDLessonPresentation.needsPractice`, `needsAnotherPresentation`, `followUpWork`

## Checklist marks, readiness and the year plan (bug hunt 2026-11-03)

Fixed in the 2026-11-03 bug hunt (`../Reviews/Bug hunt 2026-11-03.md`). These are rules: follow them.

**Checklist marks do what the presentation sheet's do.**
- A mark that records a presentation (a cell or a batch) releases that child from the year-plan plan she was on, through `YearPlanReleaseService.releaseRedundantPlans`, as `LifecycleService` does. On a shared undated record only the child marked is released.
- Mastered, Practicing or Reviewing on a lesson with no presentation attaches an undated presentation (the Previously Presented path), never one dated today. Mastered marks the latest history row by date given.
- Unmark Presented, Remove Plan and Remove in Merge Groups ask first, name the notes, and keep them as the child's, filed under the lesson. Mastery marks stay. The cell's Clear, the history's Delete and Merge Groups share this rule; the note-keeping lives in `ChecklistCellRecords` and in `Presentations/Workflow/PresentationDeletion.swift`, and the two stamp and normalize notes alike.
- A batch mark only adds; it never clears a mark.

**One readiness rule across both engines.** The blocking engine (Presentations) and the ready engine (the Checklist, Ready and Brewing) read the same inputs:
- A mastery mark counts as confirmation, and with no presentation on record it also counts as practice done.
- A lesson's own "Requires Confirmation" is honored by both; with it off, a group card offers no one for confirming. The ready engine does not honor "Requires Practice": open work never holds a child back.
- Brewing and "N of M ready" count enrolled, visible children only.
- `ReadinessAgreementFix1103Tests` runs the same records through both engines and the ready list; change one engine and run it.

**The year plan draws each lesson once.**
- An entry follows its presentation: it is drawn at the day the presentation was given or is planned, and moves when the presentation moves (a drag, an absence, MCP `reschedule_presentation`). A lesson she was given without promotion is drawn once, at that day.
- Entries are numbered by the lesson's own order in its sequence (`orderInSequence`), not by their place in an Add Sequence preview.
- `YearPlanEntryRepair` runs whenever a child's year plan loads. It fixes numbering, the day of a promoted entry, and unpromoted entries, writing only values that differ (a second pass changes nothing), and it never saves over another screen's unsaved edit.
- Add Sequence skips lessons a presentation or a mastery mark already satisfies (`YearPlanSatisfaction`). Readjust asks first ("Move 14 lessons in 3 sequences?"), says so when there is nothing to move, and has no Undo.

## Scheduled lessons: halves, order and set times (2026-11-11)

A scheduled lesson (`CDLessonAssignment.scheduledFor`) sits in a half of a day and either takes an ordering slot in that half or has a start time Danny set (the time chip on a Scheduled card, the Time row on the lesson's sheet, or MCP's `time:`). Both are written into the one date; the table that tells them apart is in `DATA_MODELS.md` › LessonAssignment, and the code is `Presentations/Planning/DayHalfPlanner.swift`. These are rules: follow them.

- A set time stays with the lesson until Danny changes or removes it: a drag to another day, Move All Forward, Today's Tomorrow, the absent-children move, Balance AM/PM and MCP `reschedule_presentation` without `time:` all keep it.
- Inside each half, timed lessons come first in clock order and can't be reordered by hand; the rest follow in the order Danny dragged them, under an "Any time" divider on the Scheduled cards. Today's Lessons list leads with timed lessons the same way, whatever hand order was saved.
- Set and remove through `CDLessonAssignment.setTime/removeTime` (or the pure `DayHalfPlanner` functions for an unsaved `Date`, as the lesson's sheet does in `ScheduledDateEdits`). The picker hands back an hour and a minute, never a date.
- Every device must run a build with these rules: an older build reads a lesson set for exactly 9:00 or 2:00 as an ordinary slot, and a drag or balance there erases that time.

### Clashes with a set time (2026-11-11)

A set time can clash two ways. Both only warn; neither blocks a save, a drag or an MCP write.

- **Another lesson at the same time:** two timed lessons on a day share a start (the chip's amber look, `DayClashes` in `WeekDayColumn+Balance.swift`).
- **A child is with another teacher:** a lesson's child is in a co-teacher's group then (plan "Co-teacher times when scheduling"). Lessons have no length, so a lesson is taken as `LessonLength.assumedMinutes` (30) long (`Schedules/Model/TimetableValues.swift`). A lesson starting at minute `s` clashes with a group `[b, e)` when `s < e` and `s + 30 > b`, so a group that ends as the lesson starts, or starts as it ends, isn't a clash; a group with no length never is.
  - Who counts as away: a child named in a block of a person lane other than the guide's own, on the day as the Schedules page resolves it (`AwayTimes.day(from:guideLaneID:)` over `ScheduleDayResolver`), so Only This Day, cancelled blocks, Out Today and no-school days all count. Room blocks and turns in the adolescent room don't. With no lane marked as the guide's, nobody counts as away.
  - The rules are `AwayDay` (`Schedules/Services/AwayTimes.swift`): `clashes(children:start:)`, `away(children:in:)`, `freeStarts(children:ownStarts:)` (every 5 minutes inside the quick-time hours, no group in the next 30 minutes and no other timed lesson of the guide's within 30 minutes either side; the first start of each free stretch, four at most) and `freeHalves`. Every sentence comes from `AwayText`. `AwayTimes.days(from:through:in:calendar:)` loads a whole range with one timetable fetch.
  - The planner holds one `[Date: AwayDay]` for its days (`WeekPlanSection+Away.swift`), reloaded when a `TimetableLane`, `TimetableBlock` or `TimetableChange` changes and when the strip's days change; cards, columns and the picker only read it (`AwayOnCards`). The lesson's sheet loads one day at tap time (`ScheduledDateEdits.awayInfo`) for its unsaved roster.
  - A timed clash turns the chip amber with one line under the children and counts in the day's badge (a day with only these or same-time clashes shows the plain badge, never Rearrange, which can't move a timed lesson). An untimed lesson with a child away in its half gets a quiet line, not a clash. The Schedules page's warning, `weekly_schedules`, and the replies of `schedule_presentation` and `reschedule_presentation` use the same rule.

## Version History

- **2026-02-04**: Initial implementation
  - ModelExtensions.swift created
  - WorkDetailView enhanced with presentation context
  - LessonAssignmentDetailSheet enhanced with work summary
  - GroupPracticeSheet enhanced with lesson context
  - LessonJourneyTimeline component created
  - LessonProgressView created
  - FollowUpWorkService created
