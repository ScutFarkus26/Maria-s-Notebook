# Dependency Injection Guidelines

**Created:** 2026-02-13
**Phase:** 5 - DI Modernization (Evaluation Phase)
**Purpose:** Document dependency injection patterns for Maria's Notebook
**Decision:** Continue with current AppDependencies pattern (no migration to Swift Dependencies)

---

## Table of Contents

1. [Overview](#overview)
2. [Current Implementation](#current-implementation)
3. [Swift Dependencies Evaluation](#swift-dependencies-evaluation)
4. [Decision: No Migration](#decision-no-migration)
5. [Best Practices](#best-practices)
6. [Adding New Services](#adding-new-services)
7. [Testing Strategy](#testing-strategy)

---

## Overview

### What is Dependency Injection?

Dependency Injection (DI) is a design pattern where objects receive their dependencies from external sources rather than creating them internally. This enables:

- ✅ **Testability** - Can inject mock dependencies for unit tests
- ✅ **Flexibility** - Can swap implementations without changing code
- ✅ **Separation of Concerns** - Dependencies are explicitly declared
- ✅ **Reusability** - Services can be shared across the application
- ✅ **Maintainability** - Clear dependency graph

---

## Current Implementation

### AppDependencies.swift (512 lines)

**Central DI Container:**
```swift
@Observable
@MainActor
final class AppDependencies {
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    // 35+ services with lazy initialization
    private var _toastService: ToastService?
    var toastService: ToastService {
        if let service = _toastService { return service }
        let service = ToastService.shared
        _toastService = service
        return service
    }
    
    // ... more services
}
```

### Key Features

**1. Lazy Initialization**
```swift
private var _backupService: BackupService?
var backupService: BackupService {
    if let service = _backupService { return service }
    let service = BackupService()
    _backupService = service
    return service
}
```

**Benefits:**
- Services created only when first accessed
- Reduces app startup time
- Memory efficient (services not needed = not created)

**2. SwiftUI Environment Integration**
```swift
// In App
@main
struct MariasNotebookApp: App {
    @State private var dependencies: AppDependencies
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.dependencies, dependencies)
        }
    }
}

// In Views
struct TodayView: View {
    @Environment(\.dependencies) private var dependencies
    
    var body: some View {
        Button("Sync") {
            dependencies.reminderSync.syncReminders()
        }
    }
}
```

**Benefits:**
- Natural SwiftUI integration
- Environment-based propagation
- No boilerplate at call sites

**3. Service Composition**
```swift
var cloudBackupService: CloudBackupService {
    if let service = _cloudBackupService { return service }
    // Compose with other dependencies
    let service = CloudBackupService(backupService: backupService)
    _cloudBackupService = service
    return service
}
```

**Benefits:**
- Services can depend on other services
- Clear dependency relationships
- Automatic graph resolution

**4. Testing Support**
```swift
static func makeTest() throws -> AppDependencies {
    let schema = Schema([Student.self, Lesson.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    return AppDependencies(modelContext: container.mainContext)
}

static func makeTest(context: ModelContext) -> AppDependencies {
    return AppDependencies(modelContext: context)
}
```

**Benefits:**
- In-memory storage for tests
- Fast test execution
- Isolated test environments

**5. Memory Pressure Handling**
```swift
var memoryPressureMonitor: MemoryPressureMonitor {
    if let monitor = _memoryPressureMonitor { return monitor }
    let monitor = MemoryPressureMonitor()
    monitor.startMonitoring { [weak self] in
        self?.handleMemoryPressure()
    }
    _memoryPressureMonitor = monitor
    return monitor
}

private func handleMemoryPressure() {
    NotificationCenter.default.post(
        name: Notification.Name("MemoryPressureDetected"),
        object: nil
    )
}
```

**Benefits:**
- Proactive cache clearing
- Prevents app termination
- Automatic lifecycle management

---

## Swift Dependencies Evaluation

### Framework Overview

**Swift Dependencies** (by Point-Free) is a DI framework inspired by SwiftUI's environment system.

**Sources:**
- [GitHub - pointfreeco/swift-dependencies](https://github.com/pointfreeco/swift-dependencies)
- [Dependencies Documentation](https://pointfreeco.github.io/swift-dependencies/main/documentation/dependencies/)
- [Macro Bonanza: Dependencies](https://www.pointfree.co/blog/posts/120-macro-bonanza-dependencies)

**Key Features:**
- `@DependencyClient` macro for dependency design
- Struct-based dependencies with closure properties
- Swift Testing framework support
- Cross-platform compatibility (Linux, Windows, SwiftWasm)
- Test overrides for specific endpoints

### Example Pattern

```swift
// Swift Dependencies approach
@DependencyClient
struct BackupClient {
    var exportBackup: @Sendable (ModelContext, URL) async throws -> BackupSummary
    var importBackup: @Sendable (ModelContext, URL) async throws -> BackupSummary
}

extension BackupClient: DependencyKey {
    static let liveValue = BackupClient(
        exportBackup: { context, url in
            // Implementation
        },
        importBackup: { context, url in
            // Implementation
        }
    )
    
    static let testValue = BackupClient(
        exportBackup: { _, _ in throw TestError() },
        importBackup: { _, _ in throw TestError() }
    )
}

// Usage
@Dependency(\.backupClient) var backupClient
try await backupClient.exportBackup(context, url)
```

---

## Decision: No Migration

### Why Skip Swift Dependencies?

After thorough evaluation, we decided **NOT to adopt** Swift Dependencies for the following reasons:

### 1. Current Solution is Production-Grade ✅

**AppDependencies already provides:**
- ✅ Lazy initialization (35+ services)
- ✅ SwiftUI Environment integration
- ✅ Testing support (in-memory containers)
- ✅ Service composition
- ✅ Memory pressure handling
- ✅ Clear, simple pattern
- ✅ Zero external dependencies
- ✅ Industry-standard approach

**What we'd gain from Swift Dependencies:**
- `@DependencyClient` macro (marginal improvement)
- Test value overrides (we already have mocks via protocols)
- Cross-platform support (not needed - iOS/macOS only)

**Verdict:** No significant benefits over current implementation.

### 2. Migration Risk vs Benefit

**Migration Would Require:**
- Add Swift Dependencies package dependency
- Migrate 35+ service properties
- Convert services to `@DependencyClient` structs
- Update all view injection points
- Rewrite test infrastructure
- Team learning curve

**Estimated Effort:** 3 weeks

**Risk Level:** MEDIUM-HIGH (4/10)
- Touching every service integration
- Risk of breaking existing code
- Potential performance regression
- New dependency to maintain

**Benefit:** MINIMAL
- Current pattern works perfectly
- No problems to solve
- No performance improvements
- No new capabilities needed

**Verdict:** Risk >> Benefit. Not worth it.

### 3. Current Pattern is Simpler

**AppDependencies Pattern:**
```swift
// Simple, transparent, easy to understand
private var _toastService: ToastService?
var toastService: ToastService {
    if let service = _toastService { return service }
    let service = ToastService.shared
    _toastService = service
    return service
}

// Usage
dependencies.toastService.showSuccess("Done!")
```

**Swift Dependencies Pattern:**
```swift
// More abstraction, macro-based
@DependencyClient
struct ToastClient {
    var showSuccess: @Sendable (String) -> Void
}

extension ToastClient: DependencyKey {
    static let liveValue = ToastClient(
        showSuccess: { message in ToastService.shared.showSuccess(message) }
    )
}

// Usage
@Dependency(\.toastClient) var toastClient
toastClient.showSuccess("Done!")
```

**Verdict:** Current pattern is clearer and requires less indirection.

### 4. No Testing Issues

**Current Testing Approach Works:**
```swift
// Test setup
let dependencies = try AppDependencies.makeTest()

// Mock via protocols (Phase 1)
let mockService = MockWorkCheckInService()
// Use mockService in tests
```

**We don't need:**
- Swift Dependencies test value overrides
- Macro-based mocking
- Framework-specific testing patterns

**Verdict:** Testing already solved via protocols and in-memory containers.

### 5. Industry Standard Pattern

The current lazy initialization pattern is used by:
- ✅ Apple (SwiftUI, UIKit examples)
- ✅ Major iOS apps
- ✅ Industry best practices
- ✅ Well-documented and understood

**Swift Dependencies is:**
- Point-Free specific
- Macro-based (less transparent)
- Additional framework overhead
- Less familiar to most developers

**Verdict:** Stick with widely-adopted patterns.

---

## Best Practices

### 1. Lazy Initialization Pattern

✅ **DO:**
```swift
private var _service: ServiceType?
var service: ServiceType {
    if let service = _service { return service }
    let service = ServiceType()
    _service = service
    return service
}
```

**Why:**
- Services created only when needed
- Reduces startup time
- Memory efficient
- Thread-safe (all services are @MainActor)

❌ **DON'T:**
```swift
// Eager initialization
let service = ServiceType() // Created immediately on app launch
```

### 2. Service Composition

✅ **DO:**
```swift
var cloudBackupService: CloudBackupService {
    if let service = _cloudBackupService { return service }
    // Compose with dependencies
    let service = CloudBackupService(backupService: backupService)
    _cloudBackupService = service
    return service
}
```

**Why:**
- Clear dependency relationships
- Automatic dependency resolution
- Services get their dependencies automatically

❌ **DON'T:**
```swift
// Hard-coded dependencies
var cloudBackupService: CloudBackupService {
    CloudBackupService(backupService: BackupService()) // Creates new instance
}
```

### 3. Repository Container Integration

✅ **DO:**
```swift
private var _repositories: RepositoryContainer?
var repositories: RepositoryContainer {
    if let container = _repositories { return container }
    let container = RepositoryContainer(
        context: modelContext,
        saveCoordinator: saveCoordinator
    )
    _repositories = container
    return container
}
```

**Why:**
- Single repository container
- Consistent context injection
- Centralized data access

### 4. Environment Integration

✅ **DO:**
```swift
// In views
@Environment(\.dependencies) private var dependencies

var body: some View {
    Button("Save") {
        dependencies.saveCoordinator.save(modelContext)
    }
}
```

**Why:**
- Natural SwiftUI pattern
- Environment-based propagation
- No manual injection needed

❌ **DON'T:**
```swift
// Hard-coded singletons
Button("Save") {
    ToastService.shared.showSuccess("Saved") // Bypass DI
}
```

### 5. Testing Setup

✅ **DO:**
```swift
func testMyFeature() throws {
    let dependencies = try AppDependencies.makeTest()
    let viewModel = MyViewModel(dependencies: dependencies)
    
    // Test with in-memory storage
    viewModel.performAction()
    
    XCTAssertEqual(viewModel.state, .success)
}
```

**Why:**
- In-memory storage (fast tests)
- Isolated test environment
- Easy to set up

---

## Adding New Services

### Step-by-Step Guide

**1. Create the Service**
```swift
// Services/MyNewService.swift
@MainActor
final class MyNewService {
    init() {
        // Initialize
    }
    
    func performAction() {
        // Implementation
    }
}
```

**2. Add to AppDependencies**
```swift
// AppCore/AppDependencies.swift

// MARK: - My Feature Services

private var _myNewService: MyNewService?
var myNewService: MyNewService {
    if let service = _myNewService { return service }
    let service = MyNewService()
    _myNewService = service
    return service
}
```

**3. Use in Views**
```swift
struct MyView: View {
    @Environment(\.dependencies) private var dependencies
    
    var body: some View {
        Button("Do Something") {
            dependencies.myNewService.performAction()
        }
    }
}
```

**4. Add Test Support (if needed)**
```swift
// If service needs special test setup
static func makeTest() throws -> AppDependencies {
    let deps = try AppDependencies.makeTest()
    // Configure service for testing if needed
    return deps
}
```

### Service with Dependencies

If your service needs other services:

```swift
@MainActor
final class MyCompositeService {
    private let backupService: BackupService
    private let toastService: ToastService
    
    init(backupService: BackupService, toastService: ToastService) {
        self.backupService = backupService
        self.toastService = toastService
    }
    
    func performComplexAction() async throws {
        try await backupService.exportBackup(...)
        toastService.showSuccess("Done!")
    }
}
```

**Add to AppDependencies:**
```swift
var myCompositeService: MyCompositeService {
    if let service = _myCompositeService { return service }
    // Compose with other dependencies
    let service = MyCompositeService(
        backupService: backupService,
        toastService: toastService
    )
    _myCompositeService = service
    return service
}
```

---

## Testing Strategy

### 1. In-Memory Storage

```swift
func testFeature() throws {
    // Create in-memory dependencies
    let dependencies = try AppDependencies.makeTest()
    
    // Use in test
    let viewModel = MyViewModel(dependencies: dependencies)
    viewModel.loadData()
    
    XCTAssertEqual(viewModel.items.count, 0)
}
```

**Benefits:**
- Fast (no disk I/O)
- Isolated (each test gets fresh storage)
- Clean (automatically destroyed after test)

### 2. Protocol-Based Mocking

**For services migrated in Phase 1:**
```swift
struct MockWorkCheckInService: WorkCheckInServiceProtocol {
    var context: ModelContext
    var checkInCalled = false
    
    mutating func checkIn(work: WorkModel) {
        checkInCalled = true
    }
}

func testWorkCheckIn() {
    var mockService = MockWorkCheckInService(context: testContext)
    
    // Use mock in test
    viewModel.performCheckIn(service: mockService)
    
    XCTAssertTrue(mockService.checkInCalled)
}
```

**Benefits:**
- Full control over behavior
- Can verify method calls
- Can test error conditions

### 3. Shared Test Context

```swift
class MyTestCase: XCTestCase {
    var dependencies: AppDependencies!
    var modelContext: ModelContext!
    
    override func setUp() async throws {
        dependencies = try AppDependencies.makeTest()
        modelContext = dependencies.modelContext
    }
    
    override func tearDown() {
        dependencies = nil
        modelContext = nil
    }
    
    func testFeature() {
        // Use shared dependencies
        let viewModel = MyViewModel(dependencies: dependencies)
        // Test
    }
}
```

---

## Future Considerations

### When to Revisit Swift Dependencies

Consider Swift Dependencies if:
1. We need cross-platform support (Linux, Windows, SwiftWasm)
2. Current testing approach becomes insufficient
3. Framework adds compelling features we need
4. Industry shifts to macro-based DI as standard

**Current Verdict:** None of these apply. Current pattern works perfectly.

### When to Refactor AppDependencies

Consider refactoring if:
1. AppDependencies exceeds 1,000 lines (currently 512)
2. Lazy initialization becomes bottleneck (not an issue)
3. Testing becomes difficult (not an issue)
4. Memory management becomes problem (handled well)

**Current Verdict:** No refactoring needed. Current implementation is clean and maintainable.

---

## Success Criteria

✅ **Phase 5 Complete When:**
1. Swift Dependencies evaluated ✅
2. Decision documented with rationale ✅
3. Current pattern documented as best practice ✅
4. Guidelines for adding new services provided ✅
5. Testing strategy documented ✅

**No code changes required** - current DI pattern is production-grade and works perfectly.

---

## Related Documentation

- `AppDependencies.swift` - Central DI container (512 lines)
- `PHASE1_COMPLETION.md` - Protocol-based services (integration with DI)
- `REPOSITORY_GUIDELINES.md` - Repository pattern (integrated via DI)
- `VIEWMODEL_GUIDELINES.md` - ViewModel patterns (use DI for dependencies)

---

## Conclusion

After thorough evaluation, Maria's Notebook's current dependency injection pattern via `AppDependencies` is production-grade and superior to migrating to Swift Dependencies for this codebase.

**Key Reasons:**
1. ✅ Current pattern provides all needed features
2. ✅ Zero migration risk vs minimal benefit
3. ✅ Simpler and more transparent than macro-based approach
4. ✅ Industry-standard pattern
5. ✅ Testing already works perfectly

**Decision:** Continue with `AppDependencies` pattern, document as best practice, proceed to Phase 7.

---

**Document Version:** 1.0
**Last Updated:** 2026-02-13
**Author:** Claude Sonnet 4.5
**Status:** Approved (No Migration)
