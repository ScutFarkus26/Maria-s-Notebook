# Phase 3: Testing Guide

**Status:** Phase 3A-3C Complete ✅ | Phase 3D-3F Pending
**Current Branch:** `refactor/phase-1-foundation`
**Last Updated:** 2026-02-05

---

## What Has Been Completed

### Phase 3A: Infrastructure ✅
- Created 7 domain-specific note types
- Added to AppSchema
- Fixed relationship configurations
- **Tag:** `phase-3a-infrastructure-complete`

### Phase 3B: Dual-Write ✅
- NoteRepository now writes to BOTH old Note and new domain-specific types
- All note creation goes through dual-write
- Fixed inverse relationship errors
- **Tags:** `phase-3b-dual-write-complete`, `phase-3b-relationships-fixed`

### Phase 3C: Migration Service ✅
- NoteSplitMigration service ready to migrate existing notes
- Validates migration integrity
- Idempotent (safe to run multiple times)
- **Tag:** `phase-3c-migration-service`

---

## Current State

**Dual-Write Active:** Every new note creates:
1. Old `Note` record (for backward compatibility)
2. New domain-specific type (LessonNote, WorkNote, StudentNote, etc.)

**Migration NOT Yet Run:** Existing old notes remain unmigrated

**Old Note Records:** Preserved for rollback safety

---

## Testing Before Proceeding to Phase 3D

### Recommended Testing Steps

#### 1. Backup Current Database
```bash
# Create backup before any testing
cp ~/Library/Application\ Support/Maria\'s\ Notebook/default.store ~/Desktop/marias-notebook-backup-before-phase3.store
```

#### 2. Test Dual-Write Behavior

**Create test notes in each context:**
- [ ] Create note on Lesson → should create LessonNote
- [ ] Create note on WorkModel → should create WorkNote  
- [ ] Create note on StudentLesson → should create StudentNote (one per student)
- [ ] Create note on Attendance → should create AttendanceNote
- [ ] Create note on Presentation → should create PresentationNote
- [ ] Create note on ProjectSession → should create ProjectNote
- [ ] Create standalone note → should create GeneralNote

**Verify dual-write:**
```swift
// In Xcode debug console after creating note:
let noteCount = try modelContext.fetchCount(FetchDescriptor<Note>())
let lessonNoteCount = try modelContext.fetchCount(FetchDescriptor<LessonNote>())
print("Old notes: \(noteCount), LessonNotes: \(lessonNoteCount)")
// Both should have increased
```

#### 3. Test Migration Service (Optional - Development Only)

**Option A: Test on Copy of Production Database**
1. Export production backup
2. Restore to test database
3. Run migration manually:
   ```swift
   // In app startup or test code
   let success = try await NoteSplitMigration.execute(context: modelContext)
   print("Migration result: \(success)")
   ```
4. Verify note counts match
5. Test note display in UI

**Option B: Skip Migration Testing (Safe)**
- Continue with dual-write only
- Migration will run automatically when MigrationRegistry executes
- Old notes remain accessible
- Can always rollback via git tags

#### 4. Verify Build & Launch
- [ ] App builds without errors
- [ ] App launches without crashes
- [ ] Can create notes in various contexts
- [ ] Notes display correctly in UI

---

## Safety Net: Rollback Options

### If Issues Found During Testing

**Immediate Rollback (Phase 3A-3C):**
```bash
# Revert to before Phase 3
git checkout phase-1-foundation  # or appropriate tag
```

**Restore Database:**
```bash
# Restore backup
cp ~/Desktop/marias-notebook-backup-before-phase3.store ~/Library/Application\ Support/Maria\'s\ Notebook/default.store
```

### Git Rollback Tags
- `phase-3a-infrastructure-complete` - After creating note types
- `phase-3b-dual-write-complete` - After dual-write implementation
- `phase-3b-relationships-fixed` - After fixing crashes
- `phase-3c-migration-service` - After migration service (current)

---

## Before Proceeding to Phase 3D

### Decision Point

**Phase 3D involves updating 30+ files to query domain-specific note types.**

**Option 1: Proceed with Phase 3D**
- Update all query code to use new types
- Large scope (4-6 hours estimated)
- Point of no return (requires completing all files)

**Option 2: Pause and Test**
- Test dual-write behavior thoroughly
- Run migration on production backup
- Verify data integrity
- Then proceed with Phase 3D

**Option 3: Deploy Dual-Write First**
- Ship current state (dual-write only)
- Run in production for 1-2 weeks
- Validate data being written correctly
- Then proceed with Phase 3D in next release

---

## Phase 3D Preview: What Will Change

### Files That Need Updates (~30 files)

**Note Queries:**
- NoteRepository.swift (query methods)
- StudentNotesTab.swift
- StudentNotesTimelineView.swift
- StudentLessonNotesSectionUnified.swift
- UnifiedNoteEditor.swift (creation logic)
- All detail views with note lists

**Query Pattern Changes:**

**Before (polymorphic):**
```swift
let allNotes = try context.fetch(FetchDescriptor<Note>())
let studentNotes = allNotes.filter { note in
    note.searchIndexStudentID == studentID || note.scopeIsAll
}
```

**After (domain-specific):**
```swift
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
    
    // ... other note types
    
    return notes
}
```

**Complexity:** Each "fetch all notes" location needs type-specific logic

---

## Success Criteria for Phase 3

### Phase 3A-3C (Current) ✅
- [x] Build compiles
- [x] App launches
- [x] Dual-write creates both old and new notes
- [x] Migration service ready

### Phase 3D-3F (Pending)
- [ ] All query code updated to use domain-specific types
- [ ] Old Note model deprecated
- [ ] Denormalized fields removed
- [ ] All tests pass
- [ ] UI displays notes from both old and new systems

---

## Recommendation

Given that Phase 3D is a large, multi-file update, I recommend:

**Path A (Conservative):**
1. Pause here for testing
2. Create backup of production database
3. Test migration on backup copy
4. Verify dual-write working correctly
5. Then proceed with Phase 3D in separate session

**Path B (Aggressive):**
1. Proceed immediately with Phase 3D
2. Update all 30+ files in one session
3. Test thoroughly at end
4. Rollback entire Phase 3 if issues found

---

**Your Choice:** Which path would you like to take?
- Type `test` to pause and test current state
- Type `proceed` to continue with Phase 3D immediately
- Type `status` to see detailed current state

---

**Last Updated:** 2026-02-05 (Phase 3C Complete)
