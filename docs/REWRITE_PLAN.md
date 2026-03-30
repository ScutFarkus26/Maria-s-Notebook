# Maria's Notebook Rewrite Plan

## Goal

Rewrite Maria's Notebook with iCloud sync and **classroom sharing** as the default, fewer models, cleaner architecture, and no data loss. The existing backup system (v12) serves as the data bridge between the old and new schema.

## Key Decisions Already Made

- **Core Data + NSPersistentCloudKitContainer** — SwiftData does not support CloudKit shared databases. Core Data with NSPersistentCloudKitContainer provides built-in zone-based sharing with CKShare, automatic sync, and Apple DTS-recommended patterns for multi-user collaboration.
- **Two persistent stores** — Private store for teacher-specific data, shared store for classroom-level data. NSPersistentCloudKitContainer routes records to the correct CloudKit database automatically.
- **Classroom sharing model** — Lead guides share all classroom data with assistants via CKShare. Assistants have read access to everything, write access to attendance/notes/check-ins only. Permissions enforced at the app level.
- **Git worktree for safety** — Rewrite lives in a separate worktree (`../MariasNotebook-Rewrite`). Current app remains untouched on the main branch.
- **Cosmic Map view and Observation Mode view have been removed** — the `GreatLesson` enum and `greatLessonRaw` field on `LessonModel` remain (lesson metadata, not tied to a specific view). Developmental traits files in `ObservationMode/` remain (used by `StudentDetailView`).
- **Data migration via backup/restore** — users export a v12 backup from the current app, the new app imports it into the new schema

## Current State (Before Rewrite)

- 1,038 Swift files, 58 SwiftData models, 50+ services, 40+ ViewModels
- Pure Apple stack (no third-party dependencies)
- **Swift 6.0** with modern concurrency fully adopted:
  - `@Observable` on all ViewModels and stateful services (71 uses, zero `ObservableObject`)
  - `@MainActor` on all ViewModels, services, and repositories (655 uses)
  - `async/await` throughout (923 uses), actors for off-thread work (12 uses)
  - `Sendable` types for cross-actor data (253 uses)
  - Only 7 legacy `DispatchQueue.main.asyncAfter` calls remain (animation timing)
- MVVM + Services architecture with `AppDependencies` DI container
- String-based foreign keys everywhere for CloudKit compatibility
- CloudKit sync enabled by default (private database only, via SwiftData `.automatic`)
- 10+ startup migration services behind a 3-second delay
- Backup system at format v12 with AES-GCM-256 encryption, LZFSE compression, Ed25519 signing
- Minimal test coverage (backup serialization tests only)

---

## Architecture

```
+-------------------------------------+
|           SwiftUI Views             |  @FetchRequest, @Environment(\.managedObjectContext)
+-------------------------------------+
|        Feature Services             |  ~20-25 consolidated services
+-------------------------------------+
|     NSManagedObject Subclasses      |  58 existing + ClassroomMembership
+------------------+------------------+
|  Private Store   |   Shared Store   |  Two NSPersistentStoreDescriptions
+------------------+------------------+
|  NSPersistentCloudKitContainer      |  Handles all CloudKit sync automatically
+------------------+------------------+
|  Private DB      |   Shared DB      |  CloudKit databases
+------------------+------------------+
```

---

## Sharing Model

### Roles
- **Lead Guide** (`CKShare.ParticipantRole.owner`): Full read/write on all shared + private data. Can create classroom, invite assistants, manage permissions.
- **Assistant** (`CKShare.ParticipantRole.readWrite`): Read all shared data. Write limited to AttendanceRecord, Note (on shared students), WorkCheckIn. Cannot modify curriculum, procedures, classroom settings. App-level enforcement.

### Data Routing

