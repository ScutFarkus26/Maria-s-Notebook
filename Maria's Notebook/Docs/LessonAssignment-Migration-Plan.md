# Migration Plan: Consolidate StudentLesson + Presentation → LessonAssignment

## Overview

This plan consolidates two overlapping models (`StudentLesson` and `Presentation`) into a single unified model called `LessonAssignment`. The migration is designed to be **safe**, **incremental**, and **reversible** at each step.

### Goals
- Single source of truth for lesson planning and history
- Proper SwiftData relationships (no more string-based foreign keys)
- Simplified codebase with less sync/repair logic
- Zero data loss
- App remains functional after each phase

### Timeline Estimate
This is a multi-week effort broken into 7 phases. Each phase results in a working, shippable app.

---

## Phase 1: Create the New Model (No Breaking Changes)

**Goal:** Add `LessonAssignment` alongside existing models. Nothing changes yet.

### Step 1.1: Create LessonAssignment Model

Create a new file `Models/LessonAssignment.swift`:

```swift
@Model
final class LessonAssignment: Identifiable {
    var id: UUID = UUID()
    var createdAt: Date = Date()

    // State machine: draft → scheduled → presented
    var stateRaw: String = LessonAssignmentState.draft.rawValue

    // Scheduling
    var scheduledFor: Date?
    var scheduledForDay: Date = Date.distantPast  // Denormalized for queries

    // Presentation (filled when state becomes .presented)
    var presentedAt: Date?

    // Snapshots (frozen when presented, for historical accuracy)
    var lessonTitleSnapshot: String?
    var lessonSubtitleSnapshot: String?

    // Planning flags
    var needsPractice: Bool = false
    var needsAnotherPresentation: Bool = false
    var followUpWork: String = ""
    var notes: String = ""

    // CloudKit-compatible foreign keys
    var lessonID: String = ""
    var studentIDs: [String] = []

    // Migration tracking
    var migratedFromStudentLessonID: String?
    var migratedFromPresentationID: String?

    // Relationships
    @Relationship var lesson: Lesson?
    @Relationship(deleteRule: .cascade, inverse: \Note.lessonAssignment)
    var unifiedNotes: [Note]? = []

    // Track integration (optional)
    var trackID: String?
    var trackStepID: String?
}

enum LessonAssignmentState: String, Codable, CaseIterable {
    case draft = "draft"           // Created but not scheduled
    case scheduled = "scheduled"   // Has a scheduled date
    case presented = "presented"   // Has been given to students
}
```

### Step 1.2: Add to Schema

Edit `AppCore/AppSchema.swift` to include the new model:

```swift
LessonAssignment.self,  // Add after Presentation.self
```

### Step 1.3: Add Note Relationship

Edit `Models/Note.swift` to add the inverse relationship:

```swift
var lessonAssignment: LessonAssignment?  // Add alongside existing studentLesson and presentation
```

### Step 1.4: Build & Test

- Run the app
- Verify it launches without crashes
- Existing features work unchanged
- New model exists in database (empty)

**Checkpoint:** App works exactly as before. New model is ready but unused.

---

## Phase 2: Create Migration Service

**Goal:** Build infrastructure to copy data from old models to new model.

### Step 2.1: Create LessonAssignmentMigrationService

Create `Services/Migrations/LessonAssignmentMigrationService.swift`:

