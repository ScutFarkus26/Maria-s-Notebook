# Error Handling

**Last Updated:** 2026-02-25

## Overview

Maria's Notebook uses domain-specific error types that provide user-friendly messages, actionable recovery suggestions, and automatic logging. The system replaces generic `Error` with typed errors that speak the app's language.

---

## Error Types

### Core Protocol

```swift
protocol AppError: LocalizedError, Sendable {
    var category: ErrorCategory { get }
    var severity: ErrorSeverity { get }
}
```

### Domain Errors

| Error Type | Domain | Example Cases |
|-----------|--------|---------------|
| `StudentError` | Student management | `.notFound`, `.duplicateName`, `.invalidData` |
| `LessonError` | Lesson operations | `.notFound`, `.alreadyAssigned`, `.invalidOrder` |
| `WorkError` | Work/practice items | `.notFound`, `.invalidStatus`, `.completionFailed` |
| `AttendanceError` | Attendance tracking | `.alreadyRecorded`, `.invalidDate`, `.syncConflict` |
| `SyncError` | CloudKit sync | `.networkUnavailable`, `.conflictDetected`, `.quotaExceeded` |
| `BackupOperationError` | Backup/restore | Hierarchical error with nested context (exemplary pattern) |

### Generic Helpers

- `ValidationError` — field-level validation failures
- `DatabaseError` — SwiftData operation failures

### Error Categories

| Category | Description |
|----------|-------------|
| `.validation` | Invalid user input |
| `.notFound` | Entity doesn't exist |
| `.conflict` | Data conflicts |
| `.permission` | Access denied |
| `.network` | Connectivity issues |
| `.storage` | Disk/database problems |
| `.sync` | CloudKit sync failures |
| `.system` | Unexpected system errors |

### Error Severity

| Level | Usage |
|-------|-------|
| `.debug` | Development only |
| `.info` | Informational |
| `.warning` | Recoverable issues |
| `.error` | User-visible failures |
| `.critical` | Data loss risk |

---

## Implementation Files

Located in `Errors/`:

| File | Purpose |
|------|---------|
| `AppError.swift` | Core protocol and categories |
| `ErrorHandling.swift` | Error handling utilities and logging |
| `ErrorViews.swift` | SwiftUI error display components (ErrorBanner, ErrorDetailView, ErrorEmptyState) |
| `StudentError.swift` | Student domain errors |
| `LessonError.swift` | Lesson domain errors |
| `WorkError.swift` | Work domain errors |
| `AttendanceError.swift` | Attendance domain errors |
| `SyncError.swift` | Sync domain errors |

---

## Patterns

### Pattern 1: Hierarchical Domain Errors (Complex Services)

Best for services with many failure modes. `BackupOperationError` is the exemplary implementation.

```swift
enum BackupOperationError: AppError {
    case exportFailed(underlying: Error, entityType: String?)
    case importFailed(underlying: Error, phase: RestorePhase)
    case checksumMismatch(expected: String, actual: String)
    case formatVersionUnsupported(version: Int)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Backup file appears corrupted"
        // ...
        }
    }
}
```

### Pattern 2: Simple Domain Errors (Repositories)

Best for straightforward CRUD operations with 5-10 cases.

```swift
enum StudentError: AppError {
    case notFound(id: UUID)
    case duplicateName(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Student not found"
        case .duplicateName(let name):
            return "A student named '\(name)' already exists"
        }
    }
}
```

### Pattern 3: Error Display in Views

```swift
// Alert
.alert("Error", isPresented: $showError, presenting: lastError) { _ in
    Button("OK") {}
} message: { error in
    Text(error.localizedDescription)
}

// Inline banner
if let error = viewModel.error {
    ErrorBanner(error: error, dismiss: { viewModel.error = nil })
}

// Toast
dependencies.toastService.showError(error.localizedDescription)
```

### Pattern 4: Service Error Handling

```swift
func saveStudent(_ student: Student) async throws {
    do {
        try modelContext.safeSave()
    } catch {
        throw StudentError.saveFailed(underlying: error)
    }
}
```

---

## Best Practices

1. **Always conform to `LocalizedError`** — provides `errorDescription` for user display
2. **Use associated values for context** — `case notFound(id: UUID)` not just `case notFound`
3. **Wrap underlying errors** — preserve the original error for debugging
4. **Conform to `Sendable`** — required for Swift 6 concurrency safety
5. **Provide recovery suggestions** — implement `recoverySuggestion` where applicable

---

## When to Create Custom Errors

**Do create** when:
- Service has 3+ distinct failure modes
- User needs to see specific error messages
- Error recovery differs by case
- Logging/analytics needs categorization

**Don't create** when:
- Simple pass-through of SwiftData errors
- Only one failure mode (use `throws` directly)
- Error is never shown to user

---

## Migration Strategy

When adding error handling to existing code:

1. **High priority:** User-facing operations (save, delete, sync)
2. **Medium priority:** Background services (backup, migration)
3. **Low priority:** Internal utilities (formatting, caching)
4. **Skip:** Code that already handles errors adequately
