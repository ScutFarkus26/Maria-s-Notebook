# Performance Audit: Query Patterns

**Date:** Audit conducted on repository-wide SwiftData query patterns  
**Purpose:** Identify high-risk query patterns that load entire tables into memory

---

## Executive Summary

This audit identifies **25+ locations** with unfiltered queries loading entire tables. The highest-risk areas are:

**✅ COMPLETED OPTIMIZATIONS:**
1. ✅ **Settings/SettingsView.swift** - **OPTIMIZED** - Now uses `SettingsStatsViewModel` for efficient statistics loading
2. ✅ **AppCore/RootView.swift** - **OPTIMIZED** - Backfill operations moved to `AppBootstrapper` and are now async with batch processing
3. ✅ **Work/WorksAgendaView.swift** - **OPTIMIZED** - Uses filtered queries, lazy loading, and lightweight change detection
4. ✅ **Presentations/PresentationHistoryView.swift** - **OPTIMIZED** - Implements pagination (loads 50 at a time)

**⚠️ REMAINING HIGH-RISK AREAS:**
1. **Tests/CloudKitStatusView.swift** - Loads ALL 14 model types (HIGH) - Test/debug view, lower priority
2. **Inbox/FollowUpInboxView.swift** - 7 unfiltered queries (HIGH)
3. **Work/WorkContractDetailSheet.swift** - 6 unfiltered queries (HIGH)
4. **Students/StudentLessonsRootView.swift** - 3 large join tables (HIGH)
5. **Planning/PlanningWeekView.swift** - 3 large join tables (HIGH)
6. **Presentations/PresentationsViewModel.swift** - Loads all StudentLesson, Lesson, Student (HIGH) - Algorithmic requirement
7. **Backup/BackupService.swift** - Multiple unfiltered fetches for backup (MED - expected)
8. **Services/DataMigrations.swift** - Unfiltered fetches for migrations (MED - expected, now async with batching)

---

## 1. Unfiltered @Query Usage

### High Risk: Multiple Unfiltered Queries in Single View

#### Tests/CloudKitStatusView.swift
- **Symbol:** `CloudKitStatusView` (View)
- **Queries:** 
  - `@Query private var students: [Student]` (unfiltered)
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var studentLessons: [StudentLesson]` (unfiltered)
  - `@Query private var workContracts: [WorkContract]` (unfiltered)
  - `@Query private var workPlanItems: [WorkPlanItem]` (unfiltered)
  - `@Query private var workCompletionRecords: [WorkCompletionRecord]` (unfiltered)
  - `@Query private var attendanceRecords: [AttendanceRecord]` (unfiltered)
  - `@Query private var notes: [Note]` (unfiltered)
  - `@Query private var scopedNotes: [ScopedNote]` (unfiltered)
  - `@Query private var projects: [Project]` (unfiltered)
  - `@Query private var projectSessions: [ProjectSession]` (unfiltered)
  - `@Query private var presentations: [Presentation]` (unfiltered)
  - `@Query private var studentMeetings: [StudentMeeting]` (unfiltered)
  - `@Query private var communityTopics: [CommunityTopic]` (unfiltered)
- **Risk:** **HIGH** - Loads ALL 14 model types. Test/debug view, but still problematic if accessed with large dataset.

#### Settings/SettingsView.swift
- **Symbol:** `SettingsView` (View)
- **Status:** ✅ **OPTIMIZED**
- **Implementation:** Now uses `SettingsStatsViewModel` which loads counts efficiently using `FetchDescriptor` with `includesPendingChanges: false` for read-only analytics queries
- **Queries:** No longer uses unfiltered @Query for statistics - uses ViewModel with targeted fetches
- **Risk:** ✅ **RESOLVED** - Statistics are now loaded efficiently without loading entire tables

#### Inbox/FollowUpInboxView.swift
- **Symbol:** `FollowUpInboxView` (View)
- **Queries:**
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var students: [Student]` (unfiltered)
  - `@Query private var studentLessons: [StudentLesson]` (unfiltered)
  - `@Query private var contracts: [WorkContract]` (unfiltered)
  - `@Query private var planItems: [WorkPlanItem]` (unfiltered)
  - `@Query private var notes: [ScopedNote]` (unfiltered)
  - `@Query(filter: #Predicate<WorkNote> { $0.isLessonToGive == true }, sort: [...]) private var lessonReminderNotes: [WorkNote]` (filtered)