```swift
@MainActor
final class LessonAssignmentMigrationService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Migrates all StudentLessons and Presentations to LessonAssignments.
    /// Safe to run multiple times (idempotent).
    func migrateAll() async throws -> MigrationResult {
        var result = MigrationResult()

        // Step 1: Migrate all StudentLessons
        let studentLessons = try context.fetch(FetchDescriptor<StudentLesson>())
        for sl in studentLessons {
            if try migrateStudentLesson(sl) {
                result.studentLessonsMigrated += 1
            } else {
                result.studentLessonsSkipped += 1
            }
        }

        // Step 2: Migrate Presentations that have no matching StudentLesson
        let presentations = try context.fetch(FetchDescriptor<Presentation>())
        for p in presentations {
            if try migratePresentationIfOrphaned(p) {
                result.presentationsMigrated += 1
            } else {
                result.presentationsSkipped += 1
            }
        }

        try context.save()
        return result
    }

    /// Migrates a single StudentLesson to LessonAssignment.
    /// Returns true if migrated, false if already exists.
    private func migrateStudentLesson(_ sl: StudentLesson) throws -> Bool {
        // Check if already migrated
        let existingDescriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.migratedFromStudentLessonID == sl.id.uuidString }
        )
        let existing = try context.fetch(existingDescriptor)
        if !existing.isEmpty { return false }

        // Find linked Presentation (if any)
        let presentationDescriptor = FetchDescriptor<Presentation>(
            predicate: #Predicate { $0.legacyStudentLessonID == sl.id.uuidString }
        )
        let linkedPresentation = try context.fetch(presentationDescriptor).first

        // Determine state
        let state: LessonAssignmentState
        if sl.isPresented || sl.givenAt != nil || linkedPresentation != nil {
            state = .presented
        } else if sl.scheduledFor != nil {
            state = .scheduled
        } else {
            state = .draft
        }

        // Create new LessonAssignment
        let la = LessonAssignment()
        la.id = UUID()  // New ID for clean slate
        la.createdAt = sl.createdAt
        la.stateRaw = state.rawValue
        la.scheduledFor = sl.scheduledFor
        la.scheduledForDay = sl.scheduledForDay
        la.presentedAt = linkedPresentation?.presentedAt ?? sl.givenAt
        la.lessonTitleSnapshot = linkedPresentation?.lessonTitleSnapshot
        la.lessonSubtitleSnapshot = linkedPresentation?.lessonSubtitleSnapshot
        la.needsPractice = sl.needsPractice
        la.needsAnotherPresentation = sl.needsAnotherPresentation
        la.followUpWork = sl.followUpWork
        la.notes = sl.notes
        la.lessonID = sl.lessonID
        la.studentIDs = sl.studentIDs
        la.lesson = sl.lesson
        la.trackID = linkedPresentation?.trackID
        la.trackStepID = linkedPresentation?.trackStepID

        // Track migration source
        la.migratedFromStudentLessonID = sl.id.uuidString
        la.migratedFromPresentationID = linkedPresentation?.id.uuidString

        context.insert(la)
        return true
    }

    /// Migrates orphaned Presentations (no linked StudentLesson).
    private func migratePresentationIfOrphaned(_ p: Presentation) throws -> Bool {
        // Skip if has a linked StudentLesson (already migrated via that path)
        if let legacyID = p.legacyStudentLessonID, !legacyID.isEmpty {
            let slDescriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { $0.id.uuidString == legacyID }
            )
            let linkedSL = try context.fetch(slDescriptor)
            if !linkedSL.isEmpty { return false }
        }

        // Check if already migrated
        let existingDescriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.migratedFromPresentationID == p.id.uuidString }
        )
        let existing = try context.fetch(existingDescriptor)
        if !existing.isEmpty { return false }

        // Create new LessonAssignment
        let la = LessonAssignment()
        la.id = UUID()
        la.createdAt = p.createdAt
        la.stateRaw = LessonAssignmentState.presented.rawValue
        la.presentedAt = p.presentedAt
        la.lessonTitleSnapshot = p.lessonTitleSnapshot
        la.lessonSubtitleSnapshot = p.lessonSubtitleSnapshot
        la.lessonID = p.lessonID
        la.studentIDs = p.studentIDs
        la.trackID = p.trackID
        la.trackStepID = p.trackStepID
        la.migratedFromPresentationID = p.id.uuidString

        context.insert(la)
        return true
    }
}

struct MigrationResult {
    var studentLessonsMigrated = 0
    var studentLessonsSkipped = 0
    var presentationsMigrated = 0
    var presentationsSkipped = 0
}
```

### Step 2.2: Add Validation Service

Create `Services/Migrations/LessonAssignmentMigrationValidator.swift`:

```swift
@MainActor
final class LessonAssignmentMigrationValidator {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Validates that migration preserved all data correctly.
    func validate() async throws -> ValidationResult {
        var result = ValidationResult()

        let studentLessons = try context.fetch(FetchDescriptor<StudentLesson>())
        let presentations = try context.fetch(FetchDescriptor<Presentation>())
        let lessonAssignments = try context.fetch(FetchDescriptor<LessonAssignment>())

        result.totalStudentLessons = studentLessons.count
        result.totalPresentations = presentations.count
        result.totalLessonAssignments = lessonAssignments.count

        // Check each StudentLesson has a corresponding LessonAssignment
        for sl in studentLessons {
            let matchDescriptor = FetchDescriptor<LessonAssignment>(
                predicate: #Predicate { $0.migratedFromStudentLessonID == sl.id.uuidString }
            )
            let matches = try context.fetch(matchDescriptor)
            if matches.isEmpty {
                result.unmatchedStudentLessons.append(sl.id)
            }
        }

        // Check each Presentation is accounted for
        for p in presentations {
            let matchDescriptor = FetchDescriptor<LessonAssignment>(
                predicate: #Predicate {
                    $0.migratedFromPresentationID == p.id.uuidString ||
                    $0.migratedFromStudentLessonID == p.legacyStudentLessonID
                }
            )
            let matches = try context.fetch(matchDescriptor)
            if matches.isEmpty {
                result.unmatchedPresentations.append(p.id)
            }
        }

        return result
    }
}

struct ValidationResult {
    var totalStudentLessons = 0
    var totalPresentations = 0
    var totalLessonAssignments = 0
    var unmatchedStudentLessons: [UUID] = []
    var unmatchedPresentations: [UUID] = []

    var isValid: Bool {
        unmatchedStudentLessons.isEmpty && unmatchedPresentations.isEmpty
    }
}
```

