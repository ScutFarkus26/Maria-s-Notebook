# Swift 6.2 Evaluation: Module-Level @MainActor Adoption

**Date:** April 2026
**Status:** Preparation — ready to adopt when Swift 6.2 is stable
**Applies to:** Maria's Notebook (Core Data + NSPersistentCloudKitContainer rewrite)

---

## Summary

Swift 6.2 introduces module-level default actor isolation via `.defaultIsolation(MainActor.self)` in the Swift settings. This eliminates the need for per-type `@MainActor` annotations when the entire module should default to main-actor isolation.

**Recommendation: Adopt `.defaultIsolation(MainActor.self)`** — the app is already structured for this pattern.

---

## Current Concurrency Annotation Counts

| Annotation | Count | Notes |
|-----------|-------|-------|
| `@MainActor` | ~496 | Views, view models, services, app lifecycle |
| `nonisolated` | ~257 | Background work, computed properties, Sendable contexts |
| `: Sendable` | ~46 | DTOs, enums, value types for cross-actor transfer |
| `NSManagedObject` subclasses | ~60 | NOT Sendable — context-bound |

---

## What Changes Under Module-Level @MainActor

### Becomes Redundant (Can Remove)
- ~496 explicit `@MainActor` annotations on classes, structs, functions
- `@MainActor` on SwiftUI views (already implicitly MainActor via View protocol)
- `@MainActor` on `@Observable` classes (implicitly MainActor in Swift 6.2)

### Must Add `nonisolated` or `@concurrent`
These patterns currently run off the main actor and must be explicitly opted out:

1. **Background Core Data contexts** — `NSManagedObjectContext.perform { }` blocks
   - `PersistentHistoryProcessor.processRemoteChanges()`
   - `DeduplicationCoordinator` background processing
   - `AppBootstrapper.runPostLaunchMigrations()` (uses `Task.detached`)

2. **BackupService encoding pipeline** — JSON encoding, compression, encryption
   - `encodeAndWriteExport()` — CPU-intensive, should stay off main thread
   - `extractPayloadBytes()` — decompression/decryption

3. **File I/O operations**
   - `LessonFileStorage.migrateToICloudDrive()`
   - `BackupService.verifyExport()`
   - `SwiftDataMigrationService.performMigration()` (already async)

4. **CloudKit operations**
   - `ClassroomSharingService` share/accept operations
   - `CloudKitSyncStatusService` monitoring

5. **NSManagedObject computed properties** — Already `nonisolated` where needed
   - The ~257 existing `nonisolated` declarations cover most of these

### No Change Needed
- DTOs and value types (already Sendable, isolation doesn't apply)
- Enums with static properties (already nonisolated where needed)
- Extensions on Foundation/UIKit types

---

## NSManagedObject Threading Rules

**Critical: NSManagedObject is NOT Sendable and this does NOT change in Swift 6.2.**

Despite Xcode 26's experimental `@retroactive Sendable` on NSManagedObject, the actual thread-safety rules are unchanged:
- NSManagedObject instances are bound to their context's queue
- Pass `NSManagedObjectID` or Sendable DTOs across actor boundaries
- Use `context.perform { }` for background context work

The app already follows this pattern:
- `BackupPayload` and all `*DTO` types are `Sendable`
- Entity-to-DTO conversion happens within the context's queue
- No NSManagedObject subclass conforms to Sendable

---

## Migration Checklist

When ready to enable module-level @MainActor:

### 1. Enable in Build Settings
```swift
// Package.swift or Xcode build setting
.defaultIsolation(MainActor.self)
```

### 2. Remove Redundant Annotations
- [ ] Remove `@MainActor` from ~496 declarations
- [ ] Keep `@MainActor` only where it serves as documentation for protocol conformance

### 3. Add Explicit Isolation Where Needed
- [ ] Add `nonisolated` to background Core Data context work in:
  - `AppBootstrapper.runPostLaunchMigrations()`
  - `PersistentHistoryProcessor`
  - `DeduplicationCoordinator`
  - `MigrationRunner`
- [ ] Add `nonisolated` or `@concurrent` to:
  - `BackupService` encoding/compression pipeline
  - File I/O helpers
  - CloudKit operation handlers
- [ ] Verify `Task.detached` blocks don't capture MainActor-isolated state

### 4. Verify Background Work
- [ ] `NSManagedObjectContext.perform { }` blocks work correctly
- [ ] Batch save operations in `SwiftDataMigrationService` work off main thread
- [ ] History processing in `PersistentHistoryProcessor` remains nonisolated

### 5. Test
- [ ] All Phase 4–9 tests pass
- [ ] App launches without deadlock
- [ ] Background operations (backup, sync, migration) complete without main thread blocking
- [ ] CloudKit sync works correctly
- [ ] Stutter detection doesn't fire during normal usage

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Deadlock from accidentally running background work on MainActor | Medium | High | Careful audit of `nonisolated` annotations |
| Performance regression from main-thread bottleneck | Low | Medium | Existing `nonisolated` coverage is good (~257) |
| Compilation errors from missing `nonisolated` | High | Low | Incremental adoption, fix as compiler reports |
| NSManagedObject threading violations | Low | High | Already using DTOs for cross-boundary transfer |

---

## Conclusion

The app is well-positioned for Swift 6.2 module-level @MainActor:
- Already uses `@MainActor` on ~496 declarations (most of the codebase)
- Already has ~257 `nonisolated` declarations for background work
- Already uses Sendable DTOs for cross-actor data transfer
- No NSManagedObject subclass incorrectly marked as Sendable

The primary work is removing redundant `@MainActor` annotations and adding a few missing `nonisolated` markers on background Core Data operations. This is a low-risk, high-reward change that reduces boilerplate and makes the concurrency model clearer.
