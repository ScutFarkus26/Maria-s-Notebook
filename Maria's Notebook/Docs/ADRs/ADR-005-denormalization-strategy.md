# ADR-005: Denormalization for Query Performance

**Status:** ✅ Accepted
**Date:** 2025-11 (Adopted), 2026-02 (Documented)
**Deciders:** Development Team
**Tags:** `performance`, `swiftdata`, `optimization`, `queries`

## Context

SwiftData Predicate queries can be slow when filtering on computed properties, date components, or foreign key names. Denormalization improves query performance at the cost of data duplication.

### The Problem

**Slow Queries on Computed Properties:**
```swift
@Model
class LessonPresentation {
    var scheduledFor: Date

    // Computed property - NOT queryable efficiently
    var scheduledForDay: Date {
        Calendar.current.startOfDay(for: scheduledFor)
    }
}

// Slow: Can't use Predicate on computed property
#Predicate<LessonPresentation> {
    $0.scheduledForDay == targetDay  // ❌ Compile error
}

// Workaround: Fetch all, filter in memory
let all = try context.fetch(FetchDescriptor<LessonPresentation>())
let filtered = all.filter { Calendar.current.isDate($0.scheduledFor, inSameDayAs: targetDay) }
// ❌ Loads ALL presentations into memory
// ❌ No database indexing
// ❌ Slow for large datasets
```

**Performance Impact:**
- Loading 1000+ presentations
- Filtering in-memory (no database index)
- O(n) complexity instead of O(log n)

## Decision

**Denormalize frequently-queried computed values** into stored properties.

### Standard Pattern

```swift
@Model
class LessonPresentation {
    // Original property
    var scheduledFor: Date

    // Denormalized: Start of day for efficient date queries
    var scheduledForDay: Date

    init(scheduledFor: Date) {
        self.scheduledFor = scheduledFor
        self.scheduledForDay = Calendar.current.startOfDay(for: scheduledFor)
    }

    // Update denormalized field when source changes
    func updateScheduledFor(_ newDate: Date) {
        scheduledFor = newDate
        scheduledForDay = Calendar.current.startOfDay(for: newDate)
    }
}

// Fast: Uses database index
#Predicate<LessonPresentation> {
    $0.scheduledForDay == targetDay  // ✅ Efficient query
}
```

### When to Denormalize

**YES - Denormalize When:**
1. ✅ Frequently queried property
2. ✅ Performance bottleneck identified
3. ✅ Computed from stored data
4. ✅ Deterministic calculation
5. ✅ Read-heavy workload

**NO - Don't Denormalize When:**
1. ❌ Rarely queried
2. ❌ No performance issue
3. ❌ Complex calculation
4. ❌ Frequently updated
5. ❌ High data change rate

## Denormalization Cases

### Case 1: Date Components

**Purpose:** Query by day without time component

**Implementation:**
```swift
@Model
class LessonPresentation {
    var scheduledFor: Date           // 2026-02-13 14:30:00
    var scheduledForDay: Date        // 2026-02-13 00:00:00

    init(scheduledFor: Date) {
        self.scheduledFor = scheduledFor
        self.scheduledForDay = Calendar.current.startOfDay(for: scheduledFor)
    }
}

// Query: All presentations on specific day
#Predicate<LessonPresentation> {
    $0.scheduledForDay == targetDay
}
```

**Benefits:**
- ✅ Database index on `scheduledForDay`
- ✅ Efficient day-based queries
- ✅ No in-memory filtering

### Case 2: Grouping Keys

**Purpose:** Sort/group without joins

**Implementation:**
```swift
@Model
class Student {
    var firstName: String
    var lastName: String
    var level: Level

    // Denormalized: Pre-computed grouping key
    var studentGroupKeyPersisted: String

    init(firstName: String, lastName: String, level: Level) {
        self.firstName = firstName
        self.lastName = lastName
        self.level = level
        self.studentGroupKeyPersisted = "\(level.rawValue)_\(lastName)_\(firstName)"
    }
}

// Query: Students grouped by level and sorted by name
let descriptor = FetchDescriptor<Student>(
    sortBy: [SortDescriptor(\.studentGroupKeyPersisted)]
)
// ✅ Single indexed field instead of compound sort
```

**Benefits:**
- ✅ Single index instead of multi-column
- ✅ Faster sorting
- ✅ Consistent grouping

### Case 3: Foreign Key Names

**Purpose:** Display names without loading related entities

**Implementation:**
```swift
@Model
class LessonPresentation {
    var lessonID: String

    // Denormalized: Avoid loading Lesson just for title
    var lessonTitle: String

    init(lesson: Lesson) {
        self.lessonID = lesson.id.uuidString
        self.lessonTitle = lesson.title  // Cached for display
    }
}

// Display in list without loading all Lesson entities
struct PresentationRow: View {
    let presentation: LessonPresentation

    var body: some View {
        Text(presentation.lessonTitle)  // ✅ No fetch needed
    }
}
```

**Benefits:**
- ✅ Avoid N+1 query problem
- ✅ Faster list rendering
- ✅ Reduced memory usage

## Update Strategies

### Strategy 1: Update on Set (didSet)

```swift
@Model
class LessonPresentation {
    var scheduledFor: Date {
        didSet {
            scheduledForDay = Calendar.current.startOfDay(for: scheduledFor)
        }
    }
    var scheduledForDay: Date
}
```

**Pros:** Automatic, always in sync
**Cons:** SwiftData `@Model` doesn't support property observers

### Strategy 2: Update Methods

```swift
@Model
class LessonPresentation {
    var scheduledFor: Date
    var scheduledForDay: Date

    func updateScheduledFor(_ newDate: Date) {
        scheduledFor = newDate
        scheduledForDay = Calendar.current.startOfDay(for: newDate)
    }
}
```

