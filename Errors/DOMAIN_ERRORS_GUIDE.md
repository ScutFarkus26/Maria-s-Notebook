# Domain Errors Implementation Guide

## Overview

This guide documents the **Domain Error System** for Maria's Notebook. This system provides type-safe, user-friendly error handling that replaces generic `Error` types with specific, actionable domain errors.

## Philosophy

**Domain errors** speak your app's language. Instead of:
> "Error: The operation couldn't be completed"

You get:
> "Cannot delete Maria because she has 5 active lessons. Archive or remove her lessons first."

## Error Types

### Core Protocol: `AppError`

All domain errors conform to `AppError`, which extends `LocalizedError`:

```swift
protocol AppError: LocalizedError {
    var code: String { get }              // Unique error code for logging
    var isRecoverable: Bool { get }       // Can user fix this?
    var recoverySuggestion: String? { get } // How to fix it
    var category: ErrorCategory { get }   // Error category
    var severity: ErrorSeverity { get }   // Logging severity
}
```

### Available Domain Errors

1. **StudentError** - Student management
2. **LessonError** - Lesson operations  
3. **WorkError** - Work item management
4. **AttendanceError** - Attendance tracking
5. **SyncError** - CloudKit sync operations
6. **BackupOperationError** - Backup/restore (already exists)

### Generic Helpers

- **ValidationError** - Quick validation failures
- **DatabaseError** - Database operation wrapper

## Usage Examples

### 1. Basic Error Throwing

```swift
func deleteStudent(id: UUID) throws {
    let student = try fetchStudent(id: id)
    
    // Business rule validation
    let lessonCount = countLessons(for: student)
    if lessonCount > 0 {
        throw StudentError.cannotDeleteWithActiveLessons(
            studentName: student.fullName,
            lessonCount: lessonCount
        )
    }
    
    try performDelete(student)
}
```

### 2. Error Handling in Views

#### Pattern A: Simple Alert

```swift
struct StudentListView: View {
    @State private var error: (any AppError)?
    
    var body: some View {
        List {
            // ... content
        }
        .errorAlert(error: $error)
    }
    
    private func deleteStudent(_ student: Student) {
        do {
            try studentRepository.delete(id: student.id)
        } catch let error as StudentError {
            self.error = error
        } catch {
            self.error = DatabaseError(
                operation: "delete",
                entity: "Student",
                underlying: error
            )
        }
    }
}
```

#### Pattern B: Custom Error Presentation

```swift
struct StudentDetailView: View {
    @State private var errorPresentation: ErrorPresentation?
    
    var body: some View {
        VStack {
            // ... content
        }
        .errorPresentation(presentation: $errorPresentation)
    }
    
    private func deleteStudent() {
        do {
            try studentRepository.delete(id: student.id)
            dismiss()
        } catch StudentError.cannotDeleteWithActiveLessons(let name, let count) {
            // Custom presentation with action
            errorPresentation = ErrorPresentation(
                title: "Cannot Delete \(name)",
                message: "This student has \(count) active lessons.",
                severity: .warning,
                actions: [
                    .init(title: "View Lessons", style: .default, isPreferred: true) {
                        navigateToLessons()
                    },
                    .init(title: "Archive Instead", style: .default) {
                        archiveStudent()
                    },
                    .init(title: "Cancel", style: .cancel) {}
                ]
            )
        } catch {
            errorPresentation = ErrorPresentation(from: error as? AppError ?? DatabaseError(
                operation: "delete",
                entity: "Student",
                underlying: error
            ))
        }
    }
}
```

#### Pattern C: Inline Banner

```swift
struct WorkListView: View {
    @State private var bannerError: (any AppError)?
    
    var body: some View {
        VStack {
            if let error = bannerError {
                ErrorBanner(error: error) {
                    bannerError = nil
                }
                .padding()
            }
            
            List {
                // ... content
            }
        }
    }
}
```

#### Pattern D: Empty State with Retry

