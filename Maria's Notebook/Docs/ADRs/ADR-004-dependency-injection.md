# ADR-004: Dependency Injection via AppDependencies

**Status:** ✅ Accepted
**Date:** 2026-02 (Phase 2 of 7-Phase Migration)
**Deciders:** Architecture Migration Team
**Tags:** `architecture`, `di`, `services`, `singletons`

## Context

The app initially used scattered `.shared` singletons throughout the codebase, making testing difficult and dependencies unclear.

### The Problem Before

**Scattered Singletons:**
```swift
// In various files across codebase
class StudentService {
    static let shared = StudentService()
}

class LessonService {
    static let shared = LessonService()
}

class BackupService {
    static let shared = BackupService()
}
// × 38+ services...

// Usage in views/ViewModels
StudentService.shared.createStudent(...)
LessonService.shared.fetchLessons()
```

**Issues:**
- ❌ No clear dependency graph
- ❌ Hard to test (can't inject mocks)
- ❌ Initialization order unclear
- ❌ Tight coupling to concrete types
- ❌ Hard to find what depends on what
- ❌ Memory usage (all services initialized at startup)

## Decision

Centralize all dependencies in `AppDependencies` with **lazy initialization**.

### Architecture

```swift
@Observable
@MainActor
final class AppDependencies {
    let viewContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }

    // Lazy initialization pattern for each service
    private var _studentRepository: StudentRepository?
    var studentRepository: StudentRepository {
        if let repo = _studentRepository {
            return repo
        }
        let repo = StudentRepository(context: viewContext)
        _studentRepository = repo
        return repo
    }

    // × 38+ services...
}
```

### Environment Integration

```swift
// In App
@main
struct MariasNotebookApp: App {
    @State private var dependencies: AppDependencies

    init() {
        let coreDataStack = CoreDataStack.shared
        _dependencies = State(wrappedValue: AppDependencies(
            viewContext: coreDataStack.viewContext
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.dependencies, dependencies)
        }
    }
}

// In Views/ViewModels
struct FeatureView: View {
    @Environment(\.dependencies) private var dependencies

    var body: some View {
        Button("Create") {
            dependencies.studentRepository.createStudent(...)
        }
    }
}
```

## Consequences

### Positive

✅ **Single Source of Truth**
- All dependencies in one file
- Clear dependency graph
- Easy to find what's available

✅ **Lazy Initialization**
- Services only created when first used
- Reduces startup time
- Better memory usage

✅ **Testable**
```swift
func testFeature() {
    let testContext = createTestContext()
    let dependencies = AppDependencies(viewContext: testContext)
    let viewModel = FeatureViewModel(dependencies: dependencies)
    // Test with real or mock dependencies
}
```

✅ **Type-Safe**
- Compile-time dependency checking
- No string-based lookups
- Auto-completion support

✅ **Centralized Lifecycle**
- All service initialization in one place
- Easy to manage startup sequence
- Clear dependency injection points

### Negative

❌ **Boilerplate Heavy**
```swift
// Required for EACH service (6 lines × 38 services = 228 lines)
private var _serviceName: ServiceType?
var serviceName: ServiceType {
    if let service = _serviceName {
        return service
    }
    let service = ServiceType(...)
    _serviceName = service
    return service
}
```

❌ **Manual Property Management**
- Must manually write lazy initialization
- Easy to forget to cache service
- Repetitive code

❌ **Large File**
- `AppDependencies.swift` is 512 lines
- All services in one file
- Can be overwhelming

❌ **Not Truly Lazy in Environment**
- `AppDependencies` instance created at app startup
- Services lazy, but container isn't

### Neutral

⚠️ **Transition from Phase 1 Singletons**
- Some services still have `.shared` (CalendarSync, Toast, ReminderSync)
- Migration ongoing, not complete

## Current State (As of 2026-02-13)

### Services in AppDependencies (38+)

**Core Services:**
- `lifecycleService`
- `memoryPressureMonitor`

**Repositories (14):**
- `repositories` (container with 14 repo types)

**Data Services:**
- `workCheckInService`
- `workStepService`
- `groupTrackService`
- `trackProgressResolver`

**Sync Services:**
- `reminderSync`
- `calendarSync`
- `cloudKitSyncStatusService`

**Backup Services (10):**
- `backupService`
- `selectiveRestoreService`
- `cloudBackupService`
- `incrementalBackupService`
- `backupSharingService`
- `backupTransactionManager`
- `selectiveExportService`
- `autoBackupManager`

**Business Logic:**
- `followUpInboxEngine`
- `studentAnalysisService`
- `reportGeneratorService`

**UI Services:**
- `toastService`

**Calendar:**
- `schoolCalendarService`
- `schoolDayLookupCache`

**Coordinators:**
- `appRouter`
- `saveCoordinator`
- `restoreCoordinator`

**ViewModels:**
- `presentationsViewModel`

**MCP:**
- `mcpClient`

### Remaining Standalone Singletons

❌ **Not Yet Migrated:**
- `ToastService.shared` (also in dependencies)
- `ReminderSyncService.shared` (also in dependencies)
- `CalendarSyncService` (partially migrated)
- `AppRouter.shared` (also in dependencies)
- `FeatureFlags.shared` (intentionally global)

## Standard Patterns

### Pattern 1: Simple Service
```swift
private var _serviceName: ServiceType?
var serviceName: ServiceType {
    if let service = _serviceName { return service }
    let service = ServiceType()
    _serviceName = service
    return service
}
```

### Pattern 2: Service with Dependencies
```swift
private var _backupService: BackupService?
var backupService: BackupService {
    if let service = _backupService { return service }
    let service = BackupService(/* dependencies */)
    _backupService = service
    return service
}
```

### Pattern 3: Service Depending on Another Service
```swift
var incrementalBackupService: IncrementalBackupService {
    if let service = _incrementalBackupService { return service }
    let service = IncrementalBackupService(
        backupService: backupService  // Uses lazy property
    )
    _incrementalBackupService = service
    return service
}
```

### Pattern 4: Container of Related Services
```swift
struct RepositoryContainer {
    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    var students: StudentRepository {
        StudentRepository(context: context, saveCoordinator: saveCoordinator)
    }

    var lessons: LessonRepository {
        LessonRepository(context: context, saveCoordinator: saveCoordinator)
    }
    // ... 14 repositories
}

private var _repositories: RepositoryContainer?
var repositories: RepositoryContainer {
    if let container = _repositories { return container }
    let container = RepositoryContainer(context: viewContext, saveCoordinator: nil)
    _repositories = container
    return container
}
```

## Migration from Singletons

### Before (Phase 1)
```swift
// Service definition
class StudentService {
    static let shared = StudentService()
    // ...
}

// Usage
StudentService.shared.createStudent(...)
```

### After (Phase 2)
```swift
// In AppDependencies
private var _studentService: StudentService?
var studentService: StudentService {
    if let service = _studentService { return service }
    let service = StudentService()
    _studentService = service
    return service
}

// Usage
@Environment(\.dependencies) var dependencies
dependencies.studentService.createStudent(...)
```

## Feature Flags Integration

```swift
// Feature flag for DI approach
var useNewDependencyInjection: Bool {
    FeatureFlags.shared.useNewDependencyInjection
}

// Usage in services
if FeatureFlags.shared.useProtocolBasedServices {
    return WorkCheckInServiceAdapter(context: viewContext)
} else {
    return WorkCheckInServiceAdapter(context: viewContext)
}
```

## Preloading Strategy

```swift
/// Preload presentations data in background for instant navigation
func preloadPresentationsData(
    calendar: Calendar,
    inboxOrderRaw: String,
    missWindow: PresentationsMissWindow,
    showTestStudents: Bool,
    testStudentNamesRaw: String
) {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))  // Wait for DB init

        presentationsViewModel.update(
            viewContext: viewContext,
            calendar: calendar,
            inboxOrderRaw: inboxOrderRaw,
            missWindow: missWindow,
            showTestStudents: showTestStudents,
            testStudentNamesRaw: testStudentNamesRaw
        )
    }
}
```

## Testing Support

```swift
extension AppDependencies {
    /// Create dependencies with in-memory storage for testing
    static func makeTest() throws -> AppDependencies {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        let container = NSPersistentContainer(name: "MariasNotebook")
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error { fatalError("Test store failed: \(error)") }
        }
        return AppDependencies(viewContext: container.viewContext)
    }

    /// Create with specific NSManagedObjectContext for testing
    static func makeTest(context: NSManagedObjectContext) -> AppDependencies {
        return AppDependencies(viewContext: context)
    }
}
```

## Alternatives Considered

### 1. Continue with Scattered Singletons
**Rejected:** Hard to test, unclear dependencies, tight coupling.

### 2. Swift Dependencies Framework
```swift
extension DependencyValues {
    var studentRepository: StudentRepository {
        get { self[StudentRepositoryKey.self] }
        set { self[StudentRepositoryKey.self] = newValue }
    }
}

@Dependency(\.studentRepository) var repository
```
**Deferred:** Planned for Phase 5, but requires learning new framework. Current approach works and is simpler for team to understand.

### 3. Service Locator Pattern
```swift
class ServiceLocator {
    static func getService<T>(_ type: T.Type) -> T
}
```
**Rejected:** Loses type safety, runtime lookups, harder to debug.

### 4. Constructor Injection Everywhere
```swift
struct FeatureViewModel {
    let repository: StudentRepository
    let service: BackupService
    // ... inject all dependencies
}
```
**Rejected:** Too verbose; SwiftUI environment is cleaner.

## Future: Phase 5 Migration to Swift Dependencies

**Planned Benefits:**
- Eliminate 228+ lines of boilerplate
- Automatic dependency resolution
- Better testing with `withDependencies`
- Cleaner syntax

**Example Future State:**
```swift
@Dependency(\.studentRepository) var repository
@Dependency(\.backupService) var backup
// No more AppDependencies.swift boilerplate
```

**Status:** Deferred (Phase 5 of 7-phase migration)

## Related Decisions

- See [ADR-003](ADR-003-repository-pattern.md) for repository usage
- See [FeatureFlags.swift](../AppCore/FeatureFlags.swift) for migration flags
- See [7-Phase Migration Plan](../Docs/ARCHITECTURE_MIGRATION.md)

## References

- Code: `AppCore/AppDependencies.swift` (512 lines)
- Testing: `AppDependencies.makeTest()` methods
- Environment: `AppDependenciesKey` environment key
- Migration: Phase 2 of 7-phase plan

## Revision History

| Date | Author | Change |
|------|--------|--------|
| 2026-02 | Architecture Migration | Phase 2: Consolidated singletons |
| 2026-02-13 | Architecture Migration | Documented as ADR-004 |

---

**Next ADR:** [ADR-005: Denormalization Strategy](ADR-005-denormalization-strategy.md)
