# ADR-003: Repository Pattern Usage

**Status:** ✅ Accepted (Pragmatic Approach)
**Date:** 2026-01 (Adopted), 2026-02 (Documented)
**Deciders:** Development Team
**Tags:** `architecture`, `data-access`, `testing`, `swiftdata`

## Context

SwiftData provides `@Query` for direct data access in views, but this creates tight coupling and testing challenges for complex business logic.

### The Problem

**Direct @Query in Views:**
```swift
struct StudentListView: View {
    @Query(sort: \Student.lastName) var students: [Student]

    var body: some View {
        List(students) { student in
            StudentRow(student)
        }
    }
}
```

**Issues:**
- ❌ Views directly coupled to data layer
- ❌ Hard to test (requires ModelContext)
- ❌ Business logic mixed with UI
- ❌ Can't mock data for previews
- ❌ Complex queries clutter view code

## Decision

Use **Repository Pattern** for complex data access, but **keep @Query for simple cases**.

### Pragmatic Approach (Phase 3 Guidelines)

**Use Repositories For:**
1. ✅ ViewModels (always)
2. ✅ Complex queries with business logic
3. ✅ Bulk operations
4. ✅ Code that needs testing
5. ✅ Validation and business rules

**Keep @Query For:**
1. ✅ Simple list views (basic display)
2. ✅ Single entity fetch by ID
3. ✅ No business logic involved
4. ✅ Prototyping/quick views

### Repository Pattern

```swift
@MainActor
struct StudentRepository: SavingRepository {
    typealias Model = Student

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    // MARK: - Fetch

    func fetchStudent(id: UUID) throws -> Student {
        var descriptor = FetchDescriptor<Student>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        guard let student = try context.fetch(descriptor).first else {
            throw StudentError.notFound(id: id)
        }

        return student
    }

    func fetchStudents(
        predicate: Predicate<Student>? = nil,
        sortBy: [SortDescriptor<Student>] = [
            SortDescriptor(\.lastName),
            SortDescriptor(\.firstName)
        ]
    ) throws -> [Student] {
        var descriptor = FetchDescriptor<Student>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy

        return try context.fetch(descriptor)
    }

    // MARK: - Create

    @discardableResult
    func createStudent(
        firstName: String,
        lastName: String,
        birthday: Date
    ) throws -> Student {
        // Validation
        guard !firstName.isEmpty else {
            throw StudentError.missingRequiredField(field: "First Name")
        }

        // Business rule check
        if try checkDuplicateName(firstName: firstName, lastName: lastName) {
            throw StudentError.duplicateName(firstName: firstName, lastName: lastName)
        }

        // Create & save
        let student = Student(firstName: firstName, lastName: lastName, birthday: birthday)
        context.insert(student)
        try context.save()

        return student
    }

    // MARK: - Delete

    func deleteStudent(id: UUID) throws {
        let student = try fetchStudent(id: id)

        // Business rule: Check for active lessons
        let lessonCount = countActiveLessons(for: student)
        if lessonCount > 0 {
            throw StudentError.cannotDeleteWithActiveLessons(
                studentName: student.fullName,
                lessonCount: lessonCount
            )
        }

        context.delete(student)
        try context.save()
    }
}
```

## Consequences

### Positive

✅ **Testable Data Access**
```swift
func testDeleteStudentWithLessons() throws {
    let repository = StudentRepository(context: testContext)
    let student = try repository.createStudent(...)
    let _ = createTestLesson(for: student)

    #expect(throws: StudentError.cannotDeleteWithActiveLessons) {
        try repository.deleteStudent(id: student.id)
    }
}
```

✅ **Type-Safe Queries**
- Compile-time safety for predicates
- Reusable query logic
- Consistent error handling

✅ **Business Logic Encapsulation**
- Validation in one place
- Enforceable business rules
- Clear separation of concerns

✅ **Mockable for Testing**
```swift
protocol StudentRepositoryProtocol {
    func fetchStudents() throws -> [Student]
}

struct MockStudentRepository: StudentRepositoryProtocol {
    func fetchStudents() -> [Student] {
        [Student.mock1, Student.mock2]
    }
}
```

✅ **Coordinated Saves**
- `SavingRepository` protocol
- `SaveCoordinator` integration
- Consistent error handling

### Negative

❌ **More Boilerplate**
- Each repository ~150 lines
- 14 repositories created so far
- Repetitive CRUD methods

❌ **Migration Burden**
- Not all views migrated yet
- Inconsistent patterns during transition
- Some duplicate logic (view + repository)

❌ **Learning Curve**
- Team must understand pattern
- When to use repository vs @Query

### Neutral

⚠️ **Pragmatic, Not Dogmatic**
- Simple views can keep @Query
- Migrate on-touch (when editing anyway)
- Don't over-engineer

## Implementation Status

### Repositories Created (14)

