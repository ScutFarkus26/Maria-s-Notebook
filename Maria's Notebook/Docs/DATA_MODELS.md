# Data Models

This document describes the SwiftData models used in Maria's Notebook.

## Overview

All models use SwiftData's `@Model` macro and follow CloudKit compatibility patterns:
- UUID primary keys with `@Attribute(.unique)`
- Enum properties stored as raw strings
- Foreign keys stored as `String` (not UUID)
- Relationship arrays marked as optional

## Entity Relationship Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Student   │────▶│StudentLesson│◀────│   Lesson    │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │                   │
       │                   ▼                   │
       │            ┌─────────────┐            │
       │            │    Note     │◀───────────┘
       │            └─────────────┘
       │                   ▲
       ▼                   │
┌─────────────┐     ┌─────────────┐
│ WorkModel   │────▶│  WorkStep   │
└─────────────┘     └─────────────┘
       │
       ├────▶ WorkParticipantEntity
       ├────▶ WorkCheckIn
       └────▶ WorkCompletionRecord

┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Project   │────▶│ProjectSession│────▶│    Note     │
└─────────────┘     └─────────────┘     └─────────────┘
       │
       └────▶ ProjectAssignmentTemplate

┌─────────────┐     ┌─────────────┐
│Presentation │────▶│    Note     │
└─────────────┘     └─────────────┘

┌─────────────────┐
│AttendanceRecord │────▶ Note
└─────────────────┘
```

## Core Models

### Student

The primary entity representing a student in the classroom.

**Location:** `Students/StudentModel.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `firstName` | String | First name |
| `lastName` | String | Last name |
| `nickname` | String? | Optional nickname |
| `birthday` | Date | Date of birth |
| `levelRaw` | String | Level enum stored as string ("Lower" or "Upper") |
| `nextLessons` | [String] | Upcoming lesson IDs (stored as UUID strings) |
| `manualOrder` | Int | Manual sort order |
| `dateStarted` | Date? | When student enrolled |
| `modifiedAt` | Date | Last modification timestamp |

**Computed Properties:**
- `level: Level` - Enum accessor (.lower, .upper)
- `fullName: String` - Combined first and last name
- `nextLessonUUIDs: [UUID]` - UUID convenience accessor

**Relationships:**
- `documents: [Document]?` - Student's attached documents

---

### Lesson

Curriculum lessons organized by subject and group.

**Location:** `Lessons/LessonModel.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `name` | String | Lesson name |
| `subject` | String | Subject area (e.g., "Math", "Language") |
| `group` | String | Group/category (e.g., "Decimal System") |
| `orderInGroup` | Int | Order within group |
| `sortIndex` | Int | Global sort index within subject |
| `subheading` | String | Short description |
| `writeUp` | String | Detailed lesson content (Markdown) |
| `sourceRaw` | String | Source type ("album" or "personal") |
| `personalKindRaw` | String? | Personal lesson subtype |
| `defaultWorkKindRaw` | String? | Default work type for this lesson |
| `pagesFileBookmark` | Data? | Security-scoped bookmark for attached file |
| `pagesFileRelativePath` | String? | Relative path to imported file |

**Computed Properties:**
- `source: LessonSource` - Enum accessor (.album, .personal)
- `personalKind: PersonalLessonKind?` - Personal lesson type
- `defaultWorkKind: WorkKind?` - Default work kind

**Relationships:**
- `notes: [Note]?` - Attached notes
- `studentLessons: [StudentLesson]?` - Student lesson instances

---

### StudentLesson

Links students to lessons with scheduling and presentation tracking.

**Location:** `Students/StudentLessonModel.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `lessonID` | String | Foreign key to Lesson (UUID string) |
| `_studentIDsData` | Data? | JSON-encoded student IDs |
| `createdAt` | Date | Creation timestamp |
| `scheduledFor` | Date? | Scheduled presentation date/time |
| `scheduledForDay` | Date | Denormalized start-of-day for queries |
| `givenAt` | Date? | When lesson was presented |
| `isPresented` | Bool | Whether lesson has been presented |
| `notes` | String | Legacy notes field |
| `needsPractice` | Bool | Needs follow-up practice |
| `needsAnotherPresentation` | Bool | Needs re-presentation |
| `followUpWork` | String | Follow-up work description |
| `studentGroupKeyPersisted` | String | Denormalized student group key |

**Computed Properties:**
- `studentIDs: [String]` - Student ID array accessor
- `lessonIDUUID: UUID?` - UUID convenience accessor
- `isScheduled: Bool` - Has scheduled date
- `isGiven: Bool` - Has been presented

**Relationships:**
- `lesson: Lesson?` - Parent lesson
- `students: [Student]` - Transient student references
- `unifiedNotes: [Note]?` - Attached notes

---

### WorkModel

Tracks student work items through their lifecycle.

