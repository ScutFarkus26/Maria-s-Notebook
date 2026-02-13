# Error Handling Guidelines

**Created:** 2026-02-13
**Phase:** 4 - Error Handling Standardization
**Purpose:** Document error handling patterns and best practices for Maria's Notebook

---

## Table of Contents

1. [Overview](#overview)
2. [Current State](#current-state)
3. [Error Handling Patterns](#error-handling-patterns)
4. [When to Create Custom Errors](#when-to-create-custom-errors)
5. [Best Practices](#best-practices)
6. [Examples](#examples)
7. [Migration Strategy](#migration-strategy)

---

## Overview

### Why Error Handling Matters

Good error handling:
- ✅ **Helps users** - Clear, actionable error messages
- ✅ **Aids debugging** - Detailed error context for developers
- ✅ **Enables recovery** - Users can fix issues and retry
- ✅ **Prevents crashes** - Graceful error handling prevents app crashes
- ✅ **Improves UX** - Better than generic "Something went wrong"

### Swift Error Handling

Swift provides several error handling mechanisms:
```swift
// 1. Simple Error throwing
func doSomething() throws -> Result

// 2. Typed errors (Swift 6+)
func doSomething() throws(MyError) -> Result

// 3. Result type
func doSomething() -> Result<Value, Error>

// 4. Optional (for simple cases)
func doSomething() -> Value?
```

---

## Current State

### Existing Error Types

**Audit Results:**
- **Comprehensive:** `BackupOperationError` (253 lines, excellent pattern)
- **Simple:** ~10 other error enums across the codebase
- **Most code:** Uses generic `Error` or doesn't throw

**File Distribution:**
- Backup system: Comprehensive typed errors ✅
- CSV importers: Custom error enums ✅
- Services: Mostly generic `Error`
- Repositories: Generic `Error` or no throws
- Views: Error handling via SaveCoordinator

### Excellent Example: BackupOperationError

Location: `Maria's Notebook/Backup/Core/BackupErrors.swift`

**Pattern:**
```swift
public enum BackupOperationError: Error, Sendable {
    case exportFailed(ExportError)
    case importFailed(ImportError)
    case validationFailed(ValidationError)

    public enum ExportError: Error, Sendable {
        case contextUnavailable
        case entityFetchFailed(entityType: String, underlying: Error)
        case encodingFailed(underlying: Error)
        // ... more cases
    }
}

extension BackupOperationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .exportFailed(let error):
            return "Export failed: \\(error.localizedDescription)"
        // ... more cases
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .exportFailed(.insufficientDiskSpace(let required, let available)):
            return "Free up at least \\(formatter.string(fromByteCount: required - available))..."
        // ... more cases
        }
    }
}

extension BackupOperationError {
    public var isRecoverable: Bool { ... }
    public var shouldRetry: Bool { ... }
}
```

**Why This is Excellent:**
- ✅ Hierarchical structure (domain -> subdomain -> specific error)
- ✅ Associated values for context (URLs, counts, reasons)
- ✅ LocalizedError conformance for user-friendly messages
- ✅ Recovery suggestions for user guidance
- ✅ Utility properties (isRecoverable, shouldRetry)
- ✅ Sendable conformance for Swift 6 concurrency

---

## Error Handling Patterns

### Pattern 1: Hierarchical Domain Errors

**Use When:** Complex subsystem with multiple error categories

**Structure:**
```swift
enum DomainError: Error, Sendable {
    case categoryA(CategoryAError)
    case categoryB(CategoryBError)
    case categoryC(CategoryCError)

    enum CategoryAError: Error, Sendable {
        case specificError1
        case specificError2(reason: String)
        case specificError3(underlying: Error)
    }

    enum CategoryBError: Error, Sendable {
        case specificError4
        case specificError5(url: URL)
    }
}
```

**Example:** `BackupOperationError` (already implemented)

**Benefits:**
- Clear error categorization
- Type-safe error handling
- Exhaustive switch statements
- Easy to add new error types

---

### Pattern 2: Simple Domain Errors

**Use When:** Service has 5-10 distinct error cases

**Structure:**
```swift
enum ServiceError: Error, LocalizedError {
    case invalidInput(String)
    case notFound(id: UUID)
    case permissionDenied
    case operationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let reason):
            return "Invalid input: \\(reason)"
        case .notFound(let id):
            return "Item not found: \\(id)"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .operationFailed(let error):
            return "Operation failed: \\(error.localizedDescription)"
        }
    }
}
```

**Example:** CSV importers (StudentCSVImporter, LessonCSVImporter)

**Benefits:**
- Simpler than hierarchical
- Still type-safe
- Good error messages
- Easy to maintain

---

### Pattern 3: Result Type

**Use When:** Function has clear success/failure outcomes, no exceptions

**Structure:**
```swift
func performOperation() -> Result<SuccessType, OperationError> {
    guard condition else {
        return .failure(.invalidInput("reason"))
    }

    return .success(value)
}

// Usage
switch performOperation() {
case .success(let value):
    // Handle success
case .failure(let error):
    // Handle error
}
```

**Benefits:**
- Explicit success/failure handling
- Forces error handling at call site
- No try/catch needed
- Good for async completion handlers

---

### Pattern 4: Optional for Simple Cases

**Use When:** Failure doesn't need detailed error information

**Structure:**
```swift
func fetchItem(id: UUID) -> Item? {
    // Return nil if not found
    return repository.fetch(id: id)
}

// Usage
guard let item = fetchItem(id: id) else {
    // Handle not found
    return
}
```

**Benefits:**
- Simplest approach
- Good for lookups
- No error context needed
- Clean code

**Drawbacks:**
- No error information
- Can't distinguish failure reasons
- Not suitable for operations that need recovery

---

## When to Create Custom Errors

### ✅ Create Custom Error Enum When:

1. **Multiple Distinct Failures** - Operation can fail in 5+ different ways
2. **Need Context** - Errors need associated data (IDs, URLs, counts)
3. **User-Facing** - Errors will be shown to users
4. **Recovery Possible** - User can take action to fix the error
5. **Complex Domain** - Subsystem with multiple error categories (like Backup)

**Example:**
```swift
// Good: Multiple failures with context
enum StudentImportError: Error {
    case fileNotFound(URL)
    case invalidFormat(row: Int, reason: String)
    case duplicateStudent(name: String)
    case validationFailed(field: String, reason: String)
}
```

### ❌ Keep Generic Error When:

1. **Simple Failure** - Only one way to fail
2. **Pass-Through** - Just forwarding errors from underlying APIs
3. **Internal Only** - Error never shown to users
4. **Rare** - Error almost never happens
5. **No Recovery** - Nothing user can do about it

**Example:**
```swift
// Fine: Simple pass-through
func saveData() throws {
    try context.save() // Just forwarding SwiftData error
}
```

---

## Best Practices

### 1. LocalizedError Conformance

**Always** conform custom errors to `LocalizedError`:

```swift
extension MyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .someCase:
            return "User-friendly description"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .someCase:
            return "Try doing X or Y"
        }
    }
}
```

**Why:**
- Provides user-friendly error messages
- Works with SwiftUI's `.alert(error:)` modifier
- Standard Swift error presentation

---

### 2. Associated Values for Context

**Include context** that helps debugging and recovery:

```swift
// ❌ Bad: No context
enum MyError: Error {
    case failed
}

// ✅ Good: Includes context
enum MyError: Error {
    case fetchFailed(entityType: String, id: UUID, underlying: Error)
    case saveFailed(reason: String, entityCount: Int)
}
```

---

### 3. Wrap Underlying Errors

**Preserve original errors** when wrapping:

```swift
enum ServiceError: Error {
    case databaseError(underlying: Error)
    case networkError(underlying: Error)
}

func fetchData() throws -> Data {
    do {
        return try database.fetch()
    } catch {
        throw ServiceError.databaseError(underlying: error)
    }
}
```

**Why:**
- Preserves stack trace
- Aids debugging
- Doesn't lose information

---

### 4. Sendable Conformance

**Mark errors Sendable** for Swift 6 concurrency:

```swift
enum MyError: Error, Sendable {
    case someCase
}
```

**Why:**
- Required for async/await
- Swift 6 compatibility
- Thread-safe error passing

---

### 5. Recovery Information

**Add utility properties** for error handling:

```swift
extension MyError {
    var isRecoverable: Bool {
        switch self {
        case .networkError: return true
        case .validationError: return true
        case .internalError: return false
        }
    }

    var shouldRetry: Bool {
        switch self {
        case .networkError: return true
        default: return false
        }
    }

    var severity: ErrorSeverity {
        switch self {
        case .networkError: return .warning
        case .internalError: return .critical
        default: return .error
        }
    }
}

enum ErrorSeverity {
    case info, warning, error, critical
}
```

---

## Examples

### Example 1: Service Error (Recommended Pattern)

```swift
enum StudentServiceError: Error, LocalizedError, Sendable {
    case studentNotFound(id: UUID)
    case duplicateName(firstName: String, lastName: String)
    case invalidAge(age: Int)
    case databaseError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .studentNotFound(let id):
            return "Student not found: \\(id)"
        case .duplicateName(let first, let last):
            return "A student named \\(first) \\(last) already exists"
        case .invalidAge(let age):
            return "Invalid age: \\(age). Age must be between 5 and 18."
        case .databaseError(let error):
            return "Database error: \\(error.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .duplicateName:
            return "Choose a different name or edit the existing student."
        case .invalidAge:
            return "Enter an age between 5 and 18."
        default:
            return nil
        }
    }
}
```

### Example 2: Repository Error Handling

```swift
struct StudentRepository: SavingRepository {
    func create(firstName: String, lastName: String, age: Int) throws -> Student {
        // Validate input
        guard age >= 5 && age <= 18 else {
            throw StudentServiceError.invalidAge(age: age)
        }

        // Check for duplicates
        if let existing = fetchStudent(firstName: firstName, lastName: lastName) {
            throw StudentServiceError.duplicateName(firstName: firstName, lastName: lastName)
        }

        // Create student
        let student = Student(firstName: firstName, lastName: lastName, age: age)
        context.insert(student)

        // Save
        do {
            try context.save()
        } catch {
            throw StudentServiceError.databaseError(underlying: error)
        }

        return student
    }
}
```

### Example 3: View Error Handling

```swift
struct StudentCreateView: View {
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var age = 10
    @State private var error: StudentServiceError?
    @State private var showError = false

    var body: some View {
        Form {
            TextField("First Name", text: $firstName)
            TextField("Last Name", text: $lastName)
            Stepper("Age: \\(age)", value: $age, in: 5...18)

            Button("Create") {
                createStudent()
            }
        }
        .alert("Error", isPresented: $showError, presenting: error) { _ in
            Button("OK") { }
        } message: { error in
            VStack(alignment: .leading) {
                Text(error.localizedDescription)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                }
            }
        }
    }

    private func createStudent() {
        do {
            let student = try repository.create(
                firstName: firstName,
                lastName: lastName,
                age: age
            )
            // Success
        } catch let error as StudentServiceError {
            self.error = error
            self.showError = true
        } catch {
            // Unexpected error
            print("Unexpected error: \\(error)")
        }
    }
}
```

### Example 4: Async Error Handling

```swift
enum NetworkError: Error, LocalizedError, Sendable {
    case offline
    case timeout
    case serverError(statusCode: Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .offline:
            return "No internet connection"
        case .timeout:
            return "Request timed out"
        case .serverError(let code):
            return "Server error: \\(code)"
        case .invalidResponse:
            return "Invalid server response"
        }
    }
}

func fetchData() async throws -> Data {
    guard isOnline else {
        throw NetworkError.offline
    }

    let (data, response) = try await URLSession.shared.data(from: url)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw NetworkError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        throw NetworkError.serverError(statusCode: httpResponse.statusCode)
    }

    return data
}
```

---

## Migration Strategy

### Pragmatic Approach (Recommended)

**Don't force error migrations**. Use custom errors when:
1. Adding new features
2. Refactoring existing code
3. Improving error UX
4. Debugging issues

**Keep generic Error when:**
1. Simple operations
2. Pass-through errors
3. Internal-only code
4. Works fine as-is

### Priority Order

**1. User-Facing Operations** (HIGH)
- Student/Lesson creation
- Data import/export
- Sync operations
- File operations

**2. Critical Services** (MEDIUM)
- Backup/restore (already done ✅)
- Database operations
- Network requests
- Permission requests

**3. Internal Operations** (LOW)
- Simple lookups
- Calculations
- Formatting
- Utilities

---

## Error Display Utilities

### SaveCoordinator Integration

Maria's Notebook already has good error handling via `SaveCoordinator`:

```swift
// SaveCoordinator already handles save errors
func save(_ context: ModelContext, reason: String? = nil) -> Bool {
    do {
        try context.save()
        return true
    } catch {
        lastSaveError = error
        lastSaveErrorMessage = reason ?? "Save failed"
        isShowingSaveError = true
        return false
    }
}
```

**Usage:**
```swift
// In repository
func deleteStudent(_ student: Student) {
    context.delete(student)
    save(reason: "Deleting student")  // SaveCoordinator handles errors
}
```

### ToastService Integration

Use `ToastService` for non-critical errors:

```swift
// For recoverable errors
do {
    try performOperation()
    toastService.showSuccess("Operation completed")
} catch {
    toastService.showError("Operation failed: \\(error.localizedDescription)")
}
```

---

## Success Criteria

✅ **Phase 4 Complete When:**
1. Error handling patterns documented (this file) ✅
2. Examples provided for each pattern ✅
3. Migration strategy defined ✅
4. Existing excellent patterns identified (BackupOperationError) ✅
5. Integration with SaveCoordinator/ToastService documented ✅

**No code changes required** - patterns already exist, just need documentation and adoption over time.

---

## Related Documentation

- `BackupErrors.swift` - Excellent example to follow
- `SaveCoordinator.swift` - Error handling for saves
- `ToastService.swift` - Error display service
- `PHASE4_COMPLETION.md` - Phase completion report

---

## Conclusion

Maria's Notebook already has excellent error handling in the Backup system (`BackupOperationError`). This pattern should be followed for new code:

**Key Takeaways:**
1. ✅ Use hierarchical errors for complex domains
2. ✅ Use simple enums for services
3. ✅ Always implement `LocalizedError`
4. ✅ Include context via associated values
5. ✅ Add utility properties (isRecoverable, shouldRetry)
6. ✅ Mark errors `Sendable` for Swift 6

**Migration:** Incremental, on-touch basis. No forced migrations.

---

**Document Version:** 1.0
**Last Updated:** 2026-02-13
**Author:** Claude Sonnet 4.5
**Status:** Living Document
