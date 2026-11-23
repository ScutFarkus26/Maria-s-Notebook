# Data Models

This document describes the Core Data models used in Cosmic Daybook.

## Overview

All models are NSManagedObject subclasses (with `CD` prefix) defined in `CosmicDaybook.xcdatamodeld` and follow CloudKit compatibility patterns:
- UUID primary keys (no unique constraints — CloudKit incompatible)
- Enum properties stored as raw strings
- Foreign keys stored as `String` (not UUID)
- Relationship arrays marked as optional

## Entity Relationship Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Student   │────▶│LessonAssign.│◀────│   Lesson    │
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

**Location:** `Students/Models/StudentEntity.swift` (class `CDStudent`)

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
| `parentLockerID` | String? | The child's `student_id` on the school's ParentLocker site, stored once matched by name (schema 18); written only on the guide's devices |
| `bornAfterSunset` | Bool | Born after sunset, so the child's Hebrew birthday is the next day's (schema 21; optional, default NO, a record from before it reads as false). The Hebrew date is worked out from `birthday` wherever it's shown, never stored |
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

**Location:** `Lessons/LessonEntity.swift` (class `CDLesson`)

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
| `greatLessonRaw` | String? | `GreatLesson` tag; the Three-Year View builds its Great Lessons row from it (story-format lessons preferred) |
| `isKeyLesson` | Bool | Milestone flag (schema 6, 2026-09). Key lessons are the Three-Year View's default rows, together with the first lesson of every sequence |

**Computed Properties:**
- `source: LessonSource` - Enum accessor (.album, .personal)
- `personalKind: PersonalLessonKind?` - Personal lesson type
- `defaultWorkKind: WorkKind?` - Default work kind

**Relationships:**
- `notes: [Note]?` - Attached notes
- `lessonAssignments: [LessonAssignment]?` - Lesson assignment instances

---

### LessonAssignment

Links students to lessons with scheduling and presentation tracking.

**Location:** `Models/LessonAssignmentEntity.swift` (class `CDLessonAssignment`)

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `lessonID` | String | Foreign key to Lesson (UUID string) |
| `_studentIDsData` | Data? | JSON-encoded student IDs |
| `createdAt` | Date | Creation timestamp |
| `scheduledFor` | Date? | Scheduled day, half of day, and either an ordering slot or a set start time (see below) |
| `scheduledForDay` | Date | Denormalized start-of-day for queries |
| `givenAt` | Date? | When lesson was presented |
| `isPresented` | Bool | Whether lesson has been presented |
| `notes` | String | Legacy notes field |
| `needsPractice` | Bool | Needs follow-up practice. Since schema 25 it means "some child on it does"; each child's own value is on her `LessonPresentation` row |
| `needsAnotherPresentation` | Bool | Needs re-presentation; since schema 25 "some child on it does", as `needsPractice` |
| `followUpWork` | String | Follow-up work description |
| `studentGroupKeyPersisted` | String | Denormalized student group key |

**How `scheduledFor` is read** (plan "Lesson times on cards", decision 4; `Presentations/Planning/DayHalfPlanner.swift`, `moment(of:)`). Most lessons have no clock time, only a half of the day and an order inside it; some have a start time Danny set. Both live in this one date, told apart by how it is written, so there is no extra field and no schema change:

| Stored time | Reads as |
|-------------|----------|
| midnight (0:00:00) | a morning slot (rows written before the halves existed) |
| 9:00 or 14:00, second 0–58 | a slot in that half; the second is its rank |
| 9:00:59 or 14:00:59 (also 0:00:59) | a set time of exactly 9:00, 2:00 (or midnight): the marker |
| any other time, second 0 | a set time |
| any other time, second ≠ 0 | a slot in that half (an old value stored one second below a timed lesson) |