- **Risk:** **HIGH** - Loads 6 entire tables. Used for filtering/follow-up logic, but likely only needs subsets.

#### Work/WorkContractDetailSheet.swift
- **Symbol:** `WorkContractDetailSheet` (View)
- **Queries:**
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var students: [Student]` (unfiltered)
  - `@Query private var workNotes: [ScopedNote]` (unfiltered)
  - `@Query private var presentations: [Presentation]` (unfiltered)
  - `@Query private var planItems: [WorkPlanItem]` (unfiltered)
  - `@Query private var peerContracts: [WorkContract]` (unfiltered)
- **Risk:** **HIGH** - Sheet view that loads 6 entire tables. Only needs data related to the single contract being viewed.

#### Students/StudentLessonsRootView.swift
- **Symbol:** `StudentLessonsRootView` (View)
- **Queries:**
  - `@Query private var studentLessons: [StudentLesson]` (unfiltered)
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var students: [Student]` (unfiltered)
- **Risk:** **HIGH** - Loads all StudentLesson (join table between Student and Lesson), plus all Lessons and Students. Filters in memory by subject/completion status. Should filter at database level.

#### Planning/PlanningWeekView.swift
- **Symbol:** `PlanningWeekView` (View)
- **Queries:**
  - `@Query private var studentLessons: [StudentLesson]` (unfiltered)
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var students: [Student]` (unfiltered)
- **Risk:** **HIGH** - Loads all StudentLesson, Lesson, and Student tables. Filters in memory for week view. Should filter by date range at database level.

#### Projects/ProjectDetailView.swift
- **Symbol:** `ProjectDetailView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var students: [Student]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectRole.createdAt, order: .forward)]) private var allRoles: [ProjectRole]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectTemplateWeek.weekIndex, order: .forward)]) private var allWeeks: [ProjectTemplateWeek]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [ProjectWeekRoleAssignment]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectSession.createdAt, order: .forward)]) private var allSessions: [ProjectSession]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectAssignmentTemplate.createdAt, order: .forward)]) private var allTemplates: [ProjectAssignmentTemplate]` (unfiltered, sorted)
  - `@Query private var contracts: [WorkContract]` (unfiltered)
- **Risk:** **MED-HIGH** - Loads all project-related tables plus all Students. Filters roles by `projectID` in memory (line 18). Should filter by project at database level.

#### Projects/NewProjectSessionSheet.swift
- **Symbol:** `NewProjectSessionSheet` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\ProjectTemplateWeek.weekIndex, order: .forward)]) private var allTemplateWeeks: [ProjectTemplateWeek]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectRole.createdAt, order: .forward)]) private var allRoles: [ProjectRole]` (unfiltered, sorted)
  - `@Query private var allStudentLessons: [StudentLesson]` (unfiltered)
- **Risk:** **HIGH** - Loads all StudentLesson table plus project tables. Should filter by project.

#### Components/OpenWorkListView.swift
- **Symbol:** `OpenWorkListView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\WorkModel.createdAt, order: .reverse)]) private var allWorks: [WorkModel]` (unfiltered, sorted)
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var studentLessons: [StudentLesson]` (unfiltered)
- **Risk:** **MED-HIGH** - Loads all WorkModel, Lesson, and StudentLesson. Filters `allWorks` in memory for `isOpen`. Should filter at database level.

#### Students/StudentLessonDetailView.swift
- **Symbol:** `StudentLessonDetailView` (View)
- **Queries:**
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var studentsAll: [Student]` (unfiltered)
  - `@Query private var studentLessonsAll: [StudentLesson]` (unfiltered)
- **Risk:** **HIGH** - Detail view for a single StudentLesson loads ALL lessons, students, and studentLessons. Only needs data related to the current lesson.

