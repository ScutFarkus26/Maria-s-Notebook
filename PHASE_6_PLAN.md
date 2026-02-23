# Phase 6: Backup System Overhaul - Implementation Plan

**Status:** 🟡 Planning - Awaiting User Approval
**Branch:** `refactor/phase-1-foundation` (will create `refactor/phase-6-backup`)
**Risk Level:** 🟡 MEDIUM - Production backup system changes require careful testing
**Estimated Duration:** 3-4 weeks (incremental migration approach)

---

## Executive Summary

Phase 6 will eliminate the parallel DTO hierarchy (37 DTO types, ~1,500 lines of transformation code) by implementing the GenericBackupCodec system with BackupEncodable protocol conformance across all 48 models.

**Scope:** Replace DTO-based backup with protocol-based system
**Prerequisites:** Phases 1, 4, and 5 complete ✅
**Dependencies:** Must maintain backward compatibility with existing backup files

---

## Critical Analysis: Why Phase 6 Is Necessary

### Current Backup System Problems

**Discovered Facts from Exploration:**
- **37 DTO types** creating parallel model hierarchy
- **~1,500 lines** of manual transformation code in BackupDTOTransformers
- **Manual maintenance burden** - every model change requires DTO update
- **Type safety gaps** - UUID String conversions happen in multiple places
- **GenericBackupCodec exists** but is a placeholder (278 lines, not fully implemented)

**Maintenance Issues:**
- Adding new model requires: Model + DTO + Transformer + BackupPayload update (4 files)
- Field rename requires: Model + DTO + Transformer updates (3 files)
- Transformation logic scattered across BackupDTOTransformers.swift

**Code Example of Current Problem:**
```swift
// Adding a new field to Student requires changes in 4 places:

// 1. Student model
@Model final class Student {
    var email: String? = nil  // NEW FIELD
}

// 2. StudentDTO
struct StudentDTO: Codable {
    var email: String?  // NEW FIELD
}

// 3. BackupDTOTransformers
static func toDTO(_ student: Student) -> StudentDTO {
    StudentDTO(
        // ... 10 existing fields
        email: student.email  // NEW FIELD
    )
}

// 4. BackupEntityImporter
func importStudent(_ dto: StudentDTO, context: ModelContext) {
    let student = Student(
        // ... 10 existing fields
        email: dto.email  // NEW FIELD
    )
}
```

**Proposed Solution (GenericBackupCodec):**
```swift
// Only need to update 1 place:

@Model final class Student: BackupEncodable {
    static var entityName: String { "Student" }

    var email: String? = nil  // NEW FIELD

    // Codable conformance is automatic for simple types!
}

// Backup system automatically includes new field
```

---

## Proposed Solution: Protocol-Based Backup System

### New Architecture

**Core Protocol:**
```swift
protocol BackupEncodable: Codable {
    static var entityName: String { get }
    var backupVersion: Int { get }  // Default: 1
}
```

**Benefits:**
- ✅ **Single Source of Truth:** Model IS the backup format
- ✅ **Automatic Codable:** Swift synthesizes encoding/decoding
- ✅ **Type Safety:** No manual transformations, no conversion errors
- ✅ **Maintainability:** 1 file to update instead of 4
- ✅ **Less Code:** Eliminate ~1,500 lines of transformation logic
- ✅ **Discovery:** Automatic entity registration via protocol conformance

**GenericBackupContainer:**
```swift
struct GenericBackupContainer: Codable {
    var version: Int = 2  // v1 = legacy DTOs, v2 = generic
    var createdAt: Date
    var appVersion: String
    var entities: [String: [Data]]  // "Student" -> [encoded instances]
    var metadata: BackupMetadata
}
```

---

## Migration Strategy: Incremental Dual-Format Approach

### Why Incremental (Recommended by Exploration Agent)

**Option A: Incremental Migration** ✅ RECOMMENDED
- Migrate models one-by-one over 3-4 weeks
- Dual-format support during transition (write both DTO + protocol-based)
- Can test each model migration in isolation
- Lower risk of breaking existing backups
- Easy rollback per model

**Option B: Big Bang** ❌ HIGH RISK
- Migrate all 48 models at once
- No fallback if issues found
- Testing all 48 models simultaneously difficult
- Hard to isolate problems

**Decision:** Use Option A (Incremental)

---

## Phase 6 Implementation Roadmap

### Phase 6A: Foundation Setup (Week 1)

