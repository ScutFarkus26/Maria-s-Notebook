# Phase 3: Data Model Consolidation - Implementation Plan

**Status:** 🟡 Planning - Awaiting User Approval
**Branch:** `refactor/phase-1-foundation` (will create `refactor/phase-3-data-model`)
**Risk Level:** 🔴 HIGH - Major data model changes, requires migration
**Estimated Duration:** 4-6 weeks

---

## Executive Summary

Phase 3 will address the **critical polymorphism issues** in the Note model by splitting it into 7+ domain-specific types. This eliminates 16 optional relationships, improves type safety, and optimizes query performance.

**Scope:** Note model refactoring + denormalized field removal
**Prerequisites:** Phases 1, 4, and 5 complete ✅
**Dependencies:** Requires careful data migration strategy

---

## Critical Analysis: Why Phase 3 Is Necessary

### Current Note Model Problems

**Discovered Facts:**
- **16 optional relationships** on a single Note model
- **16 entity types** notes can attach to (Lesson, WorkModel, StudentLesson, etc.)
- **Runtime string detection** via `attachedTo` property (16 if-statements)
- **Denormalized search index** (scopeIsAll, searchIndexStudentID)
- **JSON blob scope storage** with manual sync requirements

**Performance Impact:**
- Complex multi-join queries for note lookup
- O(n) relationship checks on every note access
- Search index fields require manual invalidation
- Cannot use SwiftData query optimization

**Type Safety Issues:**
- Can accidentally set multiple relationships (no compiler enforcement)
- Runtime errors possible if multiple relationships set
- String-based context identification fragile
- No clear "note type" distinction

---

## Proposed Solution: Domain-Specific Note Types

### New Architecture

**Base Protocol:**
```swift
protocol NoteProtocol {
    var id: UUID { get }
    var content: String { get }
    var createdAt: Date { get }
    var authorID: UUID? { get }
    var category: NoteCategory { get }
}
```

**Domain-Specific Types (7 proposed):**

1. **LessonNote** - Attached to Lesson entities
   ```swift
   @Model final class LessonNote: NoteProtocol {
       @Relationship var lesson: Lesson  // Required, not optional!
       var scope: NoteScope  // .all, .student(UUID), or .students([UUID])
   }
   ```

2. **WorkNote** - Attached to WorkModel, WorkCheckIn, or WorkCompletionRecord
   ```swift
   @Model final class WorkNote: NoteProtocol {
       @Relationship var work: WorkModel
       var checkInID: UUID?  // Optional: links to WorkCheckIn
       var completionRecordID: UUID?  // Optional: links to WorkCompletionRecord
       var workPlanItemID: UUID?  // Optional: links to WorkPlanItem
   }
   ```

3. **StudentNote** - Attached to Student, StudentMeeting, or StudentLesson
   ```swift
   @Model final class StudentNote: NoteProtocol {
       @Relationship var student: Student
       var meetingID: UUID?  // Optional: part of StudentMeeting
       var studentLessonID: UUID?  // Optional: specific lesson observation
   }
   ```

4. **AttendanceNote** - Attendance-related notes
   ```swift
   @Model final class AttendanceNote: NoteProtocol {
       @Relationship var attendance: AttendanceRecord
   }
   ```

5. **PresentationNote** - LessonAssignment/Presentation notes
   ```swift
   @Model final class PresentationNote: NoteProtocol {
       @Relationship var presentation: Presentation
       var scope: NoteScope  // Multi-student support
   }
   ```

6. **ProjectNote** - Project session notes
   ```swift
   @Model final class ProjectNote: NoteProtocol {
       @Relationship var projectSession: ProjectSession
   }
   ```

7. **GeneralNote** - Standalone notes (Community, Reminders, Issues, etc.)
   ```swift
   @Model final class GeneralNote: NoteProtocol {
       var communityTopicID: UUID?
       var reminderID: UUID?
       var issueID: UUID?
       var schoolDayOverrideID: UUID?
       var trackEnrollmentID: UUID?
       var practiceSessionID: UUID?
       // Only one should be set (could use enum)
   }
   ```

### Benefits