#### Students/StudentLessonPill.swift
- **Symbol:** `StudentLessonPill` (View)
- **Queries:**
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var students: [Student]` (unfiltered)
- **Risk:** **MED** - Component view loads all Lessons and Students. Should receive data as parameters or fetch specific items.

#### Presentations/PresentationDetailSheet.swift
- **Symbol:** `PresentationDetailSheet` (View)
- **Queries:**
  - `@Query private var lessons: [Lesson]` (unfiltered)
  - `@Query private var students: [Student]` (unfiltered)
- **Risk:** **MED** - Sheet for single presentation loads all Lessons and Students. Should fetch specific items.

#### Presentations/PresentationsInboxView.swift
- **Symbol:** `PresentationsInboxView` (View)
- **Queries:**
  - `@Query private var studentLessons: [StudentLesson]` (unfiltered)
- **Risk:** **HIGH** - Loads all StudentLesson. Filters for unscheduled in memory.

#### Presentations/PresentationHistoryView.swift
- **Symbol:** `PresentationHistoryView` (View)
- **Status:** ✅ **OPTIMIZED** - Implements pagination
- **Implementation:** 
  - Loads presentations in batches (initial: 50, load more: 50)
  - Uses `FetchDescriptor` with `fetchLimit` for pagination
  - Uses lightweight `@Query` for change detection only (extracts IDs)
- **Queries:**
  - Paginated `FetchDescriptor<Presentation>` (loads 50 at a time)
  - `@Query` for change detection only (extracts IDs, doesn't retain full objects)
  - `@Query private var lessons: [Lesson]` (unfiltered) - Still loads all for lookup
  - `@Query private var students: [Student]` (unfiltered) - Still loads all for lookup
- **Risk:** **MED** - Pagination implemented for presentations. Lessons and Students still loaded for lookup (may be acceptable for small datasets).

#### Presentations/PresentationsCalendarStrip.swift
- **Symbol:** `PresentationsCalendarStrip` (View)
- **Queries:**
  - `@Query private var studentLessons: [StudentLesson]` (unfiltered)
- **Risk:** **MED-HIGH** - Component loads all StudentLesson to find earliest date. Should use targeted query.

#### Agenda/DayColumn.swift
- **Symbol:** `DayColumn` (View)
- **Queries:**
  - `@Query private var studentLessons: [StudentLesson]` (unfiltered)
  - `@Query(sort: [SortDescriptor(\Student.lastName), SortDescriptor(\Student.firstName)]) private var allStudents: [Student]` (unfiltered, sorted)
- **Risk:** **MED-HIGH** - Column component loads all StudentLesson and Students. Should filter by day.

#### Components/DaysSinceLastLessonView.swift
- **Symbol:** `DaysSinceLastLessonView` (View)
- **Queries:**
  - `@Query(sort: [...]) private var studentLessons: [StudentLesson]` (filtered, sorted)
  - `@Query private var lessons: [Lesson]` (unfiltered)
- **Risk:** **MED** - Loads all Lessons. Should fetch only needed lessons.

#### Components/OpenWorkGrid.swift
- **Symbol:** `OpenWorkGrid` (View)
- **Queries:**
  - `@Query private var planItems: [WorkPlanItem]` (unfiltered)
- **Risk:** **MED** - Component loads all WorkPlanItem. Should filter by contract/date.

#### Students/StudentLessonDraftSheet.swift
- **Symbol:** `StudentLessonDraftSheet` (View)
- **Queries:**
  - `@Query private var matches: [StudentLesson]` (unfiltered)
- **Risk:** **MED** - Loads all StudentLesson to find matches. Should use targeted query.

#### Students/StudentsView.swift
- **Symbol:** `StudentsView` (View)
- **Queries:**
  - `@Query private var students: [Student]` (unfiltered) - OK (needed for roster)
  - `@Query(sort: [SortDescriptor(\AttendanceRecord.id)]) private var attendanceRecordsForChangeDetection: [AttendanceRecord]` (unfiltered, sorted) - Used for change detection only
  - `@Query(sort: [SortDescriptor(\StudentLesson.id)]) private var studentLessonsForChangeDetection: [StudentLesson]` (unfiltered, sorted) - Used for change detection only
  - `@Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]` (unfiltered, sorted) - Used for change detection only
- **Risk:** **MED** - Has optimizations (only extracts IDs), but still loads full objects initially. Could use lighter-weight change detection.

#### Work/WorksAgendaView.swift
- **Symbol:** `WorksAgendaView` (View)
- **Status:** ✅ **OPTIMIZED**
- **Implementation:**
  - Uses filtered `@Query` for open contracts only (active/review status)
  - Lightweight change detection queries (extracts IDs only, doesn't retain full objects)
  - Lazy-loads lessons and students on-demand based on displayed contracts
  - Caches loaded data to avoid repeated fetches
  - Added debouncing to search field (250ms delay)
- **Queries:**
  - `@Query(filter: #Predicate<WorkContract> { $0.statusRaw == "active" || $0.statusRaw == "review" })` - ✅ Filtered
  - `@Query(sort: [SortDescriptor(\Lesson.id)])` - ✅ Change detection only (extracts IDs)
  - `@Query(sort: [SortDescriptor(\Student.id)])` - ✅ Change detection only (extracts IDs)
- **Risk:** ✅ **RESOLVED** - Optimized with filtered queries, lazy loading, and lightweight change detection.

#### Students/StudentMeetingsTab.swift
- **Symbol:** `StudentMeetingsTab` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\WorkContract.createdAt, order: .reverse)]) private var contracts: [WorkContract]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)]) private var meetings: [StudentMeeting]` (unfiltered, sorted)
- **Risk:** **MED-HIGH** - Loads all WorkContract, Lesson, and StudentMeeting. Should filter by student.

#### Attendance/AttendanceView.swift
- **Symbol:** `AttendanceView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\Student.lastName), SortDescriptor(\Student.firstName)]) private var students: [Student]` (unfiltered, sorted)
- **Risk:** **LOW-MED** - Loads all Students. May be acceptable if all students are needed for attendance.

#### Community/CommunityMeetingsView.swift
- **Symbol:** `CommunityMeetingsView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\CommunityTopic.createdAt, order: .reverse)]) private var topics: [CommunityTopic]` (unfiltered, sorted)
- **Risk:** **LOW** - CommunityTopic is likely a small table.

#### Projects/ProjectsRootView.swift
- **Symbol:** `ProjectsRootView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var clubs: [Project]` (unfiltered, sorted)
- **Risk:** **LOW-MED** - Projects table likely small. Has manual fetches in delete logic (lines 164-197) that load all related tables.

#### Projects/ProjectRolesEditorView.swift
- **Symbol:** `ProjectRolesEditorView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor<ProjectRole>(\.createdAt, order: .forward)]) private var roles: [ProjectRole]` (unfiltered, sorted)
- **Risk:** **MED** - Loads all ProjectRole. Should filter by project.

#### Projects/ProjectWeeksEditorView.swift
- **Symbol:** `ProjectWeeksEditorView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor<ProjectTemplateWeek>(\.weekIndex, order: .forward)]) private var allWeeks: [ProjectTemplateWeek]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [ProjectWeekRoleAssignment]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\Student.firstName, order: .forward), SortDescriptor(\Student.lastName, order: .forward)]) private var students: [Student]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectRole.createdAt, order: .forward)]) private var allRoles: [ProjectRole]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\ProjectWeekRoleAssignment.createdAt, order: .forward)]) private var allRoleAssignments: [ProjectWeekRoleAssignment]` (unfiltered, sorted) - duplicate?
  - `@Query(sort: [SortDescriptor(\Lesson.name, order: .forward)]) private var allLessons: [Lesson]` (unfiltered, sorted)
- **Risk:** **HIGH** - Loads all Project tables plus all Students and Lessons. Should filter by project.

#### Projects/ProjectSessionDetailView.swift
- **Symbol:** `ProjectSessionDetailView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var students: [Student]` (unfiltered, sorted)
  - `@Query(sort: [SortDescriptor(\Lesson.name)]) private var lessons: [Lesson]` (unfiltered, sorted)
  - `@Query private var allWorkContracts: [WorkContract]` (unfiltered)
- **Risk:** **MED-HIGH** - Loads all Students, Lessons, and WorkContract. Should filter by project/session.

#### Projects/ProjectEditorSheet.swift
- **Symbol:** `ProjectEditorSheet` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)]) private var students: [Student]` (unfiltered, sorted)
- **Risk:** **MED** - Loads all Students. May be acceptable for picker, but could use search/filter.