Rules that keep it true:
- Every write of a set time goes through `DayHalfPlanner.settingTime(hour:minute:on:)` (or `CDLessonAssignment.setTime`), which writes second 0, or 59 for the marker hours. Removing one (`removingTime(from:)`, `removeTime`) puts the lesson in the last slot of its half (rank 58). Slot ranks never pass 58.
- Moving a lesson to another day keeps a set time (`rebasing(_:onto:)`, `schedule(onDay:keepingTimeUsing:)`, set on the clock so daylight-saving days are right); a slot stays a slot. Only Remove Time, Clear Schedule, choosing the other half (`DayPeriod.applied(to:)`) and MCP `time: "none"` remove a time.
- A day's lessons are listed in one order everywhere (`LessonAssignmentOrdering`): morning then afternoon; inside a half, set times first by clock time, then slots by rank. Balance AM/PM never moves a timed lesson. Two lessons on one day at the same start time are a clash (`DayHalfPlanner.sameTimeClashes(in:)`).
- Code that shows or compares a lesson's clock time reads it through `moment(of:)` / `setMinute(of:)`, never `Calendar.component(.hour…)` on the raw date: a slot's 9:00:03 is not a time.

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

**Location:** `Work/Models/WorkModelEntity.swift` (class `CDWorkModel`)

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `title` | String | Work title |
| `workTypeRaw` | String | Work type ("Research", "Follow Up", "Practice", "Report") |
| `lessonAssignmentID` | UUID? | Optional link to LessonAssignment |
| `notes` | String | Work notes |
| `createdAt` | Date | Creation date |
| `completedAt` | Date? | Completion date |
| `kindRaw` | String? | Work kind raw value |
| `statusRaw` | String | Status ("active", "review", "mastered", "keepPracticing", "incomplete", "complete" = Done) |
| `assignedAt` | Date | Assignment date |
| `lastTouchedAt` | Date? | Last activity date (for aging) |
| `dueAt` | Date? | A due date the guide set, and nothing else (2026-11-21). The next check is the earliest scheduled check-in (`WorkCheckInService.nextCheckDay`); scheduling a check no longer copies its day here |
| `completionOutcomeRaw` | String? | Legacy: folded into `statusRaw` by `WorkStatusMigration`; not read elsewhere |
| `studentID` | String | Primary student ID (CloudKit string) |
| `lessonID` | String | Lesson ID (CloudKit string) |
| `presentationID` | String? | Related presentation ID |
| `scheduledNote` | String? | Scheduling notes |
| `scheduledReasonRaw` | String? | Scheduling reason |
| `sourceContextTypeRaw` | String? | Source context type |
| `sourceContextID` | String? | Source context ID |
| `legacyContractID` | UUID? | Legacy migration reference |
| `legacyLessonAssignmentID` | String? | Legacy migration reference |
| `assignmentID` | String? | Which assignment this copy is of (schema 25; optional). Every copy of work given to a group shares one (`WorkAssignmentService`); a row given to one child carries its own id (`WorkRepository.createWork`). Nil on work from before it until `WorkAssignmentFill` stamps it, at launch and after a restore, from `WorkGrouping`'s guess. Linked copies are matched by it, and the one ownership rule (`WorkOwnership`) reads it |
| `isSharedRow` | Bool | Whether this is a row its children share (a project's work), rather than one child's own copy (schema 25; default false). New rows are made false; only the fill sets it, for an older row that names several children with no copies beside it. Project-session work counts as shared by construction |

**Computed Properties:**
- `workType: WorkType` - Work type enum
- `kind: WorkKind?` - Work kind enum
- `status: WorkStatus` - The one verdict (.active, .review, .mastered, .keepPracticing, .incomplete, .done)
- `isCompleted`, `isOpen`, `isActive`, `isReview`, `isClosed` - Status helpers

**Relationships:**
- `participants: [WorkParticipantEntity]?` - Student participants
- `checkIns: [WorkCheckIn]?` - Check-in records
- `steps: [WorkStep]?` - Work steps
- `unifiedNotes: [Note]?` - Attached notes

---

### Note

Universal note entity that can attach to multiple contexts.

**Location:** `Models/NoteEntity.swift` (class `CDNote`)

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
- `lesson`, `work`, `lessonAssignment`, `presentation`
- `attendanceRecord`, `workCheckIn`, `workCompletionRecord`
- `workPlanItem`, `studentMeeting`, `projectSession`
- `communityTopic`, `schoolDayOverride`; `reminder` stays in the model but nothing sets it since Reminders sync went (round-two Simplify)
- `studentLinks: [NoteStudentLink]?` - Multi-student junction records

---

### AttendanceRecord

Daily attendance tracking per student.

**Location:** `Attendance/Store/AttendanceRecordEntity.swift` (class `CDAttendanceRecord`)

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

**Location:** `Models/LessonPresentationEntity.swift` (class `CDLessonPresentation`)

**Note:** The Core Data entity is named `LessonPresentation`. The `Presentation` typealias is available in code for cleaner semantics.

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
| `needsPractice` | Bool? | Her own "needs practice" for the presentation she had (schema 25; optional). Nil means never set on her row, and her value is then the group record's (`LessonAssignment.needsPractice`); the group's false is everyone's false, since an older build clears it for all. Read and written through `LessonPresentation+ChildFacts`: a write for some children sets their rows and keeps the group record at "any child" for older builds, and readiness reads her row first |
| `needsAnotherPresentation` | Bool? | Her own "present again" (schema 25; optional), read and written as `needsPractice` |
| `manuallyUnblocked` | Bool? | She was let past the lesson's block by hand (schema 25; optional), read and written as `needsPractice` |
| `followUpWork` | String | Follow-up work description |
| `notes` | String | General notes |
| `lessonTitleSnapshot` | String? | Frozen title at presentation time |
| `lessonSubheadingSnapshot` | String? | Frozen subheading |
| `migratedFromLessonAssignmentID` | String? | Migration tracking |
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

**Location:** `Projects/ProjectEntity.swift` (class `CDProject`)

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

**Location:** `Projects/ProjectSessionEntity.swift` (class `CDProjectSession`)

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

**Location:** `Work/Models/WorkParticipantEntityCD.swift` (class `CDWorkParticipant`)

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `studentID` | String | Student ID (CloudKit string) |
| `completedAt` | Date? | Completion date |

---

### WorkCheckIn

Check-in record for work items.

**Location:** `Work/CheckIns/WorkCheckInEntity.swift` (class `CDWorkCheckIn`)

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `workID` | String | Work item ID (CloudKit string) |
| `studentID` | String | Student ID (CloudKit string) |
| `createdAt` | Date | Check-in timestamp |
| `statusRaw` | String | Status raw value |
| `notes` | String? | Check-in notes |
| `durationMinutes` | Int16? | Minutes practiced (schema 24; optional). Set on a practice check-in, which replaced practice sessions; read and write through `durationMinutesValue` |

---

### WorkStep

Individual step within a work item.

**Location:** `Work/Steps/WorkStepEntity.swift` (class `CDWorkStep`)

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier |
| `title` | String | Step title |
| `orderIndex` | Int | Order within work |
| `completedAt` | Date? | Completion date |

---

### WorkCompletionRecord

Records student completion of a work item.

**Location:** `Work/Completion/WorkCompletionRecordEntity.swift` (class `CDWorkCompletionRecord`)

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

**Location:** `Models/DocumentEntity.swift` (class `CDDocument`)

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
Open: `active` (Working), `review` (Needs Review). Closed: `mastered`,
`keepPracticing`, `incomplete`, `done` (raw `"complete"`, legacy no-verdict).

### WorkKind
- `practice` - Practice work
- `followUp` - Follow-up work
- `research` - Research work
- `report` - Report/documentation

### CompletionOutcome
Per work *step* only (`CDWorkStep.completionOutcomeRaw`): `mastered`
(case `proficient`), `needsMorePractice`, `needsReview`, `incomplete`,
`notApplicable`. On a work row it is a legacy column — see WorkStatus.

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
// Storage (NSManagedObject property)
@NSManaged var studentID: String

// Computed accessor
var studentIDUUID: UUID? {
    get { UUID(uuidString: studentID) }
    set { studentID = newValue?.uuidString ?? "" }
}
```

### Enum Storage Pattern

Enums are stored as raw strings:

```swift
// Storage (Core Data attribute)
@NSManaged var statusRaw: String

// Computed accessor
var status: WorkStatus {
    get { WorkStatus(rawValue: statusRaw) ?? .active }
    set { statusRaw = newValue.rawValue }
}
```

### Relationships

Relationships are configured in `CosmicDaybook.xcdatamodeld`. In code, they are accessed via `NSSet`:

```swift
// Core Data relationship (configured in xcdatamodeld with cascade delete rule)
@NSManaged var notes: NSSet?

// Typed accessor
var notesArray: [CDNote] {
    (notes as? Set<CDNote>)?.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) } ?? []
}
```

### External Storage

Large data uses external storage (configured via "Allows External Storage" in xcdatamodeld):

```swift
@NSManaged var pagesFileBookmark: Data?
```

---

## Migration Notes

The migration from SwiftData to Core Data (`NSManagedObject` subclasses with `NSPersistentCloudKitContainer`) is complete. All entities are now defined in `CosmicDaybook.xcdatamodeld` with `CD`-prefixed classes.

Data migration functions are located in `Services/Migrations/DataMigrations.swift`.


## Working notes from CLAUDE.md

Moved verbatim from `Cosmic Daybook/CLAUDE.md` on 2026-10-02 so that file keeps only the rules every session needs. Dates in the notes are when each change landed.

**Data-integrity rules (2026-09-10)** — each one closed a defect found by reading the live store over MCP, and each has a launch-time repair plus a creation-time guard:
- **One lesson name per sub-area.** `LessonRepository.createLesson` throws `CreationError.duplicateName` for a folded-name match in the same area + sequence (parsha lessons exempt via `parshaKey`); `DataCleanupService.mergeSameNameLessons` (in `deduplicateAllModels`, so both the launch and post-import passes) folds any pair that got in anyway onto the older record — CloudKit creation date, then `orderInSequence` — repointing presentations, marks, year-plan entries, work, notes, recall checks and the id-list fields, and collapsing a child's doubled plan entries and marks. Same name in *different* sub-areas is left alone on purpose.
- **A check-in always knows its work.** `CDWorkCheckIn.make(for:on:purpose:in:)` is the only creation path and writes the `workID` string and `work` relationship together; readers use `resolvedWork(in:)`. `CDWorkModel.prepareForDeletion` sweeps string-only check-ins so a bare `context.delete(work)` cascades too; `DataCleanupService.repairWorkCheckInLinks` relinks at launch and deletes true orphans only once their work has been missing on passes a day apart with an import begun since (`OrphanStudentGrace`, kind `.checkInWork`; 2026-10-05), never during a first download. Deleting a check-in detaches the notes that also belong to its work (`CDWorkCheckIn.prepareForDeletion`), so an observation logged that day stays with the work.
- **Work is for enrolled children.** `WorkRepository.createWork` throws `AssignmentError.studentNotEnrolled` when the student's record is on file and she has left the class (since 2026-11-21 `hasLeft()`: a child whose last day is still to come can still be given work); `assign_work` refuses before creating anything; MCP readers print a former student as "Name (withdrawn)".
- **An observation on a presentation is about specific children.** The link (`CDNote.lessonAssignment`) is per presentation; the student dimension is the note's scope (mirrored into `NoteStudentLink`). `NoteScope.forSelection` gives an empty picker selection the presentation's roster, never `.all`; `DataCleanupService.repairPresentationNoteScopes` narrows old whole-class presentation notes; `PresentationObservationCoverageService` judges coverage per child.
- **Which notes are about a child: one rule (2026-11-21).** `NoteAboutStudent` (`CDNote.aboutPredicate` for the fetch, `isAbout(_:_:)` in memory) decides it for her Notes tab, insights, the Progress tab's sequence cards, the sequence recap and her monthly report. Her own notes (indexed to her through `searchIndexStudentID`, so a one-child lesson note counts in her sequence card) and group notes naming her always count; the note's scope decides, not its student links. A `NoteAudience` says what else counts: `herOwn` (insights, sequence cards), `withClass` adds the class's notes (her Notes tab, her reports, the recap), and `everything` adds the class's context notes too. A context note (`CDNote.isContextNote`) is a whole-class note about the class's day, a community meeting's line or a calendar day's note; it no longer lands on every child's Notes tab or feeds Writing Help. A child's report takes the notes marked Include in Report from `ReportNotes` (`withClass`), and before it is drafted or printed every other child's name in a note becomes "a classmate". The roster's "last observed" (`StudentsViewModel.latestObservationDates`) still reads a note indexed to her or a scoped note's student links; it dates a note by when it was written (`createdAt`), so an edit doesn't move it, and leaves out notes the app writes itself (`reportedBy = "app"`, such as the rollover's "Promoted from Lower to Upper…").
- **Clean Up Leftovers (2026-09-30, Mac only; called Clean Up Old Records until 2026-10-03).** Settings › Troubleshooting runs `NotebookJunkCleanup` from `NotebookCleanupSheet`. The sheet previews first. The run makes a manual backup, checks it holds every touched entity, and recounts before deleting. The 2026-09-30 audit found ~3,340 such records, among them presentation rows with no child and no lesson, work participants with no work, and past blank unmarked attendance on unlocked days. The full list is in the file header. It also skips departed children's planned year-plan entries. Meeting work reviews of deleted work are kept on purpose. Counting and changing share one code path (`run(in:today:apply:)`), so the preview can't disagree with the run. It refuses during a restore, a first download, an unfinished `ClassroomShareRelease`, unsent sync changes, or a second running copy.

**Launch repairs, duplicates and the store files (2026-10-05)** — from the data-model bug hunt and `docs/Plans/Plan - Data model and launch repair fixes.md`:
- **Duplicates: the same keeper on every device.** Copies with different ids (attendance, a child's plan entries, marks) keep the lowest `id` string; same-id copies keep the earliest `createdAt` (to the millisecond), then the lowest CloudKit record name, then object URI. The winning content (for attendance, the read side's `AttendanceDeduplication.wins`) is copied onto the keeper, and `modifiedAt` never moves back. Nothing that changes (a mark, a status, a zone) decides which row survives: two devices at different sync states then each deleted the other's.
- **Duplicates: what waits.** No destructive cleanup while the stores are open without iCloud, or for a group none of whose copies has reached iCloud (`DedupSyncState`). Attendance copies fold only once settled: unchanged for ten minutes, with an import begun after the newest change (`DedupSyncState.stillSettling`).
- **Duplicates: children move first.** Every child of the dropped copy moves to the keeper, same id or not (`mergeNSSetRelationship`); the child's own id pass folds any pair. Cascade rules would otherwise delete them with the dropped copy.
- **Repairs never delete what may still be downloading.** The orphan graces (students' ids on work and presentations, check-ins' missing work) act only after a day and an import begun since the id went missing (`ImportWatermark`, per store); nothing during a first download; with sync off only the day applies. One-shot repair flags are set only after their save succeeds.
- **One copy of the app does the surgery.** Every copy holds a shared lock on the store folder; store surgery takes it exclusively (`StoreProcessLock`). Only the copy that had the files to itself at launch (`CoreDataStack.isPrimaryProcess`) runs launch repairs and duplicate cleanup, and a second copy (`isSecondaryProcess`) never puts records into the classroom share.
- **Backups and restores are the notebook's own store.** A backup holds, and a restore writes, only `private.sqlite`; a restore keeps this device's membership pin and the mirrored Apple reminders and calendar events as they are.
- **The retired outcome goes when a status is written.** `completionOutcomeRaw` is cleared by `CDWorkModel.status`'s setter and by the launch merge, so a later plain Done is never turned back into an old verdict.

## Kept, no screen (2026-11-21/22)

Fourteen features lost their screens and Claude tools on 2026-11-21/22 (`docs/Plans/Plan - Cut unused features and close the lesson loop.md`, one `Cut:` commit each; the last version with them is the tag `retired/2026-11-cuts`). Unlike round-two Simplify's `CoreDataStack.retiredEntities`, these entities are **not** retired: their classes, model entries, backup rows (`BackupEntityTable`), dedup merges, launch repairs, `StudentDeletion` cleanup and note link fields all stay, so backups and restores carry them unchanged and the backup golden didn't move. Only nothing in the app shows or edits them now.

| Feature taken out | Entities kept | Still read by |
|---|---|---|
| Parent Reports, the per-child report | `ParentCommunication` (`Models/`) | backups only; `Guardian` keeps its screen on a child's Overview |
| Spaced recall checks | `LessonRecallCheck` | Class Grid rings, the curriculum map, readiness and mastery evidence, `student_record` |
| Projects | `Project`, `ProjectSession`, `ProjectRole`, `ProjectAssignmentTemplate`, `ProjectTemplateWeek`, `ProjectWeekRoleAssignment` | work from a session (`WorkSourceContextType.projectSession`), note links, `SchoolYearScoping` (`CDProject.overlaps`) |
| Book Club | `BookClubPacket`, `BookClubSession`, `BookClubMeeting` | work type `.bookClubSession`, note links |
| Community topics | `CommunityTopic`, `ProposedSolution`, `CommunityAttachment` | `Note.communityTopicID`, the note editor's topic context |
| Issues | `Issue`, `IssueAction` | note links, `StudentDeletion` |
| Resources, Stories, Procedures | `Resource`, `Story`, `Procedure` (files stay on disk) | backups only |
| Going Out | `GoingOut`, `GoingOutChecklistItem` | `Note.goingOutID`, `StudentDeletion` |
| Today's day pad card | `DayPad` | the Calendar's day note, `day_pad` |
| Custom meeting templates | `MeetingTemplate` | the built-in templates (`BuiltInTemplateSeeder.meetingTemplate(from:)`) |
| The To-dos screen | `TodoItem` | Today, meetings, Tide sharing, chat (`TODOS.md`) |

Deletes that reach notes: an `Issue`'s and a `ProjectSession`'s delete cascades to their notes (`Issue.notes`, `ProjectSession.noteItems`); a `CommunityTopic`'s notes link by id (`Note.communityTopicID`), so its delete leaves them, but cascades to its solutions and attachments. Nothing in the app deletes any of the three now except a Replace restore and the same-id dedup: `mergeProjectSession` moves the notes to the kept copy first, `mergeCommunityTopic` moves the solutions and attachments, and `Issue` has no dedup. Deleting a child leaves an issue with nobody on it in place rather than deleting it with its notes (`StudentDeletion`, 2026-11-22).

## Core models, patterns and integrity rules (moved from CLAUDE.md, 2026-10-04)

Moved verbatim from `Cosmic Daybook/CLAUDE.md` on 2026-10-04 so that file keeps only a pointer and the few rules a session needs before touching this area. These are still rules: follow them.

**94 entities** defined in `CosmicDaybook.xcdatamodeld` (schema 25; schema 19 added `TodoItem.tideLink`, the Tide action a to-do is shared with, `docs/Technical notes/TIDE_SHARING.md`; schema 20 added Schedules' four shared types; schema 21 added `Student.bornAfterSunset`, the switch that moves a child's Hebrew birthday one day on; schema 22 added `LessonAttachment.modifiedAt`, when a lesson file was last replaced, renamed or given a note, read as `attachedAt` on older rows, `docs/Plans/Plan - Lesson file attachments.md`; schema 23 took the four track entities out of the private store and removed the columns that named them, since a child's place in a sequence is read off the presentation record; the entities stay in the model as dormant tombstones, because deleting them would have truncated the store's persistent history, `docs/Plans/Plan - Retire the track entities.md`; schema 24 added `WorkCheckIn.durationMinutes`, a practice check-in's minutes, when practice sessions folded into check-ins, `docs/Plans/Plan - Simplify the app, round two.md`; schema 25 added the private `LevelChange` (a child's level history), which assignment a work copy is of and whether it is the shared row (`WorkModel.assignmentID`, `isSharedRow`), a child's own `needsPractice`, `needsAnotherPresentation` and `manuallyUnblocked` on her `LessonPresentation` (nil: not set on her row), the person a guardian row stands for (`Guardian.personID`), and on the shared `AttendanceEmailSettings` the classroom's time zone and the session's first and last days, `docs/Plans/Plan - Domain logic fixes.md`): 67 private-only (7 of them retired in round-two Simplify, listed in `CoreDataStack.retiredEntities`: `ClassroomJob`, `JobAssignment`, `NoteTemplate`, `PracticeSession`, `Reminder`, `TodoSubtask` and `TodoTemplate` stay in the private store with their class names blanked, so their rows survive; nothing reads or writes them, backups leave them out and restores skip them), 15 in the classroom share (schema 16 added `ClassroomPerson`, the shared list of names people set for themselves; `Sharing/ClassroomNames.swift`; schema 17 added `SupplyTransaction.changedByID`, who changed a staple's level, so its history line shows that person's current name; schema 18 added how attendance goes to the school, `AttendanceEmailSettings.sendMethodRaw` and `parentLockerSite`, the channel of each send, `AttendanceEmailSend.channelRaw`, and the child's ParentLocker match, `Student.parentLockerID`), 12 dormant tombstones in no store (`CoreDataStack.dormantTombstoneEntities`: the features removed 2026-06-11 and, since schema 23, `Track`, `TrackStep`, `SequenceTrack` and `StudentTrackEnrollment`).

**Core Models:**

| Model | Class | Purpose |
|-------|-------|---------|
| Student | `CDStudent` | Student profiles (firstName, lastName, birthday, level) |
| Lesson | `CDLesson` | Curriculum lessons with attachments & exercises |
| LessonPresentation | `CDLessonPresentation` | Presentation scheduling & history; schema 25: her own `needsPractice`, `needsAnotherPresentation` and `manuallyUnblocked` (optional, nil when not set on her row) |
| LessonAssignment | `CDLessonAssignment` | Links students to lessons |
| WorkModel | `CDWorkModel` | Work items; one `WorkStatus` per row (Working / Needs Review open; Mastered / Keep Practicing / Incomplete / legacy Done closed), changed only through `WorkLogService`; schema 25: `assignmentID` (the assignment a copy is of) and `isSharedRow` |
| LevelChange | `CDLevelChange` | One change of a child's level (schema 25, private): `studentID`, `fromLevelRaw`, `toLevelRaw` (`CDStudent.Level` raw values) and the day it took effect, `changedOn`. Written only by `StudentLevelHistory` (the student page, `update_student`, the rollover and the roster import); a change undone the same day leaves no step, so a mis-tap leaves no history. Monthly reports read it until they were taken out (2026-11-21); the records stay. The student's own `previousLevelRaw` and `dateLastPromoted`, which the promotion line and older builds read, are kept matching the latest step |
| Guardian | `CDGuardian` | A child's parent or guardian (private), one row per child. `personID` (schema 25) is shared by the rows on different children that are one person, matched by email and name (guardians have no phone field); a lone row keeps nil, which stands for itself. Filled where nil at every launch and after every restore, never during a first download (`GuardianPeople`). An edit changes every row with that id, notes aside, so "receives reports" follows the person, and the guardian sheet names her other children |
| Note | `CDNote` | Observations with tags, multi-student scoping |
| AttendanceRecord | `CDAttendanceRecord` | Daily attendance tracking; `leavesAt` (schema 13) is a planned early pickup, not a mark; `returnedAt` + `statusBeforeLeavingRaw` (schema 14) record a child who left early and came back |
| TodoItem | `CDTodoItem` | The guide's to-dos; `tideLink` (schema 19) is the Tide action one is shared with, written only by the Mac's Tide sharing (`Services/Tide/`) and the backup restore |
| ClassroomMembership | `CDClassroomMembership` | This device's role and the pinned classroom share zone (private only) |
| AttendanceDayLock | `CDAttendanceDayLock` | A day the lead guide locked (shared); read and written through `AttendanceDayLocks` |
| AttendanceEmailSend / AttendanceEmailSettings | `CDAttendanceEmailSend` / `CDAttendanceEmailSettings` | The day's attendance going to the school: who sent a day's, and the guide's settings for it (shared, schema 12). Schema 18: `sendMethodRaw` (`email` or `parentLocker`, default `email`) and `parentLockerSite` on the settings, `channelRaw` (default `email`) on each send; picking ParentLocker also writes `isEnabled = false`, so Assistant builds from before schema 18 stop offering the email. Schema 25: the classroom's time zone (`classroomTimeZoneID`) and the session's first and last days (`sessionFirstDay`, `sessionLastDay`) on the settings, all optional. The zone is the one every day in both apps is worked out in (`AppCalendar`); unset or not a zone `TimeZone` knows, the device's own is used, and the first real save from a Mac fills it with the Mac's. The session counts only when both days are set and in order: the summer outside it is days off (`SchoolDayChecker`), and Day N, the year start, the share cutoff and the front-desk reminders read it; unset, everything behaves as before. A send with `channelRaw = "arrivalClosed"` is a note of when arrival closed, not a send, left out by every reader. Close Arrival writes it, one a day, and every way back to Arrival deletes it (2026-11-22, `AttendanceEmailLog.recordArrivalClosed` / `deleteArrivalClosedNotes`); it dates the close but never closes a day by itself. The notebook's own email is written from this row too (2026-11-21), so both apps send the same one. Read and written through `AttendanceEmailLog` |

**Core Data Patterns:**
- Entity classes use `CD` prefix (e.g., `CDStudent`, `CDLesson`)
- No unique constraints (incompatible with CloudKit)
- Enums stored as raw `String` (e.g., `statusRaw`, `categoryRaw`)
- Foreign keys as `String` not `UUID`
- `modifiedAt` for conflict resolution
- All properties optional or have defaults
- Relationships use `NSSet` (cast to `Set<CDEntityType>` for iteration)
- Use `mutableSetValue(forKey:)` for relationship mutations

**Data-integrity rules** (each has a creation-time guard and a launch-time repair; detail in `docs/Technical notes/DATA_MODELS.md`):
- One lesson name per sub-area (`LessonRepository.createLesson` throws on a duplicate).
- Check-ins are created only by `CDWorkCheckIn.make(for:on:purpose:in:)` and read with `resolvedWork(in:)`.
- Work is only for enrolled children (`WorkRepository.createWork`).
- An observation on a presentation is scoped to specific children (`NoteScope.forSelection`), never `.all`.
- Old-record cleanup runs only through Settings › Sync and backup › Clean Up Leftovers (`NotebookJunkCleanup`), which previews and backs up first.