**Shared store (~30 entity types, classroom-level):**
Student, Lesson, LessonAttachment, LessonPresentation, Track, TrackStep, GroupTrack, StudentTrackEnrollment, Procedure, Supply, SupplyTransaction, Schedule, ScheduleSlot, CommunityTopic, ProposedSolution, CommunityAttachment, ClassroomJob, JobAssignment, NoteTemplate, MeetingTemplate, TodoTemplate, Resource, NonSchoolDay, SchoolDayOverride, GoingOut, GoingOutChecklistItem, TransitionPlan, TransitionChecklistItem, CalendarNote, SampleWork, SampleWorkStep

**Private store (~27 entity types, per-teacher):**
Note, NoteStudentLink, WorkModel, WorkStep, WorkCheckIn, WorkParticipantEntity, WorkCompletionRecord, PracticeSession, AttendanceRecord, LessonAssignment, StudentMeeting, ScheduledMeeting, Project, ProjectSession, ProjectAssignmentTemplate, ProjectRole, ProjectTemplateWeek, ProjectWeekRoleAssignment, Reminder, CalendarEvent, TodoItem, TodoSubtask, TodayAgendaOrder, Issue, IssueAction, DevelopmentSnapshot, PlanningRecommendation, Document

**New entity:** ClassroomMembership (classroomZoneID, roleRaw, ownerIdentity, joinedAt)

---

## Phase 0: Setup & Swift 6 Cleanup

**What:** Create git worktree, clean up 7 remaining DispatchQueue calls, verify backup system.

**Output:** Clean starting point. App builds as-is in the worktree.

---

## Phase 1: Core Data Model Layer (2 sessions)

**What:** Create `MariasNotebook.xcdatamodeld` with all 58 entities + ClassroomMembership. Generate NSManagedObject subclasses with convenience initializers matching the current @Model API. Keep String foreign keys and raw-String enums for CloudKit compatibility.

**Pros:**
- Single source of truth for the data model
- CloudKit-compatible from day one (no unique constraints, all optional or defaulted)
- Convenience APIs minimize changes needed in services and views

**Risks:**
- The .xcdatamodeld must exactly mirror all 58 entities. Any mismatch means runtime crashes.
- After first CloudKit deployment, schema changes are additive-only (no deletes, renames, type changes).

---

## Phase 2: Core Data Stack + Container Setup

**What:** Create `CoreDataStack.swift` with NSPersistentCloudKitContainer, two persistent store descriptions (private + shared), entity-to-store assignment, and CloudKit container options. Replace the SwiftData `ModelContainer` initialization.

**Pros:**
- NSPersistentCloudKitContainer handles all sync automatically
- Built-in support for private and shared databases
- Persistent history tracking enables remote change notifications

**Risks:**
- Two-store setup adds complexity to context management
- Must correctly assign each entity to the right store

---

## Phase 3: Data Access Layer Conversion (2 sessions)

**What:** Convert repositories and services from SwiftData to Core Data. `ModelContext` → `NSManagedObjectContext`, `#Predicate` → `NSPredicate`, `FetchDescriptor` → `NSFetchRequest`. Update `safeFetch`/`safeSave` extensions.

**Pros:**
- Mechanical conversion — same patterns, different syntax
- Core Data predicates are more powerful than SwiftData's `#Predicate`

**Risks:**
- Volume of changes (~36 files). Each conversion must be tested.
- `#Predicate` type-safety is lost — NSPredicate format strings can fail at runtime.

---

## Phase 4: View Layer Conversion (2-3 sessions)

**What:** Convert SwiftUI views from `@Query` → `@FetchRequest` and `@Environment(\.modelContext)` → `@Environment(\.managedObjectContext)`. Update all ViewModels for Core Data.

**Pros:**
- @FetchRequest is well-understood and feature-rich
- Core Data objects are reference types (same as SwiftData @Model) — navigation works the same

**Risks:**
- Largest volume of changes (~85 view files)
- Need to verify sort descriptors and predicates render correctly

---

## Phase 5: CloudKit Sharing (2 sessions)

**What:** Implement ClassroomSharingService (create/invite/accept/leave), ClassroomPermissions (role→entity→read/write matrix), UICloudSharingController integration, and sharing UI in Settings.