**Goal:** Prepare infrastructure without breaking existing system

**Tasks:**

1. **Create BackupEncodable Registry**
   - File: `Maria's Notebook/Backup/Services/BackupEncodableRegistry.swift`
   - Centralized list of all conforming types
   - Runtime reflection for automatic discovery

2. **Implement GenericBackupCodec Core Methods**
   - Update `discoverBackupableTypes()` to use registry
   - Implement `fetchAll<T>()` using FetchDescriptor
   - Add error handling and progress tracking

3. **Create Dual-Format BackupService Extension**
   - File: `Maria's Notebook/Backup/Services/BackupService+GenericCodec.swift`
   - Writes both legacy DTO format AND generic format
   - Reads from both formats (try generic first, fallback to DTO)

4. **Add Format Version Migration**
   - Detect backup format version (v1 = DTO, v2 = generic)
   - Automatic conversion from v1 → v2 on restore
   - Maintain v1 compatibility for 6 months

**Files to Create:**
- `Backup/Services/BackupEncodableRegistry.swift`
- `Backup/Services/BackupService+GenericCodec.swift`
- `Tests/GenericBackupCodecIntegrationTests.swift`

**Success Criteria:**
- ✅ Clean build (0 errors)
- ✅ GenericBackupCodec can export/import empty container
- ✅ Dual-format writing works without breaking existing backups
- ✅ Tests pass (2,066 existing + 10 new)

---

### Phase 6B: Pilot Migration - Simple Models (Week 2)

**Goal:** Migrate 3 simplest models to validate approach

**Pilot Models (Chosen for Simplicity):**

1. **NonSchoolDay** (3 properties, no relationships)
   ```swift
   extension NonSchoolDay: BackupEncodable {
       static var entityName: String { "NonSchoolDay" }
   }
   // All properties are Codable by default!
   ```

2. **SchoolDayOverride** (4 properties, 1 relationship)
   ```swift
   extension SchoolDayOverride: BackupEncodable {
       static var entityName: String { "SchoolDayOverride" }

       // Custom Codable for relationship
       enum CodingKeys: String, CodingKey {
           case id, date, note
           // Omit 'notes' relationship - not needed in backup
       }
   }
   ```

3. **CommunityAttachment** (5 properties, 1 relationship)
   ```swift
   extension CommunityAttachment: BackupEncodable {
       static var entityName: String { "CommunityAttachment" }

       // Store topicID instead of relationship
       private var topicIDForBackup: UUID? {
           topic?.id
       }
   }
   ```

**Process:**
1. Add BackupEncodable conformance to model
2. Register in BackupEncodableRegistry
3. Write unit tests for encoding/decoding
4. Test round-trip backup/restore
5. Verify existing DTO backups still work
6. Create production backup before migration

**Files to Update:**
- `Maria's Notebook/Models/NonSchoolDay.swift`
- `Maria's Notebook/Models/SchoolDayOverride.swift`
- `Maria's Notebook/Community/CommunityAttachment.swift`
- `Backup/Services/BackupEncodableRegistry.swift`
- `Tests/NonSchoolDayBackupTests.swift` (new)
- `Tests/SchoolDayOverrideBackupTests.swift` (new)
- `Tests/CommunityAttachmentBackupTests.swift` (new)

**Validation:**
- [ ] Create backup with dual-format (both DTO + generic)
- [ ] Restore from generic format
- [ ] Restore from legacy DTO format
- [ ] Compare counts: DTO vs generic (must match)
- [ ] Verify all fields preserved (id, date, reason, note, etc.)

**Success Criteria:**
- ✅ 3 models conform to BackupEncodable
- ✅ Round-trip backup/restore works for all 3
- ✅ Legacy DTO backups still restore correctly
- ✅ Build stable (0 errors)
- ✅ Tests pass (2,066 + 15 new)

---

### Phase 6C: Core Domain Models (Week 3)

**Goal:** Migrate primary domain models (Student, Lesson, Work, Note)

**Models to Migrate (Priority Order):**

1. **Student** (12 properties, 1 relationship array)
   - Challenge: `nextLessonUUIDs` stored as String array
   - Solution: Keep as-is (Codable already)

2. **Lesson** (10 properties, no critical relationships)
   - Challenge: `pagesFileRelativePath` optional
   - Solution: Standard Codable