**Location:** `Work/WorkModel.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `title` | String | Work title |
| `workTypeRaw` | String | Work type ("Research", "Follow Up", "Practice", "Report") |
| `studentLessonID` | UUID? | Optional link to StudentLesson |
| `notes` | String | Work notes |
| `createdAt` | Date | Creation date |
| `completedAt` | Date? | Completion date |
| `kindRaw` | String? | Work kind raw value |
| `statusRaw` | String | Status ("active", "review", "complete") |
| `assignedAt` | Date | Assignment date |
| `lastTouchedAt` | Date? | Last activity date (for aging) |
| `dueAt` | Date? | Due date |
| `completionOutcomeRaw` | String? | Completion outcome |
| `studentID` | String | Primary student ID (CloudKit string) |
| `lessonID` | String | Lesson ID (CloudKit string) |
| `presentationID` | String? | Related presentation ID |
| `trackID` | String? | Track ID if part of curriculum track |
| `trackStepID` | String? | Track step ID |
| `scheduledNote` | String? | Scheduling notes |
| `scheduledReasonRaw` | String? | Scheduling reason |
| `sourceContextTypeRaw` | String? | Source context type |
| `sourceContextID` | String? | Source context ID |
| `legacyContractID` | UUID? | Legacy migration reference |
| `legacyStudentLessonID` | String? | Legacy migration reference |

**Computed Properties:**
- `workType: WorkType` - Work type enum
- `kind: WorkKind?` - Work kind enum
- `status: WorkStatus` - Status enum (.active, .review, .complete)
- `completionOutcome: CompletionOutcome?` - Completion outcome enum
- `isCompleted`, `isOpen`, `isActive`, `isReview`, `isComplete` - Status helpers

**Relationships:**
- `participants: [WorkParticipantEntity]?` - Student participants
- `checkIns: [WorkCheckIn]?` - Check-in records
- `steps: [WorkStep]?` - Work steps
- `unifiedNotes: [Note]?` - Attached notes

---

### Note

Universal note entity that can attach to multiple contexts.

**Location:** `Models/Note.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `createdAt` | Date | Creation timestamp |
| `updatedAt` | Date | Last update timestamp |
| `body` | String | Note content |
| `isPinned` | Bool | Pinned status |
| `categoryRaw` | String | Category enum raw value |
| `includeInReport` | Bool | Include in reports |
| `imagePath` | String? | Path to attached image |
| `reportedBy` | String? | Reporter type |
| `reporterName` | String? | Reporter name |
| `scopeBlob` | Data? | JSON-encoded scope |
| `searchIndexStudentID` | UUID? | Indexed student ID for queries |
| `scopeIsAll` | Bool | Scope is "all students" |

**Note Categories:**
- `academic`, `behavioral`, `social`, `emotional`, `health`, `attendance`, `general`

**Note Scopes:**
- `.all` - Applies to all students
- `.student(UUID)` - Applies to single student
- `.students([UUID])` - Applies to multiple students

**Relationships (one set per note):**
- `lesson`, `work`, `studentLesson`, `presentation`
- `attendanceRecord`, `workCheckIn`, `workCompletionRecord`
- `workPlanItem`, `studentMeeting`, `projectSession`
- `communityTopic`, `reminder`, `schoolDayOverride`
- `studentTrackEnrollment`
- `studentLinks: [NoteStudentLink]?` - Multi-student junction records

---

### AttendanceRecord

Daily attendance tracking per student.

**Location:** `Attendance/AttendanceModels.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `studentID` | String | Student ID (CloudKit string) |
| `date` | Date | Attendance date (normalized to start of day) |
| `statusRaw` | String | Status raw value |
| `absenceReasonRaw` | String | Absence reason raw value |
| `note` | String? | Optional note |

**Attendance Statuses:**
- `unmarked`, `present`, `absent`, `tardy`, `leftEarly`

**Absence Reasons:**
- `none`, `sick`, `vacation`

**Relationships:**
- `notes: [Note]?` - Attached notes

---

### Presentation (LessonAssignment)

Unified model for lesson scheduling and presentation history.

**Location:** `Models/Presentation.swift`

**Note:** The SwiftData entity class is named `LessonAssignment` for database compatibility.
Use the `Presentation` typealias in code for cleaner semantics.

**Lifecycle:** `draft` → `scheduled` → `presented`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `createdAt` | Date | Creation timestamp |
| `modifiedAt` | Date | Last modification |
| `stateRaw` | String | State: "draft", "scheduled", "presented" |
| `scheduledFor` | Date? | When scheduled (nil for drafts) |
| `scheduledForDay` | Date | Denormalized start-of-day for queries |
| `presentedAt` | Date? | When actually presented |
| `lessonID` | String | Lesson ID (CloudKit string) |
| `studentIDs` | [String] | Participating student IDs (JSON-encoded) |
| `needsPractice` | Bool | Students need more practice |
| `needsAnotherPresentation` | Bool | Should present again |
| `followUpWork` | String | Follow-up work description |
| `notes` | String | General notes |
| `trackID` | String? | Track ID if applicable |
| `trackStepID` | String? | Track step ID |
| `lessonTitleSnapshot` | String? | Frozen title at presentation time |
| `lessonSubheadingSnapshot` | String? | Frozen subheading |
| `migratedFromStudentLessonID` | String? | Migration tracking |
| `migratedFromPresentationID` | String? | Migration tracking |

**Relationships:**
- `lesson: Lesson?` - The lesson being presented
- `unifiedNotes: [Note]?` - Attached notes (cascade delete)

**Computed Properties:**
- `state: PresentationState` - Type-safe state accessor
- `studentUUIDs: [UUID]` - Student IDs as UUIDs
- `isDraft`, `isScheduled`, `isPresented` - State helpers

---

### Project

Classroom project with sessions and templates.

**Location:** `Projects/ProjectModels.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `createdAt` | Date | Creation timestamp |
| `modifiedAt` | Date | Last modification |
| `title` | String | Project title |
| `bookTitle` | String? | Associated book title |
| `memberStudentIDs` | [String] | Member student IDs |
| `isActive` | Bool | Active status |