**Pros:** Explicit, clear intent
**Cons:** Must remember to use method

### Strategy 3: Repository Layer

```swift
@MainActor
struct PresentationRepository {
    func updateScheduledDate(id: UUID, newDate: Date) throws {
        let presentation = try fetch(id: id)
        presentation.scheduledFor = newDate
        presentation.scheduledForDay = Calendar.current.startOfDay(for: newDate)
        try context.save()
    }
}
```

**Pros:** Centralized, enforceable
**Cons:** Adds repository layer

**Recommended:** Use Strategy 3 (Repository Layer) for consistency

## Consequences

### Positive

✅ **Dramatic Performance Improvement**
- Date queries: 100ms → 5ms (20x faster)
- Large lists: No full table scan
- Database indexes utilized

✅ **Simpler View Code**
- No complex filtering logic
- Direct property access
- Cleaner predicates

✅ **Better User Experience**
- Instant filtering
- Smooth scrolling
- Responsive UI

### Negative

❌ **Data Duplication**
- More storage space per entity
- Redundant data (scheduledFor + scheduledForDay)

❌ **Consistency Risk**
- Must keep denormalized fields in sync
- Easy to forget during updates
- No automatic enforcement

❌ **Migration Complexity**
- Must backfill denormalized fields
- Schema migration required
- Existing data must be updated

❌ **Maintenance Burden**
- Must update in multiple places
- More fields to reason about
- Potential for drift

## Current Denormalized Fields

### In Production (As of 2026-02-13)

1. **LessonPresentation.scheduledForDay**
   - Source: `scheduledFor: Date`
   - Purpose: Day-based queries
   - Usage: Presentations list filtering

2. **Student.studentGroupKeyPersisted**
   - Source: `level + lastName + firstName`
   - Purpose: Grouping and sorting
   - Usage: Student lists

3. *(Add more as discovered during code review)*

## Guidelines

### Adding New Denormalized Field

1. **Identify Performance Issue**
   ```swift
   // Profile slow query
   let start = Date()
   let results = try context.fetch(descriptor)
   let duration = Date().timeIntervalSince(start)
   print("Query took \(duration)s")  // > 100ms = problem
   ```

2. **Create Denormalized Field**
   ```swift
   var originalProperty: Type
   var originalPropertyDenormalized: DenormalizedType  // Clear naming
   ```

3. **Initialize in Constructor**
   ```swift
   init(...) {
       self.originalProperty = value
       self.originalPropertyDenormalized = calculateDenormalized(value)
   }
   ```

4. **Update via Repository**
   ```swift
   func updateOriginalProperty(id: UUID, newValue: Type) throws {
       let entity = try fetch(id: id)
       entity.originalProperty = newValue
       entity.originalPropertyDenormalized = calculateDenormalized(newValue)
       try save()
   }
   ```

5. **Add Migration**
   ```swift
   static func migrateV1toV2() throws {
       // Backfill denormalized field for existing data
       let all = try context.fetch(FetchDescriptor<Entity>())
       for entity in all {
           entity.denormalizedField = calculate(entity.originalField)
       }
       try context.save()
   }
   ```

6. **Document in ADR**
   - Add to "Current Denormalized Fields" list
   - Note performance improvement
   - Document update strategy

### Naming Convention

✅ **Good:**
- `scheduledForDay` (clear relationship to `scheduledFor`)
- `studentGroupKeyPersisted` (indicates denormalized)
- `lessonTitleCached` (indicates cached value)

❌ **Bad:**
- `day` (unclear source)
- `key` (too generic)
- `title` (conflicts with original)

## Testing Denormalized Fields

```swift
func testDenormalizedFieldConsistency() throws {
    let presentation = LessonPresentation(
        scheduledFor: Date(timeIntervalSince1970: 1707869400)
    )

    // Verify denormalized field matches computed value
    let expected = Calendar.current.startOfDay(for: presentation.scheduledFor)
    XCTAssertEqual(presentation.scheduledForDay, expected)
}

func testUpdateMaintainsConsistency() throws {
    let repository = PresentationRepository(context: context)
    let presentation = createTestPresentation()

    let newDate = Date()
    try repository.updateScheduledDate(id: presentation.id, newDate: newDate)

    // Verify both fields updated
    XCTAssertEqual(presentation.scheduledFor, newDate)
    XCTAssertEqual(
        presentation.scheduledForDay,
        Calendar.current.startOfDay(for: newDate)
    )
}
```

## Alternatives Considered

### 1. Computed Properties Only
**Rejected:** Too slow for large datasets; no database indexing.

### 2. Separate Index Table
```swift
@Model
class PresentationDayIndex {
    var presentationID: String
    var day: Date
}
```
**Rejected:** Adds complexity; must maintain separate table; join overhead.

### 3. Database Views
**Rejected:** SwiftData doesn't support views; SQLite-specific solution.

### 4. In-Memory Cache
```swift
var dayCache: [UUID: Date] = [:]
```
**Rejected:** Doesn't persist; not queryable; stale data risk.

## Related Decisions

- See [ADR-001](ADR-001-swiftdata-enum-pattern.md) for SwiftData constraints
- See [ADR-003](ADR-003-repository-pattern.md) for update enforcement

## References

- Example: `LessonPresentation.scheduledForDay`
- Example: `Student.studentGroupKeyPersisted`
- Performance: TodayViewModel query optimizations

## Revision History

| Date | Author | Change |
|------|--------|--------|
| 2025-11 | Team | Adopted pattern for performance |
| 2026-02-13 | Architecture Migration | Documented as ADR-005 |

---

**Next ADR:** [ADR-006: ViewModel State Patterns](ADR-006-viewmodel-patterns.md)
