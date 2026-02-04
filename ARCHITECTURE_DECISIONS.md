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

## ADR-002: CloudKitUUID Property Wrapper for Type-Safe UUID Storage

**Status:** ACCEPTED
**Date:** 2026-02-04

### Context

CloudKit requires UUID foreign keys to be stored as `String` for sync compatibility. This creates type safety issues:

```swift
// Before: Error-prone string handling
var studentID: String = ""  // Any string accepted, no type safety

// Later in code:
if let uuid = UUID(uuidString: work.studentID) {
    // Use uuid
}
```

### Decision

Use `@CloudKitUUID` property wrapper for type-safe UUID access with String storage:

```swift
@CloudKitUUID var studentID: UUID = UUID()

// Access as UUID
let id = work.studentID  // UUID type

// Access raw String if needed via projected value
let stringID = work.$studentID  // String type
```

### Why This Works (Unlike @RawCodable)

UUIDs are **not used in Predicate comparisons**. Queries filter by String ID fields:

```swift
// ✅ WORKS - Predicate doesn't need to access @CloudKitUUID
@CloudKitUUID var studentID: UUID = UUID()

// Query uses String comparison
let idString = student.id.uuidString
@Query(filter: #Predicate<WorkModel> { $0.studentIDString == idString })
```

### Benefits

- ✅ Type safety: Only UUID values accepted
- ✅ No manual conversions needed
- ✅ CloudKit compatible (stores as String)
- ✅ No Predicate conflicts (UUIDs not queried)

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
