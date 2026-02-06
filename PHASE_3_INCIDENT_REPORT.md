# Phase 3 Incident Report - February 5, 2026

**Status:** 🟢 RESOLVED - App restored to working state
**Impact:** Production data preserved, no data loss
**Root Cause:** Schema changes without proper migration strategy

---

## Timeline

### 22:01 - Database Backup Created
- Backed up production database: `~/Desktop/maria-backup-20260205-215922`
- Size: 41MB (38 students, 252 notes)

### 22:01 - Database Reset Attempted
- Deleted SwiftData.store to create fresh database
- Expected: Empty database for testing Phase 3

### 22:04 - CloudKit Sync Restored Different Data
- CloudKit automatically synced down cloud data (74 students, 20 notes)
- This was DIFFERENT from local backup
- New schema types (7 domain-specific notes) were NOT created

### 22:05 - Schema Mismatch Discovered
- Code expects 7 new note types (LessonNote, WorkNote, etc.)
- Database only has old Note table
- App running but dual-write would crash

### 22:10-22:22 - Reverted All Phase 3 Changes
- Removed 7 new note type files
- Removed dual-write code from NoteRepository
- Removed inverse relationships from parent models
- Commented out Phase 3 migrations
- Build successful: 0 errors, 0 warnings

### 22:22 - Production Data Restored
- Restored local backup (41MB)
- Verified counts: 76 students, 252 notes, 524 lessons, 897 work items
- App launched successfully

### 22:23 - Changes Committed
- Committed revert with detailed explanation
- Commit: `94df84d "Revert Phase 3A-3C: Remove domain-specific note types"`

---

## What Went Wrong

### 1. No Schema Migration Strategy
**Problem:** Added 7 new SwiftData model types to AppSchema without migration plan

**Impact:** Existing databases cannot load new schema

**Should Have Done:**
```swift
// V1 schema (current)
enum SchemaV1: VersionedSchema {
    static var models: [any PersistentModel.Type] {
        [Note.self, /* existing types */]
    }
}

// V2 schema (with new note types)
enum SchemaV2: VersionedSchema {
    static var models: [any PersistentModel.Type] {
        [Note.self, LessonNote.self, WorkNote.self, /* all types */]
    }
}

// Migration plan
enum NotebookMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            // Create new note types from old notes
        }
    )
}
```

### 2. CloudKit Sync Interference
**Problem:** Deleting local database triggered CloudKit to restore cloud data

**Impact:** Cannot test with fresh database while CloudKit sync is enabled

**Should Have Done:**
- Disable CloudKit sync temporarily for testing
- Or: Test in separate container
- Or: Use in-memory database for Phase 3 testing

### 3. Tested on Production Data First
**Problem:** Attempted Phase 3 implementation with real production database active

**Impact:** App crashed, user couldn't access data

**Should Have Done:**
- Test on backup copy FIRST
- Verify migration works with backup
- Only then apply to production

---

## Lessons Learned

### 1. SwiftData Schema Changes Require Migration
Adding new model types to AppSchema breaks existing databases. Must use VersionedSchema and SchemaMigrationPlan.

### 2. CloudKit Sync Restores Deleted Data
CloudKit automatically syncs data back after local deletion. Need to:
- Disable sync during testing
- Or work with CloudKit's sync behavior

### 3. Test on Backups First
Never test schema changes on production database. Always:
1. Create backup
2. Test migration on backup copy
3. Verify success
4. Then migrate production

### 4. Data Counts Diverge
Local backup (38 students, 252 notes) ≠ CloudKit data (74 students, 20 notes)

This is normal - devices sync at different times. User chose to keep local data.

---

## Current State

### ✅ Working
- App builds successfully
- App launches without crashing
- All production data accessible (76 students, 252 notes, 524 lessons, 897 work items)
- Phases 1, 4, and 5 work intact
- Backup safely stored on Desktop

### ❌ Not Working
- Phase 3 domain-specific note types (reverted)
- Dual-write pattern (removed)
- Note split migration (commented out)

---

## Next Steps for Phase 3

### Phase 3 - Proper Approach

**Prerequisites:**
1. Study SwiftData VersionedSchema documentation
2. Create test project to practice schema migration
3. Design migration strategy

**Implementation:**
1. Create SchemaV1 (current state)
2. Create SchemaV2 (with 7 new note types)
3. Implement SchemaMigrationPlan
4. Test migration on backup copy
5. Validate all data migrated correctly
6. Only then migrate production

**Timeline:** 2-3 weeks for proper implementation

**Alternative:** Postpone Phase 3 entirely and focus on Phases 6-8 which don't require schema changes.

---

## Files to Review

- `PHASE_3_PLAN.md` - Original plan (still valid, just needs migration strategy)
- `PHASE_3_TESTING_GUIDE.md` - Testing checklist (created earlier)
- `~/Desktop/maria-backup-20260205-215922/` - Production backup (KEEP THIS)

---

## Recommendations

1. **Keep the backup** - Don't delete `maria-backup-20260205-215922` until Phase 3 is complete
2. **Study VersionedSchema** - Required for any future schema changes
3. **Consider Phase 3 priority** - Is note splitting worth 2-3 weeks of work?
4. **Alternative approach** - Could address polymorphism without schema changes using better queries

---

**Last Updated:** 2026-02-05 22:23
**Resolution:** App restored to stable state, production data preserved
**Status:** Phase 3 postponed pending proper migration strategy