### Step 2.3: Build & Test

- Write unit tests for migration service
- Test with sample data
- Verify idempotency (running twice produces same result)

**Checkpoint:** Migration infrastructure ready. Not yet running automatically.

---

## Phase 3: Run Migration at App Launch

**Goal:** Automatically migrate existing data on app launch.

### Step 3.1: Integrate into AppBootstrapper

Edit `AppCore/AppBootstrapper.swift` to add migration step:

```swift
// In the bootstrap sequence, after existing migrations:
let migrationService = LessonAssignmentMigrationService(context: context)
let result = try await migrationService.migrateAll()
logger.info("LessonAssignment migration: \(result.studentLessonsMigrated) StudentLessons, \(result.presentationsMigrated) Presentations migrated")

// Validate
let validator = LessonAssignmentMigrationValidator(context: context)
let validation = try await validator.validate()
if !validation.isValid {
    logger.error("Migration validation failed: \(validation.unmatchedStudentLessons.count) StudentLessons, \(validation.unmatchedPresentations.count) Presentations unmatched")
}
```

### Step 3.2: Add UserDefaults Flag

Track migration completion:

```swift
// In UserDefaultsKeys.swift
static let lessonAssignmentMigrationComplete = "lessonAssignmentMigrationComplete"
static let lessonAssignmentMigrationVersion = "lessonAssignmentMigrationVersion"
```

### Step 3.3: Build & Test

- Launch app with existing data
- Verify migration runs successfully
- Check LessonAssignment records match expected count
- Verify old data still exists (not deleted)

**Checkpoint:** Data exists in both old and new models. App uses old models.

---

## Phase 4: Create Parallel Read Layer

**Goal:** Add services that can read from either model, preparing for switch.

### Step 4.1: Create LessonAssignmentRepository

Create `Repositories/LessonAssignmentRepository.swift` with same API as `StudentLessonRepository`:

```swift
@MainActor
final class LessonAssignmentRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Queries

    func fetchAll() throws -> [LessonAssignment] {
        try context.fetch(FetchDescriptor<LessonAssignment>())
    }

    func fetchDrafts() throws -> [LessonAssignment] {
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw == "draft" }
        )
        return try context.fetch(descriptor)
    }

    func fetchScheduled(for date: Date) throws -> [LessonAssignment] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.scheduledForDay == startOfDay }
        )
        return try context.fetch(descriptor)
    }

    func fetchPresented() throws -> [LessonAssignment] {
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { $0.stateRaw == "presented" }
        )
        return try context.fetch(descriptor)
    }

    // MARK: - Mutations

    func createDraft(lessonID: UUID, studentIDs: [UUID]) -> LessonAssignment {
        let la = LessonAssignment()
        la.lessonID = lessonID.uuidString
        la.studentIDs = studentIDs.map { $0.uuidString }
        la.stateRaw = LessonAssignmentState.draft.rawValue
        context.insert(la)
        return la
    }

    func schedule(_ assignment: LessonAssignment, for date: Date) {
        assignment.scheduledFor = date
        assignment.scheduledForDay = Calendar.current.startOfDay(for: date)
        assignment.stateRaw = LessonAssignmentState.scheduled.rawValue
    }

    func markPresented(_ assignment: LessonAssignment, at date: Date = Date()) {
        assignment.presentedAt = date
        assignment.stateRaw = LessonAssignmentState.presented.rawValue

        // Snapshot lesson info
        if let lesson = assignment.lesson {
            assignment.lessonTitleSnapshot = lesson.name
            assignment.lessonSubtitleSnapshot = lesson.subtitle
        }
    }

    func delete(_ assignment: LessonAssignment) {
        context.delete(assignment)
    }
}
```