#### Work/WorksLogView.swift
- **Symbol:** `WorksLogView` (View)
- **Queries:**
  - `@Query(sort: [SortDescriptor(\WorkContract.createdAt, order: .reverse)]) private var contracts: [WorkContract]` (unfiltered, sorted)
  - `@Query(...)` (line 8 - incomplete in grep)
  - `@Query(...)` (line 11 - incomplete in grep)
- **Risk:** **MED** - Loads all WorkContract. May be acceptable for log view, but could paginate.

---

## 2. Manual FetchDescriptor Unfiltered Fetches

### High Risk: ViewModels and Services

#### Presentations/PresentationsViewModel.swift
- **Symbol:** `PresentationsViewModel` (ViewModel)
- **Location:** `init()` method (lines 72-91)
- **Fetches:**
  - `FetchDescriptor<StudentLesson>()` - unfiltered (loads all)
  - `FetchDescriptor<Lesson>()` - unfiltered (loads all)
  - `FetchDescriptor<Student>()` - unfiltered (loads all)
  - `FetchDescriptor<WorkContract>(...)` - filtered (active/review only) - GOOD
- **Risk:** **HIGH** - ViewModel loads ALL StudentLesson, Lesson, and Student in init. Comments indicate algorithmic requirement (blocking logic, days-since calculations), but this is still problematic.

