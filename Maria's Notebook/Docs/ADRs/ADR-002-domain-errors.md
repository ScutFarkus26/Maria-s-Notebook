# ADR-002: Domain-Specific Error Types

**Status:** ✅ Accepted
**Date:** 2026-02-13
**Deciders:** Architecture Migration Team
**Tags:** `errors`, `ux`, `type-safety`, `infrastructure`

## Context

The app originally used generic `Error` types throughout, resulting in poor user experience and difficult debugging.

### The Problem

**Before Domain Errors:**
```swift
// Service throws generic error
func deleteStudent(id: UUID) throws {
    try context.delete(student)
    try context.save()  // Generic SwiftData error
}

// View shows vague message
catch {
    showAlert("Error: \(error.localizedDescription)")
    // User sees: "The operation couldn't be completed"
}
```

**User Impact:**
- ❌ Vague error messages ("operation failed")
- ❌ No guidance on how to fix
- ❌ Frustrating user experience
- ❌ Increased support burden

**Developer Impact:**
- ❌ Hard to debug (what failed?)
- ❌ Can't test specific error scenarios
- ❌ Business rules not explicit
- ❌ No error analytics

## Decision

Implement **domain-specific error types** that speak the app's language and provide actionable guidance.

### Architecture

**Base Protocol:**
```swift
protocol AppError: LocalizedError {
    var code: String { get }              // Unique identifier
    var isRecoverable: Bool { get }       // Can user fix?
    var recoverySuggestion: String? { get } // How to fix
    var category: ErrorCategory { get }   // For analytics
    var severity: ErrorSeverity { get }   // Logging level
}
```

**Domain Error Types:**
1. `StudentError` - Student management (10 cases)
2. `LessonError` - Lesson operations (11 cases)
3. `WorkError` - Work items (13 cases)
4. `AttendanceError` - Attendance tracking (10 cases)
5. `SyncError` - CloudKit sync (11 cases)

**Infrastructure:**
- `ErrorHandling.swift` - SwiftUI modifiers, logging, Result extensions
- `ErrorViews.swift` - 3 reusable UI components
- `ErrorPresentation` - Model for custom error UI

### Example Implementation

```swift
enum StudentError: AppError {
    case cannotDeleteWithActiveLessons(studentName: String, lessonCount: Int)

    var errorDescription: String? {
        "Cannot delete student"
    }

    var failureReason: String? {
        "\(studentName) has \(lessonCount) active lessons. Students with active lessons cannot be deleted."
    }

    var recoverySuggestion: String? {
        "Archive or remove \(studentName)'s lessons before deleting, or use the Archive feature."
    }

    var isRecoverable: Bool { true }
    var category: ErrorCategory { .business }
}
```

## Consequences

### Positive

✅ **User-Friendly Messages**
- Clear explanations with context
- Actionable recovery suggestions
- Consistent error experience

✅ **Type-Safe Error Handling**
```swift
catch StudentError.cannotDeleteWithActiveLessons(let name, let count) {
    // Specific handling with full context
}
```

✅ **Self-Documenting Business Rules**
- Errors encode domain constraints
- Easy to understand requirements
- Natural API documentation

✅ **Better Debugging**
- Structured logging with context
- Error categories for filtering
- Severity levels for prioritization

✅ **Testable**
```swift
#expect(throws: StudentError.duplicateName) {
    try repository.createStudent(firstName: "John", lastName: "Doe")
}
```

✅ **Analytics-Ready**
- Track error frequencies
- Monitor recovery success
- Identify problem areas

### Negative

❌ **More Code**
- 59 specific error cases defined
- 2,388 lines of infrastructure
- More verbose than generic errors

❌ **Migration Required**
- Existing code uses generic Error
- Services need updating
- ViewModels need refactoring

❌ **Learning Curve**
- Team must learn new patterns
- Requires consistency discipline

### Neutral

⚠️ **Follows Existing Pattern**
- `BackupOperationError` already used this approach
- Now standardized across all domains

## Implementation

