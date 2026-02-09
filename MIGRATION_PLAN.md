# AppDependencies Migration Plan

## Phase 4 Migration Strategy

### Overview
This document outlines the remaining work to fully migrate the application to the dependency injection pattern via `AppDependencies`.

### Goals
1. Add all remaining services to the container (target: 118+ services)
2. Eliminate singleton pattern throughout the codebase
3. Improve testability with protocol-based services
4. Resolve circular dependencies

### Migration Steps

#### Step 1: Add Remaining Services
Currently, AppDependencies contains ~25 services. The following categories need to be added:

- **Navigation Services**
  - AppRouter
  - Navigation coordinators
  
- **UI State Services**
  - View-specific state managers
  - Sheet coordinators
  
- **Data Processing Services**
  - Additional data transformation services
  - Caching services
  
- **Business Logic Services**
  - Domain-specific service layer
  
#### Step 2: Replace Singleton Calls
Replace all singleton access patterns with dependency injection:

**Before:**
```swift
ReminderSyncService.shared.syncReminders()
AppRouter.shared.navigate(to: .student(id))
```

**After:**
```swift
dependencies.reminderSync.syncReminders()
dependencies.appRouter.navigate(to: .student(id))
```

#### Step 3: Update ViewModels
Refactor ViewModels to accept dependencies via initializer:

**Before:**
```swift
class TodayViewModel: ObservableObject {
    private let reminderSync = ReminderSyncService.shared
}
```

**After:**
```swift
class TodayViewModel: ObservableObject {
    private let dependencies: AppDependencies
    
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }
}
```

#### Step 4: Protocol-Based Services
Make services testable by extracting protocols:

```swift
protocol WorkLifecycleService {
    func startWork(_ work: WorkModel) async throws
    func completeWork(_ work: WorkModel) async throws
}

class WorkLifecycleServiceImpl: WorkLifecycleService {
    // Implementation
}
```

This allows for mock implementations in tests:
```swift
class MockWorkLifecycleService: WorkLifecycleService {
    // Mock implementation
}
```

#### Step 5: Resolve Circular Dependencies
Circular dependencies were identified in Phase 1.2 documentation. Resolution strategies:

1. **Use Protocols**: Break direct class dependencies
2. **Weak References**: Use `weak` for parent-child relationships
3. **Event Bus Pattern**: Consider implementing for loose coupling between services
4. **Dependency Inversion**: Depend on abstractions, not concrete implementations

### Progress Tracking

- [x] Phase 1: Core infrastructure (AppDependencies class)
- [x] Phase 2: Initial service migration (~25 services)
- [x] Phase 3: Documentation and patterns
- [ ] Phase 4: Complete service migration
- [ ] Phase 5: ViewModel refactoring
- [ ] Phase 6: Testing infrastructure
- [ ] Phase 7: Circular dependency resolution

### Notes

- Lazy initialization ensures services are only created when needed
- ModelContext is passed during initialization for data access
- All services should be `@MainActor` isolated where appropriate
- Consider using `lazy var` for simple dependencies to reduce boilerplate

### References

- See `AppCore/AppDependencies.swift` for current implementation
- Phase 1.2 documentation (if available) for circular dependency analysis