**Architecture:**
- Lead guide creates CKRecordZone → creates CKShare → invites assistant
- Assistant accepts → shared zone appears in their shared DB
- App queries both private and shared contexts for classroom data
- Permission enforcement disables edit controls for assistants on restricted entities

**Pros:**
- Multi-device, multi-teacher support out of the box
- Lead guides and assistants share a single source of truth for classroom data
- Built on Apple's proven sharing infrastructure

**Risks:**
- CloudKit sharing requires real iCloud accounts for testing — cannot be unit tested
- Share acceptance deep linking must be configured in the app's URL scheme
- Assistants could potentially bypass app-level restrictions via direct CloudKit API access (acceptable risk for an education app)

---

## Phase 6: Conflict Resolution & Offline

**What:** Implement persistent history processing, dedup logic, merge policies, and offline UI indicators. NSPersistentCloudKitContainer handles offline queuing automatically.

**Pros:**
- `NSMergeByPropertyObjectTrumpMergePolicy` handles most conflicts automatically
- Persistent history tracking enables efficient remote change processing

**Risks:**
- Two devices editing the same record offline will produce a conflict — last-writer-wins at the property level
- Dedup logic must handle CloudKit merge creating duplicate records

---

## Phase 7: Backup System Integration

**What:** Update BackupService for NSManagedObjectContext, add ClassroomMembership to entity registry, bump to format v13, maintain v12 import support.

**Critical:** The backup system becomes even more important with sharing, since CloudKit sync bugs can propagate data loss across devices. The backup is the safety net.

**Keep v12 import support permanently** — users may come back to the app after months and need to restore from an old backup.

---

## Phase 8: Migration Path for Existing Users

**What:** Detect old SwiftData store, auto-backup before migration, read SwiftData data → write to Core Data stores, show progress UI, offer rollback on failure.

**The One-Way Door:** Once users migrate to Core Data, they can't go back to the SwiftData version. The v12 backup is the insurance policy.

---

## Phase 9: Swift 6.2 Preparation

**What:** Evaluate module-level `@MainActor` default (would eliminate ~655 annotations). Document which services need explicit `nonisolated` or `@concurrent`. No code changes — preparation only.

**Context:** Swift 6.2 "Approachable Concurrency" introduces `@MainActor` by default for entire modules. This is ideal for UI apps. The app already uses `@MainActor` everywhere, so adopting this would be a simplification, not a behavior change.

---

## Implementation Order & Session Count

```
Phase 0 (1) → Phase 1A-1B (2) → Phase 2 (1) → Phase 3A-3B (2)
                                                       │
                                           Phase 4A-4B-4C (2-3)
                                                       │
                                           Phase 5A-5B (2) → Phase 6 (1)
                                                                  │
                                                     Phase 7 (1) → Phase 8 (1)

Phase 9 (1, anytime)
```

**Total: 13-14 sessions**, each designed to fit within a single Claude Code conversation (~150K tokens).

---

## Data Safety Guarantees

1. **Git worktree** — original app untouched on main branch
2. **Phase 0** — verifies backup system before any changes
3. **Phases 1-4** — building new stack, old stack works on main branch
4. **Phase 6** — merge policies prevent data loss during sync
5. **Phase 7** — v12 backward compatibility preserved
6. **Phase 8** — auto-backup before migration, rollback on failure
7. **At any point** — switch to main branch worktree to run original app

---

## Things That Stay the Same

- Pure Apple stack (no third-party dependencies)
- SwiftUI for all UI
- String-based foreign keys (required for CloudKit)
- Enum-as-raw-String pattern (CloudKit compatibility)
- `modifiedAt` timestamps on all models
- `safeFetch` / `safeSave` extensions (adapted for Core Data)
- Type-safe `AppRouter` navigation
- Backup system (enhanced to v13, not replaced)
- `GreatLesson` enum and `greatLessonRaw` on Lesson entity
- Developmental traits feature (used by `StudentDetailView`)
- `@Observable` on all ViewModels and stateful services
- `@MainActor` on all ViewModels, services, and repositories
- Swift 6.0 strict concurrency