### Phase 1: Infrastructure ✅ COMPLETE
- [x] Base `AppError` protocol
- [x] 5 domain error types (59 cases)
- [x] Error handling utilities
- [x] SwiftUI view modifiers
- [x] 3 reusable error views
- [x] Comprehensive documentation

### Phase 2: Service Migration (Next)
1. Migrate `StudentRepository` (example provided)
2. Migrate `LessonRepository`
3. Migrate `WorkService`
4. Add error handling tests

### Phase 3: ViewModel Migration
1. Store domain errors in ViewModels
2. Use `.errorAlert()` modifier
3. Provide custom error presentations

### Phase 4: UI Polish
1. Replace vague messages
2. Add recovery actions
3. Test error flows

### Phase 5: Analytics (Future)
1. Track error occurrences
2. Monitor recovery rates
3. Identify frequent errors

## Usage Patterns

### Pattern 1: Simple Alert
```swift
struct StudentListView: View {
    @State private var error: (any AppError)?

    var body: some View {
        List { }
            .errorAlert(error: $error)
    }
}
```

### Pattern 2: Custom Actions
```swift
catch StudentError.cannotDeleteWithActiveLessons(let name, let count) {
    errorPresentation = ErrorPresentation(
        title: "Cannot Delete \(name)",
        message: "This student has \(count) active lessons.",
        actions: [
            .init(title: "View Lessons") { navigateToLessons() },
            .init(title: "Archive") { archiveStudent() },
            .init(title: "Cancel", style: .cancel) {}
        ]
    )
}
```

### Pattern 3: Inline Banner
```swift
if let error = bannerError {
    ErrorBanner(error: error) {
        bannerError = nil
    }
}
```

## Error Categories

| Category | Purpose | Examples |
|----------|---------|----------|
| `validation` | User input failures | Invalid date, missing field |
| `notFound` | Entity doesn't exist | Student ID not found |
| `conflict` | Data conflicts | Duplicate name |
| `permission` | Authorization issues | Not signed in |
| `database` | Persistence failures | Save failed |
| `network` | Connectivity issues | No internet |
| `business` | Business rule violations | Can't delete with active items |
| `system` | Framework errors | Photo storage failed |

## Error Severity

| Level | Usage | Impact |
|-------|-------|--------|
| `debug` | Development only | No user impact |
| `info` | Informational | FYI only |
| `warning` | Recoverable | User can fix |
| `error` | Functionality affected | Feature broken |
| `critical` | App unusable | Major failure |

## Alternatives Considered

### 1. Continue with Generic Errors
**Rejected:** Poor UX, hard to debug, no analytics.

### 2. Result Type Everywhere
```swift
func deleteStudent() -> Result<Void, StudentError>
```
**Rejected:** Swift's `throws` is more idiomatic; Result better for async chains.

### 3. Error Codes Only
```swift
enum ErrorCode: Int {
    case studentNotFound = 1001
    case duplicateName = 1002
}
```
**Rejected:** Loses type safety and associated values (context data).

### 4. NSError with UserInfo
**Rejected:** Objective-C legacy pattern; not type-safe; verbose.

## Related Decisions

- See [ADR-001](ADR-001-swiftdata-enum-pattern.md) for enum validation
- See [ADR-004](ADR-004-repository-pattern.md) for data layer integration
- See [ViewState Pattern](ADR-006-viewmodel-patterns.md) for ViewModel integration

## Metrics

**As of 2026-02-13:**
- **10 files created**
- **2,388 lines of code**
- **59 specific error cases**
- **5 domain types**
- **3 UI components**
- **Build status:** ✅ Passing

## References

- Code: `Errors/` folder (all error files)
- Documentation: `Errors/DOMAIN_ERRORS_GUIDE.md`
- Example: `Errors/StudentRepositoryExample.swift`
- Inspiration: `Backup/Core/BackupErrors.swift`

## Revision History

| Date | Author | Change |
|------|--------|--------|
| 2026-02-13 | Architecture Migration | Initial implementation |
| 2026-02-13 | Architecture Migration | Documented as ADR-002 |

---

**Next ADR:** [ADR-003: Repository Pattern Usage](ADR-003-repository-pattern.md)