- ✅ **Type Safety:** Compiler enforces single required relationship
- ✅ **Query Performance:** Single-join queries, no multi-relationship checks
- ✅ **Code Clarity:** LessonNote vs WorkNote makes intent obvious
- ✅ **SwiftData Optimization:** Can index on single relationship
- ✅ **Removes Denormalization:** No more searchIndexStudentID or scopeIsAll
- ✅ **Maintainability:** Clear domain boundaries

---

## Migration Strategy

### Phase 3A: Preparation (Week 1)

**Tasks:**
1. Create all 7 new note type models
2. Add protocol conformance
3. Update AppSchema to include new types
4. Build and verify compilation
5. Create migration service infrastructure

**Files to Create:**
- `Models/Notes/NoteProtocol.swift`
- `Models/Notes/LessonNote.swift`
- `Models/Notes/WorkNote.swift`
- `Models/Notes/StudentNote.swift`
- `Models/Notes/AttendanceNote.swift`
- `Models/Notes/PresentationNote.swift`
- `Models/Notes/ProjectNote.swift`
- `Models/Notes/GeneralNote.swift`
- `Services/Migrations/NoteSplitMigration.swift`

**Success Criteria:**
- ✅ Clean build with no errors
- ✅ All new types in AppSchema
- ✅ Protocol conformance verified

---

### Phase 3B: Dual-Write Implementation (Week 2)

**Strategy:** Write to both old Note model AND new domain-specific types during transition period.

**Update NoteRepository:**
```swift
func createNote(
    content: String,
    context: NoteContext,
    category: NoteCategory,
    scope: NoteScope
) -> Note {
    // Create OLD Note (existing behavior)
    let oldNote = Note(...)
    context.insert(oldNote)

    // ALSO create NEW domain-specific note
    let newNote = createDomainSpecificNote(
        content: content,
        context: context,
        category: category,
        scope: scope
    )
    context.insert(newNote)

    return oldNote  // Return old for backward compatibility
}

private func createDomainSpecificNote(...) -> any NoteProtocol {
    switch context {
    case .lesson(let lesson):
        return LessonNote(content: content, lesson: lesson, scope: scope)
    case .work(let work):
        return WorkNote(content: content, work: work)
    case .studentLesson(let studentLesson):
        return StudentNote(content: content, student: studentLesson.student, studentLessonID: studentLesson.id)
    // ... handle all 14 context types
    }
}
```

**Benefits:**
- ✅ Zero data loss (writing to both models)
- ✅ Can roll back easily (old Note still exists)
- ✅ Can validate migration accuracy (compare old vs new)

**Duration:** 2 releases (2 weeks) with dual-write

---

### Phase 3C: Data Migration Execution (Week 3)

**Migration Service:**
```swift
@MainActor
struct NoteSplitMigration {
    static func execute(context: ModelContext) throws {
        // Check if already migrated
        if MigrationFlag.isSet(.noteSplit, in: context) {
            return
        }

        let allNotes = try context.fetch(FetchDescriptor<Note>())
        var migratedCount = 0
        var errorCount = 0

        for note in allNotes {
            do {
                let newNote = try migrateNote(note, context: context)
                context.insert(newNote)
                migratedCount += 1
            } catch {
                errorCount += 1
                print("Failed to migrate note \(note.id): \(error)")
            }
        }

        // Validation
        guard errorCount == 0 else {
            throw MigrationError.partialFailure(
                migrated: migratedCount,
                failed: errorCount
            )
        }

        // Mark complete
        MigrationFlag.set(.noteSplit, in: context)
    }

    private static func migrateNote(
        _ note: Note,
        context: ModelContext
    ) throws -> any NoteProtocol {
        // Determine context by checking relationships
        if let lesson = note.lesson {
            return LessonNote(
                id: note.id,
                content: note.content,
                createdAt: note.createdAt,
                authorID: note.authorID,
                category: note.category,
                lesson: lesson,
                scope: note.scope
            )
        } else if let work = note.work {
            return WorkNote(
                id: note.id,
                content: note.content,
                createdAt: note.createdAt,
                authorID: note.authorID,
                category: note.category,
                work: work,
                checkInID: note.workCheckIn?.id,
                completionRecordID: note.workCompletionRecord?.id
            )
        }
        // ... handle all 16 relationship types
        else {
            // General note (no specific relationship)
            return GeneralNote(
                id: note.id,
                content: note.content,
                createdAt: note.createdAt,
                authorID: note.authorID,
                category: note.category
            )
        }
    }
}
```