#### AppCore/AppBootstrapper.swift
- **Symbol:** `AppBootstrapper` (Service)
- **Status:** ✅ **OPTIMIZED** - Backfill operations moved from RootView to AppBootstrapper
- **Location:** `AppBootstrapper.bootstrap()` method (lines 46-50)
- **Implementation:**
  - All three backfill functions are now `async`
  - Process in batches (1000 items per batch) to reduce memory spikes
  - Use `await Task.yield()` periodically to prevent UI blocking
  - Run during app bootstrap, not blocking UI
- **Fetches:**
  - `FetchDescriptor<StudentLesson>()` - unfiltered (for migrations, but now async with batching)
  - `FetchDescriptor<Student>()` - unfiltered (for migrations, but now async with batching)
  - `FetchDescriptor<Lesson>()` - unfiltered (for migrations, but now async with batching)
- **Risk:** ✅ **RESOLVED** - Operations are async and don't block UI. Batch processing reduces memory spikes.

#### ViewModels/TodayViewModel.swift
- **Symbol:** `TodayViewModel` (ViewModel)
- **Location:** `reload()` method and fallback paths
- **Fetches:**
  - Uses targeted fetches with predicates (GOOD)
  - Fallback paths load all: `FetchDescriptor<Student>()` (line 206), `FetchDescriptor<Lesson>()` (line 232)
- **Risk:** **MED** - Main path is optimized, but fallback paths load all. Should improve predicate support or handle errors differently.

#### Students/StudentsView.swift
- **Symbol:** `StudentsView` (View)
- **Location:** `loadDataForMode()` method (lines 636, 649, 662)
- **Fetches:**
  - `FetchDescriptor<AttendanceRecord>()` - unfiltered (fallback)
  - `FetchDescriptor<StudentLesson>()` - unfiltered (fallback)
  - `FetchDescriptor<Lesson>()` - unfiltered (fallback)
- **Risk:** **MED** - Fallback paths load all if predicate fails. Main path uses targeted queries.

#### Students/StudentsRootView.swift
- **Symbol:** `StudentsRootView` (View)
- **Location:** `loadWorkloadData()` fallback (lines 143, 162)
- **Fetches:**
  - `FetchDescriptor<Student>()` - unfiltered (fallback)
  - `FetchDescriptor<Lesson>()` - unfiltered (fallback)
- **Risk:** **MED** - Fallback paths load all. Main path is optimized.

#### Lessons/LessonsRootView.swift
- **Symbol:** `LessonsRootView` (View)
- **Location:** `loadStudentLessonsForLesson()` (line 585)
- **Fetches:**
  - `FetchDescriptor<StudentLesson>()` - unfiltered (fallback)
- **Risk:** **MED** - Fallback path loads all. Main path uses targeted query.

#### Students/StudentDetailViewModel.swift
- **Symbol:** `StudentDetailViewModel` (ViewModel)
- **Location:** `loadLessons()` fallback (line 70)
- **Fetches:**
  - `FetchDescriptor<Lesson>()` - unfiltered (fallback)
- **Risk:** **MED** - Fallback path loads all. Main path is optimized.

#### Work/WorksAgendaView.swift
- **Symbol:** `WorksAgendaView` (View)
- **Location:** `loadLessonsAndStudentsIfNeeded()` fallback (lines 63, 81)
- **Fetches:**
  - `FetchDescriptor<Lesson>()` - unfiltered (fallback)
  - `FetchDescriptor<Student>()` - unfiltered (fallback)
- **Risk:** **MED** - Fallback paths load all. Main path is optimized.

#### Components/ClassSubjectChecklistView.swift
- **Symbol:** `ClassSubjectChecklistView` (View)
- **Location:** Multiple methods (lines 282, 300, 326)
- **Fetches:**
  - `FetchDescriptor<Lesson>()` - unfiltered (multiple locations)
  - `FetchDescriptor<WorkContract>()` - unfiltered
