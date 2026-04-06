# Lesson Planning Calendar — Feature Plan

## Summary

Add a per-child lesson planning calendar to Maria's Notebook that helps plan the school year. When the user places a lesson (e.g., "Racks and Tubes") for a child, the app auto-schedules the entire group sequence of lessons, spaced every N school days apart.

## User Requirements (Confirmed)

1. **Layout**: Perpetual calendar style — full year grid where columns = months, rows = day numbers (1-31). The user has existing code for this view (`PerpetualCalendarView.swift` in a `PerpetualCalendar` folder) that is NOT yet in the repo. **This code needs to be added to the repo before implementation begins.**

2. **Location**: Lives as a new **"Year Plan" tab** on each student's detail page (alongside Overview, Meetings, Notes, Progress, History, Files).

3. **Day detail**: Abbreviated lesson names shown on each day cell.

4. **Spacing**: Configurable per lesson placement (e.g., every 3 school days for math, every 5 for cultural). User sets the interval when adding a sequence.

5. **Sequence**: When placing a lesson, the app auto-schedules the **whole group sequence** — all lessons in that `subject + group` sorted by `orderInGroup`, from the selected lesson onward, spaced by the configured interval.

6. **Horizon**: Full school year (~180 school days, Aug-May).

## Existing Infrastructure to Reuse

### Calendar & Scheduling
- `SchoolCalendarService` (`AppCore/SchoolCalendarService.swift`): `nextSchoolDay(after:)`, `isNonSchoolDay()`, `precomputedNonSchoolSet()` — all async, @MainActor
- `SchoolCalendar` (`AppCore/SchoolCalendar.swift`): Static wrapper around SchoolCalendarService
- **PerpetualCalendarView** (NOT YET IN REPO): User's existing perpetual calendar code — the base layout to adapt

### Lesson Sequencing
- `PlanNextLessonService` (`Services/PlanNextLessonService.swift`): `findNextLesson(after:in:)` finds next lesson in subject+group sequence. Walk this repeatedly to get the full remaining sequence.
- `Lesson` model has `subject`, `group`, `orderInGroup` for sequencing within a group

### Data Models (no new models needed)
- `Student` (`Students/StudentModel.swift`): firstName, lastName, birthday, level
- `Lesson` (`Lessons/LessonModel.swift`): name, subject, group, orderInGroup
- `StudentLesson` (`Students/StudentLessonModel.swift`): Links student to lesson with `scheduledFor` date. Uses `setScheduledFor()` to schedule.
- `StudentLessonFactory` (`Students/StudentLessonFactory.swift`): `makeScheduled()`, `insertScheduled()`, `attachRelationships()`

### Colors
- `AppColors.color(forSubject:)` (`AppCore/AppColors.swift`): Maps subject names to SwiftUI Colors (math=indigo, language=purple, science=teal, etc.)

### Student Detail Page
- `StudentDetailTab` enum in `Students/StudentDetailTabNavigation.swift`: Currently has `overview, meetings, notes, progress, history, files`
- `StudentDetailView` (`Students/StudentDetailView.swift`): Has `tabContent` switch that routes to tab views

## Implementation Plan

### New Files to Create

#### 1. `Students/YearPlan/StudentYearPlanTab.swift`
Main tab content view:
- Adapts the PerpetualCalendarView layout for lesson planning
- Shows the perpetual calendar grid with the selected student's scheduled lessons overlaid as abbreviated, subject-colored labels on each day
- "Add Sequence" button opens `AddSequenceSheet`
- Year navigation (< 2026 >) at top

#### 2. `Students/YearPlan/AddSequenceSheet.swift`
Sheet for adding a lesson group sequence:
- Searchable lesson picker
- Date picker for start date (defaults to next school day)
- Stepper: "Every ___ school days" (1-10, default 3)
- Preview list: each lesson in the group sequence with its computed date
- "Schedule All" button creates all `StudentLesson` records

#### 3. `Services/SequenceSchedulingService.swift`
Core auto-scheduling service:
```swift
@MainActor
struct SequenceSchedulingService {
    /// Preview the sequence without creating records
    static func previewSequence(
        startingWith lesson: Lesson,
        startDate: Date,
        spacingSchoolDays: Int,
        allLessons: [Lesson],
        context: ModelContext
    ) async -> [(lesson: Lesson, date: Date)]

    /// Create all StudentLesson records for the sequence
    static func scheduleSequence(
        startingWith lesson: Lesson,
        forStudent studentID: UUID,
        startDate: Date,
        spacingSchoolDays: Int,
        allLessons: [Lesson],
        allStudents: [Student],
        existingStudentLessons: [StudentLesson],
        context: ModelContext
    ) async -> [StudentLesson]
}
```
**Algorithm:**
1. Find all lessons in same `subject` + `group`, sorted by `orderInGroup`, from the starting lesson onward
2. First lesson scheduled on `startDate`
3. Each subsequent lesson: call `SchoolCalendarService.nextSchoolDay(after:)` N times from previous date
4. Check duplicates via `PlanNextLessonService.existsActive()`, skip if exists
5. Create via `StudentLessonFactory.makeScheduled()`, attach relationships, insert, save

### Files to Modify

#### 1. `Students/StudentDetailTabNavigation.swift`
- Add `case yearPlan` to `StudentDetailTab` enum
- Add "Year Plan" tab button (icon: `calendar.badge.plus`) in both standard and compact layouts

#### 2. `Students/StudentDetailView.swift`
- Add `case .yearPlan: StudentYearPlanTab(student: student)` to the `tabContent` switch

## Prerequisites

**IMPORTANT**: Before starting implementation, the user's existing `PerpetualCalendar` folder with `PerpetualCalendarView.swift` must be added to the repo. This is the base calendar layout that will be adapted for lesson planning.

## Branch

Development branch: `claude/lesson-planning-calendar-lhy11`

## Key Design Decisions
- No new SwiftData models — reuses existing `StudentLesson` with `scheduledFor` dates
- Per-child view on student detail page (not a separate sidebar item)
- Perpetual calendar layout (months as columns, days 1-31 as rows) — NOT horizontal scrolling strip
- Full school year visible at once
- Lessons shown as abbreviated names with subject colors on calendar days
- Spacing configurable per placement, not globally