3. **WorkModel** (20+ properties, complex enums)
   - Challenge: Manual enum pattern (`statusRaw`, `completionOutcomeRaw`)
   - Solution: Custom CodingKeys to include only `*Raw` properties

4. **Note** (10 properties, 16 optional relationships)
   - Challenge: Polymorphic relationships
   - Solution: Store relationship IDs, not relationships

**Custom Codable Pattern for Models with Enums:**
```swift
@Model
final class WorkModel: BackupEncodable {
    static var entityName: String { "WorkModel" }

    // Manual enum pattern (required by SwiftData)
    var statusRaw: String = WorkStatus.active.rawValue
    var status: WorkStatus {
        get { WorkStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    // Custom Codable to encode raw values
    enum CodingKeys: String, CodingKey {
        case id, lessonID, studentID, createdAt, scheduledFor
        case statusRaw = "status"  // Encode as "status" for cleaner JSON
        case completionOutcomeRaw = "completionOutcome"
        // ... other properties
        // Omit computed properties (status, completionOutcome)
    }
}
```

**Custom Codable Pattern for Relationships:**
```swift
@Model
final class Note: BackupEncodable {
    static var entityName: String { "Note" }

    // Relationships (not encoded)
    @Relationship var lesson: Lesson?
    @Relationship var work: WorkModel?
    // ... 14 more relationships

    // Custom Codable - encode IDs instead of relationships
    enum CodingKeys: String, CodingKey {
        case id, body, createdAt, updatedAt, isPinned
        // Omit relationship properties
    }

    // Manual encoding for relationship IDs
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(body, forKey: .body)
        // ... encode stored properties only

        // Encode relationship IDs separately if needed
        var relationships = encoder.container(keyedBy: RelationshipKeys.self)
        try relationships.encodeIfPresent(lesson?.id, forKey: .lessonID)
        try relationships.encodeIfPresent(work?.id, forKey: .workID)
    }
}
```

**Files to Update:**
- `Maria's Notebook/Students/StudentModel.swift`
- `Maria's Notebook/Lessons/LessonModel.swift`
- `Maria's Notebook/Work/WorkModel.swift`
- `Maria's Notebook/Models/Note.swift`
- `Backup/Services/BackupEncodableRegistry.swift`
- `Tests/StudentBackupTests.swift` (new)
- `Tests/LessonBackupTests.swift` (new)
- `Tests/WorkModelBackupTests.swift` (new)
- `Tests/NoteBackupTests.swift` (new)

**Success Criteria:**
- ✅ 4 core models conform to BackupEncodable
- ✅ Enum properties encoded as raw values
- ✅ Relationships handled correctly (IDs, not objects)
- ✅ Round-trip backup/restore for all 4 models
- ✅ Tests pass (2,066 + 35 new)

---

### Phase 6D: Remaining Models (Week 4)

**Goal:** Complete migration of all 41 remaining models

**Models by Category:**

**Lesson-Related (5 models):**
- StudentLesson
- LessonAssignment
- WorkPlanItem
- WorkCheckIn
- WorkCompletionRecord

**Student-Related (3 models):**
- StudentMeeting
- AttendanceRecord
- WorkParticipantEntity

**Community-Related (3 models):**
- CommunityTopic
- ProposedSolution
- (CommunityAttachment already migrated in 6B)

**Project-Related (6 models):**
- Project
- ProjectAssignmentTemplate
- ProjectSession
- ProjectRole
- ProjectTemplateWeek
- ProjectWeekRoleAssignment

**Practice-Related (1 model):**
- PracticeSession

**Work-Related (2 models):**
- WorkModel (already migrated in 6C)
- Issue
- IssueAction

**Notes-Related (2 models):**
- NoteStudentLink
- NoteTemplate

**Template-Related (1 model):**
- MeetingTemplate

**Tracking/System (remaining models from BackupEntityRegistry)**

**Process for Each Model:**
1. Add BackupEncodable conformance
2. Define CodingKeys (omit relationships, computed properties)
3. Register in BackupEncodableRegistry
4. Write unit tests
5. Validate round-trip backup/restore

**Batch Approach:**
- Group similar models together (e.g., all Project* models)
- Test batch before moving to next group
- Create backup before each batch

**Files to Update:**
- 41 model files (add BackupEncodable conformance)
- BackupEncodableRegistry.swift
- ~41 test files (new)