**Validation Queries:**
```swift
// Verify all notes migrated
let oldCount = try context.fetchCount(FetchDescriptor<Note>())
let newCount = (try context.fetchCount(FetchDescriptor<LessonNote>())) +
               (try context.fetchCount(FetchDescriptor<WorkNote>())) +
               (try context.fetchCount(FetchDescriptor<StudentNote>())) +
               // ... all 7 types

assert(oldCount == newCount, "Note count mismatch after migration!")
```

**Success Criteria:**
- ✅ All notes migrated (count matches)
- ✅ No orphaned notes
- ✅ All relationships preserved
- ✅ Scope data intact

---

### Phase 3D: Update Query Code (Week 4)

**Update All Note Queries:**

**Before:**
```swift
// Old polymorphic query
let allNotes = try context.fetch(FetchDescriptor<Note>())
let studentNotes = allNotes.filter { note in
    note.searchIndexStudentID == studentID || note.scopeIsAll
}
```

**After:**
```swift
// New domain-specific queries
func fetchNotesForStudent(_ studentID: UUID) -> [any NoteProtocol] {
    var notes: [any NoteProtocol] = []

    // StudentNote (direct)
    let studentNotePredicate = #Predicate<StudentNote> {
        $0.student.id == studentID
    }
    notes.append(contentsOf: try context.fetch(FetchDescriptor(
        predicate: studentNotePredicate
    )))

    // LessonNote (with scope)
    let lessonNotePredicate = #Predicate<LessonNote> {
        $0.scope.contains(studentID) || $0.scope == .all
    }
    notes.append(contentsOf: try context.fetch(FetchDescriptor(
        predicate: lessonNotePredicate
    )))

    // WorkNote (via work.participants)
    // ...

    return notes
}
```

**Files to Update (~30 files):**
- NoteRepository.swift (query methods)
- StudentNotesTab.swift
- StudentNotesTimelineView.swift
- StudentLessonNotesSectionUnified.swift
- UnifiedNoteEditor.swift (creation logic)
- All detail views with note lists

---

### Phase 3E: Remove Old Note Model (Week 5)

**After 2 releases with dual-write + validation:**

1. Mark Note model as deprecated:
   ```swift
   @available(*, deprecated, message: "Use domain-specific note types")
   @Model final class Note { ... }
   ```

2. Remove dual-write code from NoteRepository

3. Update all remaining references to use new types

4. After 6 months: Delete Note model entirely

**Rollback Safety:**
- Old Note data remains in database for 6 months
- Can revert to dual-write if issues found
- Backup compatibility maintained

---

### Phase 3F: Remove Denormalized Fields (Week 6)

**Fields to Remove:**

1. **Note.scopeIsAll** → Computed from scope enum
2. **Note.searchIndexStudentID** → Use relationship queries
3. **StudentLesson.scheduledForDay** → Computed from scheduledFor
4. **Presentation.studentGroupKeyPersisted** → Computed on demand

**Replacement Pattern:**
```swift
// Before: Denormalized storage
var scheduledForDay: Date
var scheduledFor: Date? {
    didSet {
        if let date = scheduledFor {
            scheduledForDay = Calendar.current.startOfDay(for: date)
        }
    }
}

// After: Computed property
var scheduledForDay: Date? {
    scheduledFor.map { Calendar.current.startOfDay(for: $0) }
}
```

**Query Optimization:**
```swift
// Add index if queries slow down
@Attribute(.indexed) var scheduledFor: Date?
```

---

## Risk Assessment & Mitigation

| Risk | Level | Mitigation |
|------|-------|------------|
| Data loss during migration | 🔴 High | Dual-write period (2 releases), keep old Note for 6 months |
| Query performance degradation | 🟡 Medium | Benchmark before/after, add indices if needed |
| Breaking existing views | 🟡 Medium | Incremental updates, test after each file |
| Relationship integrity | 🟡 Medium | Validation queries, cascade delete rules |
| Rollback complexity | 🟡 Medium | Git tags at each phase, old Note model retained |
| Build stability | 🟢 Low | Phases 1, 4, 5 complete; DI + tests ready |

