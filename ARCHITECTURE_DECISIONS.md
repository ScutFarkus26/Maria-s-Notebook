# Architecture Decisions

This document records important architectural decisions and patterns used in Maria's Notebook.

---

## ADR-001: Manual Enum Raw Value Pattern for SwiftData Models

**Status:** ACCEPTED
**Date:** 2026-02-04
**Decision Makers:** Development Team

### Context

SwiftData models frequently use enums for type-safe state representation (e.g., `WorkStatus`, `AttendanceStatus`, `StudentLevel`). These enums must be persisted as their raw values (typically `String`) in the database.

We explored using a `@RawCodable` property wrapper to reduce boilerplate:

```swift
// Attempted approach (REJECTED)
@RawCodable var status: WorkStatus = .active
```

This would have eliminated ~120 lines of repetitive code across 40 enum properties.

### Problem Discovered

SwiftData's `#Predicate` system **cannot access property wrapper storage**. Predicates require direct access to stored properties for query optimization.

```swift
// ❌ FAILS - Predicate cannot access @RawCodable's computed property
@RawCodable var status: WorkStatus = .active
@Query(filter: #Predicate<WorkModel> { $0.status != .complete })
// Error: Cannot use computed properties in Predicates

// ✅ WORKS - Predicate accesses stored property directly
var statusRaw: String = WorkStatus.active.rawValue
var status: WorkStatus {
    get { WorkStatus(rawValue: statusRaw) ?? .active }
    set { statusRaw = newValue.rawValue }
}
@Query(filter: #Predicate<WorkModel> { $0.statusRaw != "complete" })
```

### Decision

**We will use the manual 3-line pattern for all enum properties in @Model classes:**

```swift
// STANDARD PATTERN for SwiftData enums
var statusRaw: String = WorkStatus.active.rawValue
var status: WorkStatus {
    get { WorkStatus(rawValue: statusRaw) ?? .active }
    set { statusRaw = newValue.rawValue }
}
```

### Rationale

1. **SwiftData Compatibility:** Direct property access required for Predicate queries (37 query locations in codebase)
2. **Predictability:** No hidden storage mechanisms - what you see is what's persisted
3. **Consistency:** One pattern throughout the codebase is clearer than mixed approaches
4. **Future-Proof:** Properties not queried today might need querying tomorrow
5. **Migration Safety:** Explicit storage format makes database migrations straightforward
6. **Debugging:** Easy to inspect raw database values without property wrapper indirection

### Consequences

**Accepted Trade-offs:**
- ✅ 120 lines of "boilerplate" across 40 properties (0.2% of 60k line codebase)
- ✅ Verbose but explicit and reliable
- ✅ No abstraction complexity
- ✅ Works with all SwiftData features