### Step 4.2: Build & Test

- Write unit tests for new repository
- Verify queries return expected results
- Compare counts with old repository

**Checkpoint:** New repository ready. Not yet used by UI.

---

## Phase 5: Switch Views One-by-One

**Goal:** Migrate each view from old models to new model, one at a time.

This is the longest phase. Each step migrates one view or feature.

### Step 5.1: Create Feature Flag

```swift
// In UserDefaultsKeys.swift
static let useLessonAssignmentModel = "useLessonAssignmentModel"
```

### Step 5.2: Migration Order (Lowest Risk First)

1. **PresentationHistoryView** - Read-only, lowest risk
2. **PresentationsInboxView** - Drafts list
3. **PresentationsCalendarStrip** - Calendar display
4. **PresentationsView** - Main presentations screen
5. **StudentLessonsRootView** - Student's lesson list
6. **StudentLessonDetailView** - Lesson detail screen
7. **WorksLogView** - Work log display
8. **PlanningWeekViewMac** - Planning calendar

### Step 5.3: Example Migration (PresentationHistoryView)

For each view:

1. **Create adapter** that reads from LessonAssignment but returns same data shape
2. **Add feature flag check** to switch between old and new
3. **Test thoroughly** with both flag states
4. **Remove old code path** once verified

Example for PresentationHistoryView:

```swift
// Before: @Query private var presentations: [Presentation]
// After:
@Query(sort: \LessonAssignment.presentedAt, order: .reverse)
private var lessonAssignments: [LessonAssignment]

private var presentedAssignments: [LessonAssignment] {
    lessonAssignments.filter { $0.state == .presented }
}
```

### Step 5.4: Update LifecycleService

The most critical change. Update `recordPresentationAndExplodeWork()` to:

1. Create/update LessonAssignment instead of Presentation
2. Keep creating LessonPresentation records (unchanged)
3. Keep creating WorkModel records (unchanged)

### Step 5.5: Update BlockingAlgorithmEngine

Update to read from LessonAssignment instead of both StudentLesson and Presentation.

### Step 5.6: Build & Test After Each View

- Verify view displays correctly
- Test all interactions (create, edit, delete)
- Verify data persists after app restart
- Test with CloudKit sync if enabled

**Checkpoint:** All views migrated. Old models still exist but unused.

---

## Phase 6: Update Backup/Restore

**Goal:** Update backup system to use new model.

### Step 6.1: Create LessonAssignmentDTO

Add to `Backup/BackupTypes.swift`:

```swift
struct LessonAssignmentDTO: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let stateRaw: String
    let scheduledFor: Date?
    let scheduledForDay: Date
    let presentedAt: Date?
    let lessonTitleSnapshot: String?
    let lessonSubtitleSnapshot: String?
    let needsPractice: Bool
    let needsAnotherPresentation: Bool
    let followUpWork: String
    let notes: String
    let lessonID: String
    let studentIDs: [String]
    let trackID: String?
    let trackStepID: String?
}
```

### Step 6.2: Update BackupPayload

Add new field while keeping old ones for backward compatibility:

```swift
struct BackupPayload: Codable {
    // Existing (keep for backward compatibility)
    var studentLessons: [StudentLessonDTO]?
    var presentations: [PresentationDTO]?

    // New
    var lessonAssignments: [LessonAssignmentDTO]?

    // Version tracking
    var schemaVersion: Int = 2  // Bump version
}
```

### Step 6.3: Update BackupDTOTransformers

Add transformers for LessonAssignment:

```swift
func toDTO(_ assignment: LessonAssignment) -> LessonAssignmentDTO { ... }
func fromDTO(_ dto: LessonAssignmentDTO) -> LessonAssignment { ... }
```

### Step 6.4: Update BackupEntityImporter

Add import logic that handles both old and new formats:

```swift
func importLessonAssignments(_ dtos: [LessonAssignmentDTO], using context: ModelContext) throws {
    // Import new format
}

func importLegacyStudentLessonsAndPresentations(
    studentLessons: [StudentLessonDTO]?,
    presentations: [PresentationDTO]?,
    using context: ModelContext
) throws {
    // Convert old format to new LessonAssignment records
}
```

### Step 6.5: Build & Test

- Create backup with new format
- Restore backup and verify data
- Test restoring old backup format (backward compatibility)

**Checkpoint:** Backup system updated. Can handle both old and new formats.

---

## Phase 7: Cleanup

**Goal:** Remove old models and migration code.