```swift
struct SyncStatusView: View {
    @State private var syncError: SyncError?
    
    var body: some View {
        if let error = syncError {
            ErrorEmptyState(error: error) {
                await retrySync()
            }
        } else {
            // Normal content
        }
    }
    
    private func retrySync() async {
        do {
            try await syncService.sync()
            syncError = nil
        } catch let error as SyncError {
            syncError = error
        } catch {
            syncError = .networkUnavailable
        }
    }
}
```

### 3. Error Handling in Services

```swift
@MainActor
final class StudentService {
    func createStudent(firstName: String, lastName: String, birthdate: Date) throws -> Student {
        // Validation
        guard !firstName.isEmpty else {
            throw StudentError.missingRequiredField(field: "First Name")
        }
        
        guard birthdate <= Date() else {
            throw StudentError.invalidBirthdate(date: birthdate)
        }
        
        // Business rule check
        if checkDuplicateName(firstName: firstName, lastName: lastName) {
            throw StudentError.duplicateName(firstName: firstName, lastName: lastName)
        }
        
        // Create student
        let student = Student(firstName: firstName, lastName: lastName, birthdate: birthdate)
        try context.save()
        
        return student
    }
}
```

### 4. Result-Based Error Handling

```swift
func loadStudents() async -> Result<[Student], Error> {
    await resultify {
        try await studentRepository.fetchAll()
    }
}

// Usage
let result = await loadStudents()
switch result {
case .success(let students):
    self.students = students
case .failure(let error as StudentError):
    self.error = error
case .failure(let error):
    self.error = DatabaseError(operation: "fetch", entity: "Student", underlying: error)
}
```

### 5. Error Logging

```swift
do {
    try performOperation()
} catch let error as AppError {
    // Automatic logging with context
    error.log(context: [
        "studentID": student.id.uuidString,
        "operation": "delete"
    ])
    throw error
}
```

### 6. Repository Pattern with Domain Errors

```swift
@MainActor
struct StudentRepository {
    let context: ModelContext
    
    func delete(id: UUID) throws {
        guard let student = fetch(id: id) else {
            throw StudentError.notFound(id: id)
        }
        
        // Business rule validation
        let lessons = fetchLessons(for: student)
        if !lessons.isEmpty {
            throw StudentError.cannotDeleteWithActiveLessons(
                studentName: student.fullName,
                lessonCount: lessons.count
            )
        }
        
        context.delete(student)
        
        do {
            try context.save()
        } catch {
            throw DatabaseError(
                operation: "delete",
                entity: "Student",
                underlying: error
            )
        }
    }
}
```

## Error Categories

| Category | Usage | Examples |
|----------|-------|----------|
| `validation` | User input validation | Invalid birthdate, missing field |
| `notFound` | Entity not found | Student ID doesn't exist |
| `conflict` | Data conflicts | Duplicate name, version mismatch |
| `permission` | Permission issues | Not signed in to iCloud |
| `database` | Persistence failures | Save failed, fetch error |
| `network` | Network/sync issues | No connection, timeout |
| `business` | Business rule violations | Cannot delete with active lessons |
| `system` | System/framework errors | Photo storage failed |

## Error Severity

| Level | Usage | Logging |
|-------|-------|---------|
| `debug` | Development-only | `logger.debug()` |
| `info` | Informational | `logger.info()` |
| `warning` | Recoverable issues | `logger.warning()` |
| `error` | Functionality affected | `logger.error()` |
| `critical` | App may not function | `logger.critical()` |

## Best Practices

### 1. Always Provide Context

❌ **Bad:**
```swift
throw StudentError.notFound(id: id)
```

✅ **Good:**
```swift
catch {
    error.log(context: [
        "operation": "deleteStudent",
        "studentID": id.uuidString,
        "lessonCount": lessons.count
    ])
    throw error
}
```

### 2. Use Specific Errors