**Success Criteria:**
- ✅ All 48 models conform to BackupEncodable
- ✅ All models registered in BackupEncodableRegistry
- ✅ Round-trip tests pass for all models
- ✅ Build stable (0 errors)
- ✅ Tests pass (2,066 + 150+ new = 2,216+)

---

### Phase 6E: Deprecate DTO System (Week 5)

**Goal:** Mark legacy DTO system as deprecated, switch to generic format as primary

**Tasks:**

1. **Update BackupService to Prefer Generic Format**
   ```swift
   func createBackup() async throws -> BackupEnvelope {
       // Write generic format (v2) as primary
       let genericContainer = try GenericBackupCodec.exportBackup(context: context)

       // Also write legacy format (v1) for compatibility (6 months)
       let legacyPayload = try createLegacyPayload()

       return BackupEnvelope(
           formatVersion: BackupFile.formatVersion,  // v6
           payload: legacyPayload,  // Legacy DTO format (deprecated)
           compressedPayload: try compress(genericContainer)  // New generic format
       )
   }
   ```

2. **Update Restore to Try Generic First**
   ```swift
   func restoreBackup(_ envelope: BackupEnvelope) async throws {
       // Try generic format first (v2)
       if let compressedData = envelope.compressedPayload {
           let genericContainer = try decompress(compressedData)
           try GenericBackupCodec.importBackup(genericContainer, into: context)
           return
       }

       // Fallback to legacy DTO format (v1)
       if let payload = envelope.payload {
           try restoreLegacyPayload(payload)
           return
       }

       throw BackupError.noPayloadFound
   }
   ```

3. **Mark DTO Types as Deprecated**
   ```swift
   @available(*, deprecated, message: "Use BackupEncodable protocol on models instead")
   struct StudentDTO: Codable { ... }
   ```

4. **Update Documentation**
   - Add migration guide for developers
   - Document backward compatibility timeline
   - Explain generic format benefits

**Files to Update:**
- `Backup/BackupService.swift`
- `Backup/BackupTypes.swift` (mark DTOs deprecated)
- `Backup/Helpers/BackupDTOTransformers.swift` (mark deprecated)
- `Backup/Helpers/BackupEntityImporter.swift` (mark deprecated)
- `ARCHITECTURE_DECISIONS.md` (add ADR-003: Generic Backup Format)

**Success Criteria:**
- ✅ Generic format is primary (used for new backups)
- ✅ Legacy DTO format still readable (backward compatibility)
- ✅ Deprecation warnings on DTO types
- ✅ Documentation updated
- ✅ Tests pass (all existing + new)

---

### Phase 6F: Cleanup and Removal (Week 6)

**Goal:** Remove deprecated DTO code after 6 months of dual-format support

**Timeline:** 6 months after Phase 6E completion

**Tasks:**

1. **Remove DTO Files**
   - Delete `BackupTypes.swift` (DTO definitions)
   - Delete `BackupDTOTransformers.swift` (~400 lines)
   - Delete `BackupEntityImporter.swift` (legacy restore logic)
   - Delete test files for DTOs

2. **Simplify BackupService**
   - Remove dual-format writing
   - Remove legacy restore logic
   - Keep only generic format code

3. **Update Backup Format Version**
   ```swift
   public enum BackupFile: Sendable {
       nonisolated public static let formatVersion = 7  // Pure generic format
       nonisolated public static let compressionIntroducedVersion = 6
   }
   ```

4. **Final Verification**
   - Ensure all existing backups can still be read
   - Test migration from v1 (DTO) → v2 (generic) → v7 (pure generic)
   - Performance testing: Compare backup/restore speed

**Files to Delete:**
- `Backup/BackupTypes.swift` (DTO definitions, ~1,000 lines)
- `Backup/Helpers/BackupDTOTransformers.swift` (~400 lines)
- `Backup/Helpers/BackupEntityImporter.swift` (~600 lines)
- `Tests/BackupDTOTests.swift` (if exists)

**Lines of Code Removed:** ~2,000 lines

**Success Criteria:**
- ✅ DTO code completely removed
- ✅ Build stable (0 errors)
- ✅ All tests pass
- ✅ Backup/restore performance same or better
- ✅ File size same or smaller

---

## Risk Assessment & Mitigation