**Rejected Alternatives:**
- ❌ Property wrappers (Predicate incompatibility)
- ❌ Computed-only properties (Can't persist)
- ❌ Protocol-based solutions (Same Predicate issues)
- ❌ Hybrid approach (Inconsistent, confusing)

### Code Examples

**Correct Usage:**

```swift
@Model
final class WorkModel {
    // Enum property used in queries
    var statusRaw: String = WorkStatus.active.rawValue
    var status: WorkStatus {
        get { WorkStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    // Optional enum
    var completionOutcomeRaw: String? = nil
    var completionOutcome: CompletionOutcome? {
        get { completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0) } }
        set { completionOutcomeRaw = newValue?.rawValue }
    }
}

// Query usage
@Query(filter: #Predicate<WorkModel> { $0.statusRaw != "complete" })
private var openWork: [WorkModel]
```

**Helper Extensions:**

```swift
extension WorkModel {
    // Computed properties for common checks
    var isComplete: Bool { status == .complete }
    var isActive: Bool { status == .active }

    // Convenience methods
    func markComplete(outcome: CompletionOutcome, note: String? = nil) {
        status = .complete
        completionOutcome = outcome
        completedAt = Date()
        if let note = note { notes = note }
    }
}
```

### Related Decisions

- **ADR-002:** CloudKitUUID property wrapper (ACCEPTED - UUIDs not used in Predicate comparisons)
- **ADR-003:** AppDependencies DI container (ACCEPTED - no SwiftData conflicts)

### References

- CRITICAL_ISSUE_RAWCODABLE.md - Full analysis of property wrapper incompatibility
- SwiftData Predicate Documentation: https://developer.apple.com/documentation/swiftdata/predicate
- Commit: 7450ad8 "Critical fix: Revert @RawCodable refactoring"

---

## ADR-002: CloudKitUUID Property Wrapper - REJECTED

**Status:** REJECTED (Previously thought ACCEPTED)
**Date:** 2026-02-04 (Initial), 2026-02-05 (Rejection discovered)

### Context

CloudKit requires UUID foreign keys to be stored as `String` for sync compatibility. This creates type safety issues:

```swift
// Current approach: Manual String storage
var studentID: String = ""  // CloudKit compatible but not type-safe

// Manual conversion everywhere:
if let uuid = UUID(uuidString: work.studentID) {
    // Use uuid
}
```

We attempted to use `@CloudKitUUID` property wrapper for type-safe UUID access:

```swift
// Attempted approach (REJECTED)
@CloudKitUUID var studentID: UUID = UUID()

// Would have provided type-safe access
let id = work.studentID  // UUID type
```

### Problem Discovered

**SwiftData's @Model macro is incompatible with custom property wrappers.**

When attempting to use `@CloudKitUUID` on WorkModel and WorkParticipantEntity:

```
Error: Invalid redeclaration of synthesized property '_studentID'
Error: Cannot assign value of type 'WorkParticipantEntity._SwiftDataNoType' to type 'CloudKitUUID'
```

**Root Cause:**
- SwiftData's @Model macro automatically synthesizes storage properties (e.g., `_studentID`)
- @CloudKitUUID property wrapper also creates a `storage` property
- These conflict, causing compilation errors
- This is the **same fundamental issue** as ADR-001 (@RawCodable rejection)

### Decision

**REJECTED:** Cannot use @CloudKitUUID property wrapper with SwiftData @Model classes.

**Continue using manual String storage with computed UUID properties where needed:**

```swift
@Model
final class WorkModel {
    // CloudKit-compatible String storage
    var studentID: String = ""
    var lessonID: String = ""

    // Computed UUID access if needed
    var studentUUID: UUID? {
        UUID(uuidString: studentID)
    }
}
```

### Why This Doesn't Work (Same as @RawCodable)

Property wrappers are fundamentally incompatible with SwiftData's @Model macro:

1. **Storage Conflicts:** Both @Model and property wrappers try to manage storage
2. **Macro Synthesis:** @Model synthesizes properties that conflict with wrapper internals
3. **No Workaround:** Cannot override or configure macro behavior
4. **Framework Limitation:** This is a SwiftData architectural constraint

### Attempted Migration Results

**Phase 2 Migration Attempt:**
- Target: 47 UUID String fields across 20 models
- Pilot: WorkModel (2 fields: studentID, lessonID)
- Result: Build failed with macro synthesis errors
- Action: Reverted all changes, WorkModel returned to String storage

### Consequences

**Accepted Reality:**
- ✅ Manual String storage remains necessary for CloudKit compatibility
- ✅ Manual UUID conversions where type safety needed
- ✅ 47 UUID fields stay as String (not a problem in practice)
- ✅ Computed properties provide UUID access when needed

**Rejected Alternatives:**
- ❌ @CloudKitUUID property wrapper (SwiftData incompatible)
- ❌ Custom storage with @Model (macro conflicts)
- ❌ Protocol-based solutions (same storage issues)

### Phase 2 Impact

**Phase 2 (CloudKitUUID Migration) is CANCELLED:**
- Cannot proceed with planned 47-field migration
- No viable alternative approach exists
- String storage is the only SwiftData-compatible solution

**Phase 2 marked as:** 🔴 BLOCKED - SwiftData Framework Limitation

---

## General Principles

### When to Use Property Wrappers in SwiftData

**DO use property wrappers when:**
- ✅ Property is not used in Predicate queries
- ✅ Wrapper provides type safety without query conflicts
- ✅ Example: `@CloudKitUUID` for UUID foreign keys

**DON'T use property wrappers when:**
- ❌ Property needs to be queried via `#Predicate`
- ❌ Wrapper hides storage from SwiftData
- ❌ Example: Enum raw values (use manual pattern)

### Code Patterns to Follow

1. **Explicit over Clever:** Verbose code that works > elegant code that breaks
2. **Framework Alignment:** Work with SwiftData's design, not against it
3. **Consistency:** Use the same pattern for similar problems
4. **Documentation:** Explain why patterns exist (especially "verbose" ones)

### Code Patterns to Avoid

1. ❌ Fighting framework constraints with abstractions
2. ❌ Premature optimization of "boilerplate" code
3. ❌ Assuming "this will never be queried"
4. ❌ Hidden storage mechanisms in persistence layer

---

**Last Updated:** 2026-02-04
**Next Review:** When SwiftData architecture changes or new patterns emerge