❌ **Bad:**
```swift
throw ValidationError(field: "student", reason: "invalid", value: nil)
```

✅ **Good:**
```swift
throw StudentError.duplicateName(firstName: "John", lastName: "Doe")
```

### 3. Handle Errors at the Right Level

- **Services**: Throw domain errors
- **ViewModels**: Catch and store errors
- **Views**: Display errors to users

### 4. Provide Actionable Recovery

❌ **Bad:**
```swift
recoverySuggestion: "Fix the error and try again."
```

✅ **Good:**
```swift
recoverySuggestion: "Archive or remove Maria's 5 lessons before deleting, or use the Archive feature."
```

### 5. Log Before Throwing (in services)

```swift
func deleteStudent(id: UUID) throws {
    do {
        // operation
    } catch let error as AppError {
        error.log(context: ["studentID": id.uuidString])
        throw error
    }
}
```

## Migration Strategy

### Phase 1: Add Domain Errors (✅ Complete)
- Created error types
- Created utilities and views
- This guide

### Phase 2: Update Services (Next)
1. Start with high-value services (StudentRepository, WorkService)
2. Replace `throws` with specific domain errors
3. Add error logging
4. Update tests

### Phase 3: Update ViewModels
1. Store domain errors as state
2. Replace generic error handling
3. Use `errorAlert()` or custom presentations

### Phase 4: Update Views
1. Remove vague error messages
2. Add specific error UX
3. Provide recovery actions

### Phase 5: Analytics Integration (Future)
1. Track error occurrences
2. Monitor recovery success
3. Identify problem areas

## Testing

### Unit Tests

```swift
func testDeleteStudentWithLessons() throws {
    let student = createTestStudent()
    let _ = createTestLesson(for: student)
    
    XCTAssertThrowsError(try repository.delete(id: student.id)) { error in
        guard case StudentError.cannotDeleteWithActiveLessons(let name, let count) = error else {
            XCTFail("Expected StudentError.cannotDeleteWithActiveLessons")
            return
        }
        XCTAssertEqual(name, student.fullName)
        XCTAssertEqual(count, 1)
    }
}
```

### UI Tests

```swift
func testErrorAlertDisplay() {
    // Trigger error condition
    app.buttons["Delete Student"].tap()
    
    // Verify error alert
    XCTAssertTrue(app.alerts["Cannot Delete Student"].exists)
    XCTAssertTrue(app.alerts.staticTexts.containing("5 active lessons").exists)
    
    // Verify recovery action
    XCTAssertTrue(app.buttons["View Lessons"].exists)
}
```

## Quick Reference

### Common Patterns

| Scenario | Error Type | Example |
|----------|-----------|---------|
| Entity not found | `*.notFound(id:)` | `StudentError.notFound(id: studentID)` |
| Duplicate data | `*.duplicateName` | `LessonError.duplicateTitle(subject:group:)` |
| Invalid input | `*.invalid*` | `WorkError.invalidDuration(duration:)` |
| Business rule | `*.cannotDeleteWith*` | `StudentError.cannotDeleteWithNotes` |
| Missing field | `*.missingRequiredField` | `ValidationError(field:reason:)` |
| Database failure | `DatabaseError` | `DatabaseError(operation:entity:underlying:)` |
| Network issue | `SyncError.*` | `SyncError.networkUnavailable` |

---

## Summary

The domain error system provides:

✅ **Type-safe error handling** - Compile-time safety  
✅ **User-friendly messages** - Clear, actionable feedback  
✅ **Consistent UX** - Standardized error presentation  
✅ **Better debugging** - Structured logging with context  
✅ **Testability** - Specific error cases easy to test

**Next Steps:**
1. Review this guide
2. Start migrating high-value services (Student, Work, Lesson)
3. Update corresponding ViewModels
4. Update UI to use error views
5. Add comprehensive tests

---

**Version:** 1.0  
**Date:** 2026-02-13  
**Author:** Architecture Migration Team