| Risk | Level | Mitigation |
|------|-------|------------|
| Breaking existing backups | 🔴 High | Dual-format support for 6 months, extensive testing |
| Codable incompatibility with SwiftData | 🟡 Medium | Pilot migration first, custom CodingKeys for relationships |
| Performance degradation | 🟡 Medium | Benchmark before/after, compression may improve speed |
| Data loss during migration | 🟡 Medium | Backup before each phase, rollback plan ready |
| SwiftData Predicate issues | 🟢 Low | BackupEncodable doesn't use property wrappers |
| Build stability | 🟢 Low | Incremental approach, test after each model |

---

## Testing Strategy

### Unit Tests (New)

**Per-Model Tests (48 tests):**
- `StudentBackupTests.swift` - Round-trip encoding/decoding
- `LessonBackupTests.swift` - Round-trip encoding/decoding
- ... (1 test file per model)

**Integration Tests:**
- `GenericBackupCodecIntegrationTests.swift` (20 tests)
  - Full backup with all 48 models
  - Restore from generic format
  - Restore from legacy DTO format
  - Format version migration (v1 → v2)
  - Backward compatibility

**Performance Tests:**
- `BackupPerformanceBenchmarkTests.swift` (5 tests)
  - Backup time: DTO vs generic
  - Restore time: DTO vs generic
  - File size: DTO vs generic
  - Memory usage during backup
  - Compression ratio

### Manual Testing Checklist

- [ ] Create backup with 100+ students, 500+ lessons
- [ ] Restore from generic format (verify counts)
- [ ] Restore from legacy DTO format (verify counts)
- [ ] Test on production backup copy
- [ ] Verify file size (should be similar or smaller)
- [ ] Test migration: v1 (DTO) → v2 (generic)
- [ ] Verify all relationships preserved
- [ ] Performance: Backup/restore < 5 seconds for 10k entities

---

## Success Metrics

| Metric | Target | Verification |
|--------|--------|-----------------|
| Build Errors | 0 | Xcode build |
| Build Warnings | 0 | Xcode build |
| Test Failures | 0 | Run 2,216+ tests |
| Backup Format Version | v2 (generic) | BackupFile.formatVersion |
| Lines of Code Removed | ~2,000 | Git diff |
| DTO Types Remaining | 0 (after 6F) | Code search for "DTO" |
| Backup/Restore Performance | Same or better | Benchmark tests |
| File Size | Same or smaller | Compare backup files |
| Backward Compatibility | 6 months | DTO backups still restore |

---

## Rollback Plan

### Immediate Rollback (During Phase 6A-6D)

```bash
# Revert to pre-Phase 6 state
git checkout phase-5-complete  # Last stable phase
# All DTOs still active, no migration started
```

### Partial Rollback (During Phase 6E)

```bash
# Revert to dual-format mode
git checkout phase-6d-complete  # All models migrated, DTOs still available
# Can continue using legacy DTO format
```

### Emergency Rollback (Phase 6F)

```bash
# If cleanup breaks existing backups
git revert <phase-6f-commits>
# Restore DTO files from git history
git checkout phase-6e-complete -- Backup/BackupTypes.swift
git checkout phase-6e-complete -- Backup/Helpers/BackupDTOTransformers.swift
```

**Backup Safety Net:**
- Keep production backup before Phase 6 starts
- Tag each phase completion: `phase-6a-complete`, `phase-6b-complete`, etc.
- Test restore from backup before proceeding to next phase

---

## Dependencies

**Required Before Starting:**
- ✅ Phase 1: Foundation Infrastructure (Complete)
- ✅ Phase 4: Dependency Injection (Complete)
- ✅ Phase 5: Testing Infrastructure (Complete)

**Blocked By:**
- ❌ None (independent of other phases)

**Enables:**
- Phase 7: Reactive Caching (clearer cache invalidation with protocol conformance)
- Phase 8: Schema Migrations (automatic backup/restore for migration testing)

---

## Technical Challenges & Solutions

### Challenge 1: SwiftData Relationships Are Not Codable

**Problem:**
```swift
@Model final class Student {
    @Relationship var lessons: [Lesson]  // Not Codable!
}
```

**Solution:** Omit relationships from CodingKeys
```swift
extension Student: BackupEncodable {
    enum CodingKeys: String, CodingKey {
        case id, firstName, lastName, birthday
        // Omit 'lessons' relationship
    }
}
```

---

### Challenge 2: Manual Enum Pattern Storage

**Problem:**
```swift
@Model final class WorkModel {
    var statusRaw: String  // This should be encoded
    var status: WorkStatus { ... }  // This should NOT be encoded
}
```