**Relationships:**
- `sharedTemplates: [ProjectAssignmentTemplate]?` - Assignment templates
- `sessions: [ProjectSession]?` - Project sessions

---

### ProjectSession

Individual session within a project.

**Location:** `Projects/ProjectModels.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `createdAt` | Date | Creation timestamp |
| `projectID` | String | Parent project ID (CloudKit string) |
| `meetingDate` | Date | Session date |
| `chapterOrPages` | String? | Chapter/pages covered |
| `notes` | String? | Session notes |
| `agendaItemsJSON` | String | JSON-encoded agenda items |
| `templateWeekID` | String? | Template week reference |

**Relationships:**
- `project: Project?` - Parent project
- `noteItems: [Note]?` - Attached notes

---

## Supporting Models

### WorkParticipantEntity

Tracks individual student participation in a work item.

**Location:** `Work/WorkParticipantEntity.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `studentID` | String | Student ID (CloudKit string) |
| `completedAt` | Date? | Completion date |

---

### WorkCheckIn

Check-in record for work items.

**Location:** `Work/WorkCheckIn.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `workID` | String | Work item ID (CloudKit string) |
| `studentID` | String | Student ID (CloudKit string) |
| `createdAt` | Date | Check-in timestamp |
| `statusRaw` | String | Status raw value |
| `notes` | String? | Check-in notes |

---

### WorkStep

Individual step within a work item.

**Location:** `Work/WorkStep.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `title` | String | Step title |
| `orderIndex` | Int | Order within work |
| `completedAt` | Date? | Completion date |

---

### WorkCompletionRecord

Records student completion of a work item.

**Location:** `Work/WorkCompletionRecord.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `workID` | String | Work item ID (CloudKit string) |
| `studentID` | String | Student ID (CloudKit string) |
| `completedAt` | Date | Completion date |
| `outcomeRaw` | String? | Outcome raw value |

---

### Document

File attachments for students.

**Location:** `Models/Document.swift`

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `filename` | String | File name |
| `relativePath` | String? | Relative file path |
| `bookmarkData` | Data? | Security-scoped bookmark |
| `createdAt` | Date | Creation timestamp |

---

## Enum Reference

### WorkStatus
- `active` - Work is in progress
- `review` - Work is ready for review
- `complete` - Work is finished

### WorkKind
- `practice` - Practice work
- `followUp` - Follow-up work
- `research` - Research work
- `report` - Report/documentation

### CompletionOutcome
- `mastered` - Student mastered the content
- `needsReview` - Needs additional review
- `needsReteach` - Requires re-teaching

### LessonSource
- `album` - Standard curriculum lesson
- `personal` - Personal/custom lesson

### PersonalLessonKind
- `personal` - Personal lesson
- `extension` - Extension activity
- `remediation` - Remediation work

---

## CloudKit Compatibility Notes

### Foreign Key Pattern

All foreign keys use `String` instead of `UUID`:

```swift
// Storage
var studentID: String = ""

// Computed accessor for convenience
var studentIDUUID: UUID? {
    get { UUID(uuidString: studentID) }
    set { studentID = newValue?.uuidString ?? "" }
}
```

### Enum Storage Pattern

Enums are stored as raw strings:

```swift
// Storage
private var statusRaw: String = "active"

// Computed accessor
var status: WorkStatus {
    get { WorkStatus(rawValue: statusRaw) ?? .active }
    set { statusRaw = newValue.rawValue }
}
```

### Optional Relationships

All relationship arrays are optional:

```swift
@Relationship(deleteRule: .cascade, inverse: \Note.work)
var notes: [Note]? = []
```

### External Storage

Large data uses external storage:

```swift
@Attribute(.externalStorage)
var pagesFileBookmark: Data? = nil
```

---

## Migration Notes

See [LegacyCleanupNotes.md](../LegacyCleanupNotes.md) for migration history from `WorkContract` to `WorkModel`.

Migration functions are located in `Services/DataMigrations.swift`.