- **Risk:** **MED-HIGH** - Component loads all Lessons and WorkContract. Should filter by subject/class.

#### Projects/ProjectsRootView.swift
- **Symbol:** `ProjectsRootView` (View)
- **Location:** `deleteClub()` method (lines 164-197)
- **Fetches:**
  - `FetchDescriptor<ProjectSession>()` - unfiltered
  - `FetchDescriptor<WorkContract>()` - unfiltered
  - `FetchDescriptor<ProjectAssignmentTemplate>()` - unfiltered
  - `FetchDescriptor<ProjectRole>()` - unfiltered
  - `FetchDescriptor<ProjectTemplateWeek>()` - unfiltered
  - `FetchDescriptor<ProjectWeekRoleAssignment>()` - unfiltered
- **Risk:** **HIGH** - Delete operation loads ALL related project tables. Should filter by project ID.

#### Work/WorkAgendaCalendarPane.swift
- **Symbol:** `WorkAgendaCalendarPane` (View)
- **Location:** Multiple methods (line 245)
- **Fetches:**
  - `FetchDescriptor<WorkPlanItem>()` - unfiltered
- **Risk:** **MED** - Loads all WorkPlanItem. Should filter by date/contract.

### Medium Risk: Service/Migration Code (Expected but Documented)

#### Services/DataMigrations.swift
- **Symbol:** Various migration functions
- **Fetches:** Multiple unfiltered fetches for migration logic
- **Risk:** **MED** - Expected for migrations, but should be documented and potentially batched.

#### Backup/BackupService.swift
- **Symbol:** `BackupService` (Service)
- **Fetches:** Multiple unfiltered fetches for backup operations
- **Risk:** **MED** - Expected for backup, but uses generic `FetchDescriptor<T>()` pattern.

#### Services/LifecycleService.swift
- **Symbol:** `LifecycleService` (Service)
- **Location:** `initializeNextLessons()` (line 31)
- **Fetches:**
  - `FetchDescriptor<Student>()` - unfiltered
- **Risk:** **MED** - Service operation that needs all students. May be acceptable.

#### Settings/DebugMaintenanceTasks.swift
- **Symbol:** Various maintenance functions
- **Fetches:** Unfiltered fetches for maintenance operations
- **Risk:** **LOW-MED** - Debug/maintenance code, expected to load all.

---

## 3. Top 10 Screens Likely to be Slow

### 1. Tests/CloudKitStatusView.swift
- **Risk:** HIGH
- **Reason:** Loads ALL 14 model types with unfiltered @Query
- **Impact:** Memory usage and load time will scale with total records across all tables

### 2. ✅ Settings/SettingsView.swift - OPTIMIZED
- **Risk:** ✅ RESOLVED
- **Reason:** Now uses `SettingsStatsViewModel` with efficient count queries
- **Impact:** ✅ Statistics load efficiently without loading entire tables

### 3. Inbox/FollowUpInboxView.swift
- **Risk:** HIGH
- **Reason:** 6 unfiltered queries (Lesson, Student, StudentLesson, WorkContract, WorkPlanItem, ScopedNote)
- **Impact:** Loads entire work/lesson ecosystem for inbox calculations

### 4. Students/StudentLessonsRootView.swift
- **Risk:** HIGH
- **Reason:** 3 unfiltered queries for join table (StudentLesson) + related tables (Lesson, Student)
- **Impact:** StudentLesson is typically the largest table (many-to-many relationship)

### 5. Planning/PlanningWeekView.swift
- **Risk:** HIGH
- **Reason:** 3 unfiltered queries, filters in memory for week view
- **Impact:** Loads all StudentLesson, Lesson, Student, then filters by date range in Swift

### 6. Work/WorkContractDetailSheet.swift
- **Risk:** HIGH
- **Reason:** 6 unfiltered queries in a sheet/detail view
- **Impact:** Sheet loads entire tables just to display details for one contract

### 7. Presentations/PresentationsViewModel.swift
- **Risk:** HIGH
- **Reason:** ViewModel init loads ALL StudentLesson, Lesson, Student
- **Impact:** Initialization blocks until all records load; used by PresentationsView

### 8. Projects/ProjectDetailView.swift
- **Risk:** MED-HIGH
- **Reason:** 7 unfiltered queries, filters project data in memory
- **Impact:** Loads all project-related tables + all Students, filters by projectID in Swift