---

## Testing Strategy

### Unit Tests (New)
- NoteSplitMigrationTests.swift (20 tests)
- DomainNoteCreationTests.swift (15 tests)
- NoteQueryPerformanceTests.swift (10 tests)

### Integration Tests (Existing + Update)
- NoteRepositoryTests.swift (update existing tests)
- BackupRestoreFlowTests.swift (verify new types)
- TodayViewLoadIntegrationTests.swift (note display)

### Manual Testing Checklist
- [ ] Create notes in all 14 contexts
- [ ] Verify note display in student detail
- [ ] Verify note search functionality
- [ ] Test backup/restore with new types
- [ ] Verify migration on production backup copy
- [ ] Performance: Today view load < 100ms

---

## Success Metrics

| Metric | Target | Verification |
|--------|--------|--------------|
| Build Errors | 0 | Xcode build |
| Build Warnings | 0 | Xcode build |
| Test Failures (new) | 0 | Run 2,373+ tests |
| Notes Migrated | 100% | Validation query |
| Query Performance | < 100ms | Benchmark tests |
| Code Complexity | -30% | Cyclomatic complexity reduction |
| Optional Relationships | 16 → 1 | Code review |

---

## Rollback Plan

### Immediate Rollback (During Phase 3A-3C)
```bash
git checkout phase-4-complete  # Last stable phase
# Old Note model still active, no migration run
```

### Post-Migration Rollback (Phase 3D-3E)
```bash
# Revert to dual-write mode
git checkout phase-3c-dual-write
# Both old and new notes exist, can continue using old
```

### Emergency Rollback (Phase 3F)
```bash
# Old Note model deprecated but still in schema
# Can re-enable dual-write if critical issue found
git revert <phase-3f-commits>
```

---

## Dependencies

**Required Before Starting:**
- ✅ Phase 1: Foundation Infrastructure (Complete)
- ✅ Phase 4: Dependency Injection (Complete)
- ✅ Phase 5: Testing Infrastructure (Complete)

**Blocked By:**
- ❌ Phase 2: CloudKitUUID Migration (CANCELLED - not a blocker)

**Enables:**
- Phase 6: Backup System Overhaul (easier with domain-specific types)
- Phase 7: Reactive Caching (clearer cache invalidation)
- Phase 8: Schema Migrations (simplified with explicit types)

---

## Timeline

| Week | Phase | Focus | Deliverable |
|------|-------|-------|-------------|
| 1 | 3A | Preparation | 7 new note types, migration service |
| 2 | 3B | Dual-Write | NoteRepository supports both models |
| 3 | 3C | Migration | All existing notes migrated |
| 4 | 3D | Query Updates | 30 files updated to use new types |
| 5 | 3E | Deprecation | Old Note marked deprecated |
| 6 | 3F | Cleanup | Denormalized fields removed |

**Total:** 6 weeks (4-6 week range due to testing/validation)

---

## Open Questions for User

Before proceeding with Phase 3, please confirm:

1. **Scope Confirmation:** Should all 16 entity types be migrated, or prioritize core types first (Lesson, Work, Student)?
2. **GeneralNote Strategy:** Should we split GeneralNote further or keep it as a catch-all?
3. **Dual-Write Duration:** Is 2 releases (2 weeks) sufficient, or extend to 4 weeks?
4. **Testing Requirements:** Manual testing on production backup copy before migration?
5. **Rollback Threshold:** What's the acceptable error rate for migration (0%? 0.1%?)?

---

## Alternative: Phased Approach (Lower Risk)

If full Phase 3 is too risky, we could break it down:

**Phase 3-Lite:** Core Notes Only (2 weeks)
- Migrate only LessonNote, WorkNote, StudentNote
- Leave other 13 entity types on old Note model
- Prove migration strategy works
- Expand later if successful

**Pros:**
- Lower risk (fewer notes to migrate)
- Faster delivery
- Can validate approach

**Cons:**
- Partial solution
- Still have polymorphism issues for 13 types
- Two note systems in codebase

---

**Last Updated:** 2026-02-05
**Status:** 🟡 Planning - Awaiting User Approval
**Recommended:** Review and approve strategy before proceeding
**Estimated Start:** After user approval