**IMPORTANT:** Only proceed with this phase after:
- Running new code in production for several weeks
- Confirming no data issues
- All users have migrated (CloudKit sync complete)

### Step 7.1: Remove Old Models

1. Delete `StudentLessonModel.swift`
2. Delete `Presentations/Presentation.swift`
3. Remove from `AppSchema.swift`
4. Remove related files (StudentLessonRepository, etc.)

### Step 7.2: Remove Migration Tracking Fields

Remove from LessonAssignment:
- `migratedFromStudentLessonID`
- `migratedFromPresentationID`

### Step 7.3: Remove Legacy Backup Support

Remove from BackupPayload:
- `studentLessons`
- `presentations`
- Legacy import methods

### Step 7.4: Clean Up Note Relationships

Remove from Note:
- `studentLesson` relationship
- `presentation` relationship

### Step 7.5: Remove Migration Services

Delete:
- `LessonAssignmentMigrationService.swift`
- `LessonAssignmentMigrationValidator.swift`
- Related tests

### Step 7.6: Final Testing

- Full regression test
- Verify all features work
- Test fresh install (no migration needed)
- Test CloudKit sync

**Checkpoint:** Migration complete. Codebase simplified.

---

## Rollback Plan

At each phase, if issues are discovered:

### Phases 1-3 (Migration infrastructure)
- Simply don't proceed to next phase
- Old models continue working unchanged

### Phase 4-5 (View migration)
- Disable feature flag to revert to old code path
- Data exists in both models, so no data loss

### Phase 6 (Backup)
- Keep accepting old backup format indefinitely
- Users can restore from old backups

### Phase 7 (Cleanup)
- **Cannot rollback** - this is irreversible
- Only proceed when 100% confident
- Consider keeping old backup import support forever

---

## Testing Checklist

### Before Each Phase
- [ ] Create full backup
- [ ] Note current record counts
- [ ] Document expected behavior

### After Each Phase
- [ ] App launches without crash
- [ ] Record counts match expectations
- [ ] All views display correctly
- [ ] Create/edit/delete operations work
- [ ] CloudKit sync works (if enabled)
- [ ] Backup/restore works

### Specific Tests
- [ ] Create new lesson assignment
- [ ] Schedule a lesson
- [ ] Mark lesson as presented
- [ ] View presentation history
- [ ] Check student progress
- [ ] Track-based lessons work
- [ ] Group lessons work
- [ ] Blocking algorithm works
- [ ] Follow-up work creates correctly

---

## Files to Create

| Phase | File | Purpose |
|-------|------|---------|
| 1 | `Models/LessonAssignment.swift` | New unified model |
| 2 | `Services/Migrations/LessonAssignmentMigrationService.swift` | Data migration |
| 2 | `Services/Migrations/LessonAssignmentMigrationValidator.swift` | Migration validation |
| 4 | `Repositories/LessonAssignmentRepository.swift` | Data access layer |
| 6 | Update `Backup/BackupTypes.swift` | DTO for backup |

## Files to Modify

| Phase | File | Change |
|-------|------|--------|
| 1 | `AppCore/AppSchema.swift` | Add LessonAssignment |
| 1 | `Models/Note.swift` | Add relationship |
| 3 | `AppCore/AppBootstrapper.swift` | Run migration |
| 5 | All view files using StudentLesson/Presentation | Switch to LessonAssignment |
| 5 | `Services/LifecycleService.swift` | Major refactor |
| 5 | `Presentations/BlockingAlgorithmEngine.swift` | Update queries |
| 6 | `Backup/BackupTypes.swift` | Add DTO |
| 6 | `Backup/Helpers/BackupDTOTransformers.swift` | Add transformers |
| 6 | `Backup/Helpers/BackupEntityImporter.swift` | Add import logic |

## Files to Delete (Phase 7 Only)

- `Students/StudentLessonModel.swift`
- `Presentations/Presentation.swift`
- `Repositories/StudentLessonRepository.swift`
- `Students/StudentLessonFactory.swift`
- `Services/Migrations/LessonAssignmentMigrationService.swift`
- `Services/Migrations/LessonAssignmentMigrationValidator.swift`
- Related test files

---

## Summary

This migration follows the "expand-migrate-contract" pattern:

1. **Expand:** Add new model alongside old ones (Phases 1-2)
2. **Migrate:** Copy data and gradually switch code paths (Phases 3-6)
3. **Contract:** Remove old models after verification (Phase 7)

Each phase produces a working app. You can pause between phases indefinitely. The final cleanup (Phase 7) is optional and can be deferred until you're fully confident.