1. ✅ `StudentRepository`
2. ✅ `LessonRepository`
3. ✅ `WorkRepository`
4. ✅ `AttendanceRepository`
5. ✅ `NoteRepository`
6. ✅ `PresentationRepository`
7. ✅ `WorkStepRepository`
8. ✅ `WorkCheckInRepository`
9. ✅ `ProjectRepository`
10. ✅ `TrackRepository`
11. ✅ `ReminderRepository`
12. ✅ `CalendarEventRepository`
13. ✅ `SupplyRepository`
14. ✅ `ProcedureRepository`

### ViewModels Using Repositories

- ✅ `PresentationsViewModel` (uses `PresentationRepository`)
- ✅ `TodayViewModel` (uses multiple repositories)
- ⚠️ `AttendanceViewModel` (partial migration)
- ❌ Many ViewModels still pending

### Views Still Using @Query

**Acceptable (Simple Lists):**
- `StudentListView` - Basic student list
- `LessonListView` - Basic lesson list
- `SupplyListView` - Simple supply inventory

**Should Migrate (Complex Logic):**
- Some detail views with business rules
- Views with complex filtering
- Views that need testing

## Standard Patterns

### Pattern 1: Basic Repository
```swift
@MainActor
struct EntityRepository: SavingRepository {
    typealias Model = Entity

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    func fetch(id: UUID) throws -> Entity
    func fetchAll() throws -> [Entity]
    func create(...) throws -> Entity
    func update(id: UUID, ...) throws
    func delete(id: UUID) throws
}
```

### Pattern 2: ViewModel Integration
```swift
@Observable
class FeatureViewModel {
    var items: [Item] = []
    private let repository: ItemRepository

    init(repository: ItemRepository) {
        self.repository = repository
    }

    func load() {
        do {
            items = try repository.fetchAll()
        } catch {
            // Handle error
        }
    }
}
```

### Pattern 3: Dependency Injection
```swift
// In AppDependencies
struct RepositoryContainer {
    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    var students: StudentRepository {
        StudentRepository(context: context, saveCoordinator: saveCoordinator)
    }

    var lessons: LessonRepository {
        LessonRepository(context: context, saveCoordinator: saveCoordinator)
    }
}

// Usage
@Environment(\.dependencies) var dependencies
let repository = dependencies.repositories.students
```

## SavingRepository Protocol

```swift
protocol SavingRepository {
    associatedtype Model

    var context: ModelContext { get }
    var saveCoordinator: SaveCoordinator? { get }
}

extension SavingRepository {
    func save() throws {
        do {
            try context.save()
        } catch {
            saveCoordinator?.handleSaveError(error)
            throw error
        }
    }
}
```

Benefits:
- Consistent error handling across all repos
- Toast notifications on save errors
- Centralized save coordination

## Guidelines

### When to Create a Repository

**YES - Create Repository:**
- ✅ Entity has business rules
- ✅ Complex queries needed
- ✅ Bulk operations required
- ✅ Needs testing
- ✅ Used by ViewModels

**NO - Use @Query:**
- ✅ Simple display-only list
- ✅ Single entity fetch
- ✅ No validation needed
- ✅ Prototyping/exploration

### Migration Strategy

**On-Touch Approach:**
1. When editing a ViewModel, migrate to repository
2. When adding business rules, create repository
3. When writing tests, use repository
4. Don't migrate simple views unnecessarily

**Not a Big Bang:**
- Migrate incrementally
- Both patterns coexist
- Prioritize high-value migrations

## Alternatives Considered

### 1. Always Use @Query
**Rejected:** Hard to test, business logic in views, tight coupling.

### 2. Always Use Repositories
**Rejected:** Over-engineering simple cases, unnecessary boilerplate.

### 3. Service Layer Only (No Repositories)
**Rejected:** Services for business logic, repositories for data access; both needed.

### 4. Generic Repository<T>
```swift
struct Repository<T: PersistentModel> {
    func fetch(id: UUID) -> T?
    func fetchAll() -> [T]
}
```
**Rejected:** Loses type-specific logic; awkward with SwiftData's Predicate system.

## Related Decisions

- See [ADR-002](ADR-002-domain-errors.md) for error handling in repositories
- See [ADR-004](ADR-004-dependency-injection.md) for repository injection
- See [ARCHITECTURE.md](../ARCHITECTURE.md) for ViewModel guidelines

## References

- Code: `Repositories/` folder
- Example: `Repositories/StudentRepository.swift`
- Example: `Errors/StudentRepositoryExample.swift` (with domain errors)
- Protocol: `Repositories/SavingRepository.swift`

## Revision History

| Date | Author | Change |
|------|--------|--------|
| 2026-01 | Team | Adopted pragmatic repository pattern |
| 2026-02-13 | Architecture Migration | Documented as ADR-003 |

---

**Next ADR:** [ADR-004: Dependency Injection Approach](ADR-004-dependency-injection.md)
