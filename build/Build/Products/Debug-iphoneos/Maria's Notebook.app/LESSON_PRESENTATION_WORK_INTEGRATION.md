# Lesson → Presentation → Work Integration

## Overview

This document describes the cohesive integration between Lessons, Presentations, and Work in Maria's Notebook. The integration creates a complete journey from curriculum content through teaching sessions to student practice and follow-up work.

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

### 1. Model Extensions (`Maria's Notebook/Models/ModelExtensions.swift`)

Provides convenience methods for traversing relationships:

```swift
// WorkModel extensions
work.fetchPresentation(from: context) -> Presentation?
work.fetchLesson(from: context) -> Lesson?
work.fetchStudent(from: context) -> Student?
work.fetchPracticeSessions(from: context) -> [PracticeSession]

// Presentation extensions
presentation.fetchRelatedWork(from: context) -> [WorkModel]
presentation.fetchStudents(from: context) -> [Student]
presentation.fetchRelatedPracticeSessions(from: context) -> [PracticeSession]
presentation.workCompletionStats(from: context) -> (completed: Int, total: Int)

// Lesson extensions
lesson.fetchAllPresentations(from: context) -> [LessonAssignment]
lesson.fetchAllWork(from: context) -> [WorkModel]
lesson.fetchAllPracticeSessions(from: context) -> [PracticeSession]
lesson.getLessonStats(from: context) -> LessonStats
```

### 2. Enhanced WorkDetailView

**Location**: `Maria's Notebook/Work/WorkDetailView.swift`

**New Features**:
- Displays presentation context section showing:
  - When the lesson was presented
  - Presentation flags (needsPractice, needsAnotherPresentation, followUpWork)
  - Other students who received the same presentation
  - Presentation notes

**Added State**:
```swift
@State private var relatedPresentation: Presentation? = nil
```

**Benefits**:
- Teachers can see the full context of why work was assigned
- Easy access to presentation notes while reviewing student work
- Visibility into group dynamics (who else is working on this)

### 3. Presentation Detail with Work Summary

**Location**: `Maria's Notebook/Presentations/LessonAssignmentDetailSheet.swift`

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

**Location**: `Maria's Notebook/Work/GroupPracticeSheet.swift`

**New Features**:
- Presentation & lesson context section showing:
  - The lesson being practiced
  - Subject and group information
  - When the lesson was presented
  - Presentation status (presented vs scheduled)

**Added State**:
```swift
@State private var relatedPresentation: Presentation? = nil
@State private var relatedLesson: Lesson? = nil
```

**Benefits**:
- Teachers see the complete educational context during practice
- Links practice sessions back to original presentations
- Better understanding of the lesson's instructional history

### 5. LessonJourneyTimeline Component

**Location**: `Maria's Notebook/Components/LessonJourneyTimeline.swift`

**Purpose**: Visual timeline showing the complete journey from lesson to outcomes

**Features**:
- Horizontal scrollable timeline
- Each presentation shown as a node
- Connecting lines to related work items
- Practice sessions linked to work
- Visual indicators for completion status

**Usage**:
```swift
LessonJourneyTimeline(lesson: lesson, modelContext: context)
    .frame(height: 350)
```

**Benefits**:
- At-a-glance view of lesson usage over time
- Understand the complete flow from teaching to practice
- Identify patterns in lesson effectiveness

### 6. LessonProgressView

**Location**: `Maria's Notebook/Lessons/LessonProgressView.swift`

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

**Location**: `Maria's Notebook/Services/FollowUpWorkService.swift`

**Purpose**: Automate creation of follow-up work from presentation flags

**Key Functions**:

```swift
// Generate work from presentation flags
FollowUpWorkService.generateWorkFromPresentation(
    presentation, 
    context: context
) -> [WorkModel]

// Analyze what follow-up is needed
FollowUpWorkService.analyzePresentation(presentation) -> PresentationFollowUp

// Find presentations needing follow-up
FollowUpWorkService.findPresentationsNeedingFollowUp(
    in: context
) -> [Presentation]

// Get suggestions without creating work
FollowUpWorkService.suggestWork(
    for: presentation,
    in: context
) -> [WorkSuggestion]
```

**Convenience Extensions**:
```swift
// On Presentation
presentation.generateFollowUpWork(in: context) -> [WorkModel]
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

## Migration Notes

No database migration required - all enhancements work with existing data model. The integration uses existing fields:
- `WorkModel.presentationID` (already exists)
- `WorkModel.lessonID` (already exists)
- `Presentation.needsPractice`, `needsAnotherPresentation`, `followUpWork` (already exist)

## Version History

- **2026-02-04**: Initial implementation
  - ModelExtensions.swift created
  - WorkDetailView enhanced with presentation context
  - LessonAssignmentDetailSheet enhanced with work summary
  - GroupPracticeSheet enhanced with lesson context
  - LessonJourneyTimeline component created
  - LessonProgressView created
  - FollowUpWorkService created