### 9. Projects/ProjectWeeksEditorView.swift
- **Risk:** HIGH
- **Reason:** 6 unfiltered queries including all Students and Lessons
- **Impact:** Editor component loads entire database for editing

### 10. Students/StudentLessonDetailView.swift
- **Risk:** HIGH
- **Reason:** Detail view for ONE StudentLesson loads ALL lessons, students, studentLessons
- **Impact:** Detail sheet loads entire database for single-item view

---

## 4. Top 5 Optimization Targets

### Target 1: ✅ Settings/SettingsView.swift - COMPLETED
**Priority:** ✅ COMPLETED  
**Impact:** ✅ High - Settings is accessed frequently  
**Effort:** ✅ Low - Only needs counts, not full data  
**Strategy:** ✅ Implemented - Uses `SettingsStatsViewModel` with `FetchDescriptor` and `includesPendingChanges: false`

### Target 2: Students/StudentLessonsRootView.swift
**Priority:** HIGH  
**Impact:** High - Core navigation screen, StudentLesson is largest table  
**Effort:** Medium - Need to add predicates for subject/completion filters  
**Strategy:** Add @Query predicates for subject and completion status filters

### Target 3: Planning/PlanningWeekView.swift
**Priority:** HIGH  
**Impact:** High - Core planning screen, loads on every week navigation  
**Effort:** Medium - Need date range predicate  
**Strategy:** Add @Query predicate for date range filtering (scheduledFor within week)

### Target 4: Work/WorkContractDetailSheet.swift
**Priority:** HIGH  
**Impact:** Medium - Sheet view, but loads 6 tables  
**Effort:** Medium - Need to filter queries by contract relationships  
**Strategy:** Fetch related items by ID/relationship instead of loading all tables

### Target 5: Presentations/PresentationsViewModel.swift
**Priority:** HIGH  
**Impact:** High - ViewModel init blocks UI  
**Effort:** High - Algorithmic requirement documented, may need algorithm redesign  
**Strategy:** Investigate if blocking logic and days-since calculations truly need ALL records, or can be optimized with targeted queries and caching

---

## Patterns Identified

### Anti-Patterns Found

1. **Detail views loading entire tables** - Many detail/sheet views load all records instead of fetching related items
2. **Memory filtering** - Views load all records then filter in Swift instead of using predicates
3. **Fallback loading all** - Many optimized paths have fallbacks that load all records
4. **Change detection loading full objects** - Some views load full objects just to extract IDs for change detection
5. **Join tables loaded unfiltered** - StudentLesson (many-to-many) is often loaded entirely

### Good Patterns Found

1. ✅ **WorksAgendaView** - Uses filtered @Query for contracts, lazy loading for related items, lightweight change detection
2. ✅ **TodayViewModel** - Uses targeted FetchDescriptor with predicates (main path)
3. ✅ **SettingsStatsViewModel** - Efficient statistics loading with caching and optimized FetchDescriptors
4. ✅ **PresentationHistoryView** - Implements pagination for large datasets
5. ✅ **AppBootstrapper** - Async backfill operations with batch processing
6. **StudentsRootView** - Loads only open contracts, then fetches related students/lessons by ID
7. **PresentationsView** - Uses change detection queries with ID extraction (though still loads full objects initially)

---

## Recommendations

### Immediate Actions

1. **Add predicates to @Query** - Replace unfiltered queries with filtered ones where possible
2. **Use targeted fetches in detail views** - Fetch by ID/relationship instead of loading all
3. **Implement count queries for stats** - Settings view should use counts, not full arrays
4. **Review fallback paths** - Improve predicate support or remove fallback "load all" patterns
5. **Optimize change detection** - Use lighter-weight change detection mechanisms

### Long-term Improvements

1. **Implement pagination** - For log/history views that legitimately need many records
2. **Add query result caching** - Cache frequently accessed filtered results
3. **Review algorithmic requirements** - Investigate if algorithms truly need all records
4. **Add database-level filtering** - Move memory-based filtering to predicate-based queries
5. **Profile memory usage** - Measure actual memory impact of current patterns

---

## Notes

- **StudentLesson** is a join table between Student and Lesson - typically the largest table
- **WorkContract** and **WorkPlanItem** are frequently loaded together
- Many views load **Student** and **Lesson** tables together for lookup purposes
- **Project**-related views often load all project tables + all Students/Lessons
- Test/debug views (CloudKitStatusView) load all tables but are less critical

---

**End of Audit**