**Solution:** Custom CodingKeys
```swift
extension WorkModel: BackupEncodable {
    enum CodingKeys: String, CodingKey {
        case statusRaw = "status"  // Encode as "status" in JSON
        case completionOutcomeRaw = "completionOutcome"
        // Omit computed properties
    }
}
```

---

### Challenge 3: UUID String Storage (CloudKit Compatibility)

**Problem:**
```swift
@Model final class WorkModel {
    var studentID: String = ""  // UUID stored as String
    var lessonID: String = ""
}
```

**Solution:** Keep as String (Codable already)
```swift
extension WorkModel: BackupEncodable {
    // studentID and lessonID are already Codable
    // No custom coding needed
}
```

---

### Challenge 4: Optional Enum Properties

**Problem:**
```swift
@Model final class WorkModel {
    var completionOutcomeRaw: String? = nil
    var completionOutcome: CompletionOutcome? { ... }
}
```

**Solution:** Same as Challenge 2
```swift
enum CodingKeys: String, CodingKey {
    case completionOutcomeRaw = "completionOutcome"
    // Omit computed property
}
```

---

### Challenge 5: NoteScope JSON Blob

**Problem:**
```swift
@Model final class Note {
    @Attribute(.externalStorage) private var scopeBlob: Data?
    var scope: NoteScope { ... }  // Computed from scopeBlob
}
```

**Solution:** Encode scopeBlob, not scope
```swift
extension Note: BackupEncodable {
    enum CodingKeys: String, CodingKey {
        case scopeBlob = "scope"  // Encode blob as "scope"
        // Omit computed 'scope' property
    }
}
```

---

### Challenge 6: Truly Generic fetchAll<T>()

**Problem:** SwiftData's #Predicate requires concrete types
```swift
func fetchAll<T: BackupEncodable>(_ type: T.Type) throws -> [T] {
    // Can't use FetchDescriptor<T> because T is not constrained to PersistentModel
}
```

**Solution:** Require dual conformance
```swift
protocol BackupEncodable: Codable, PersistentModel {
    static var entityName: String { get }
}

// Now fetchAll works:
func fetchAll<T: BackupEncodable>(_ type: T.Type, in context: ModelContext) throws -> [T] {
    let descriptor = FetchDescriptor<T>()
    return try context.fetch(descriptor)
}
```

**Note:** All @Model classes automatically conform to PersistentModel, so this is safe.

---

## Open Questions for User

Before proceeding with Phase 6, please confirm:

1. **Dual-Format Duration:** Is 6 months of dual-format support sufficient, or extend to 12 months?
2. **Pilot Testing:** Should we test pilot models (NonSchoolDay, SchoolDayOverride, CommunityAttachment) on production backup first?
3. **Rollback Threshold:** What's the acceptable error rate for backup/restore (0%? 0.01%?)?
4. **Performance Requirements:** Is 5 seconds acceptable for backup/restore of 10k entities?
5. **Cleanup Timing:** Wait 6 months before Phase 6F (cleanup), or proceed immediately if all tests pass?

---

## Timeline

| Week | Phase | Focus | Deliverable |
|------|-------|-------|-------------|
| 1 | 6A | Foundation | GenericBackupCodec implemented, dual-format support |
| 2 | 6B | Pilot Migration | 3 simple models migrated, validation complete |
| 3 | 6C | Core Models | Student, Lesson, Work, Note migrated |
| 4 | 6D | Remaining Models | All 41 remaining models migrated |
| 5 | 6E | Deprecation | Generic format primary, DTOs deprecated |
| +6mo | 6F | Cleanup | DTO code removed (~2,000 lines deleted) |

**Total:** 5 weeks + 6 months deprecation period

---

## Alternative: Phased Rollout (Lower Risk)

If full Phase 6 is too risky, we could break it down:

**Phase 6-Lite:** Core Models Only (2 weeks)
- Migrate only Student, Lesson, WorkModel, Note (4 models)
- Prove protocol-based approach works
- Keep DTOs for remaining 44 models
- Expand later if successful

**Pros:**
- Lower risk (fewer models to test)
- Faster delivery
- Can validate approach with real data

**Cons:**
- Partial solution (still have DTOs for 44 models)
- Dual system complexity (protocol + DTO)
- Delayed maintenance benefits

---

**Last Updated:** 2026-02-05
**Status:** 🟡 Planning - Awaiting User Approval
**Recommended:** Review and approve strategy before proceeding
**Estimated Start:** After user approval
