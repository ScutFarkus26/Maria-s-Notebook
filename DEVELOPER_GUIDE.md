# WorkView Developer Guide

## Quick Reference

### Adding a New Filter

**Step 1:** Add property to `WorkFilters.swift`
```swift
@Observable
final class WorkFilters {
    // ... existing properties
    var showCompletedOnly: Bool = false // New filter
    
    func filterWorks(...) -> [WorkModel] {
        var base = works
        
        // Add your filter logic
        if showCompletedOnly {
            base = base.filter { $0.isCompleted }
        }
        
        return base
    }
}
```

**Step 2:** Add UI control to `WorkViewSidebar.swift` or `WorkView.swift`
```swift
// In WorkViewSidebar
Toggle("Show Completed Only", isOn: $filters.showCompletedOnly)
    .padding(.horizontal, 8)
```

**Step 3:** (Optional) Add scene storage for persistence in `WorkView.swift`
```swift
@SceneStorage("WorkView.showCompletedOnly") 
private var showCompletedOnlyStorage: Bool = false

// In syncFiltersFromStorage()
filters.showCompletedOnly = showCompletedOnlyStorage

// In syncFiltersToStorage()
showCompletedOnlyStorage = filters.showCompletedOnly

// Add onChange
.onChange(of: filters.showCompletedOnly) { _, _ in syncFiltersToStorage() }
```

---

### Adding a New Grouping Mode

**Step 1:** Add case to `WorkFilters.Grouping` enum
```swift
enum Grouping: String, CaseIterable {
    case none, type, date, checkIns, priority // New case
    
    var displayName: String {
        switch self {
        // ... existing cases
        case .priority: return "Priority"
        }
    }
    
    var icon: String {
        switch self {
        // ... existing cases
        case .priority: return "exclamationmark.3"
        }
    }
}
```

**Step 2:** Add grouping logic to `WorkGroupingService.swift`
```swift
static func sectionOrder(for grouping: WorkFilters.Grouping) -> [String] {
    switch grouping {
    // ... existing cases
    case .priority:
        return ["High", "Medium", "Low", "None"]
    }
}

static func sectionIcon(for key: String) -> String {
    switch key {
    // ... existing cases
    case "High": return "exclamationmark.3"
    case "Medium": return "exclamationmark.2"
    case "Low": return "exclamationmark"
    default: return "circle"
    }
}

static func groupByPriority(_ works: [WorkModel]) -> [String: [WorkModel]] {
    Dictionary(grouping: works) { work in
        // Your grouping logic
        switch work.priority {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        default: return "None"
        }
    }
}

static func itemsForSection(...) -> [WorkModel] {
    switch grouping {
    // ... existing cases
    case .priority:
        return groupByPriority(works)[key] ?? []
    }
}
```

**Step 3:** Done! The UI automatically picks up the new case through `ForEach(WorkFilters.Grouping.allCases, ...)`

---

### Adding a Helper Method to WorkLookupService

```swift
struct WorkLookupService {
    // ... existing properties
    
    // Add your helper method
    func workCount(for studentID: UUID) -> Int {
        // Use the lookup dictionaries
        return /* calculation */
    }
    
    func mostRecentWork(for lessonID: UUID) -> WorkModel? {
        // Your logic here
    }
}
```

Then use it in any view:
```swift
let count = lookupService.workCount(for: student.id)
```

---

### Modifying Empty States

Edit `WorkEmptyStateView.swift`:

```swift
private var title: String {
    switch type {
    case .noWork:
        return "No work yet" // Change this
    case .noMatchingFilters:
        return "No work matches your filters"
    case .newCase: // Add new cases
        return "New message"
    }
}
```

---

### Changing Sidebar Layout

Edit `WorkViewSidebar.swift`. The structure is:
```
VStack {
    Section 1: Students
      - Button → triggers popover
      
    Search Field
    
    Section 2: Group By
      - Buttons for each grouping mode
      
    Section 3: Subject
      - All Subjects button
      - Subject buttons (dynamic)
}
```

To add a new section, insert it in the VStack:
```swift
Text("New Section")
    .font(.system(size: AppTheme.FontSize.caption, weight: .semibold))
    .padding(.horizontal, 8)
    .padding(.top, 8)

// Your controls here
```

---

### Customizing the Student Filter

Edit `StudentFilterView.swift`:

**Change sorting:**
```swift
private var filteredStudents: [Student] {
    // ... existing filter logic
    return base.sorted { lhs, rhs in
        // Change sorting here
        lhs.lastName < rhs.lastName
    }
}
```

**Add badge or icon per student:**
```swift
HStack(spacing: 8) {
    Image(systemName: selectedStudentIDs.contains(s.id) ? "checkmark.circle.fill" : "circle")
    Text(displayName(s))
    
    // Add your badge
    if someCondition {
        Badge(...)
    }
}
```

---

### Platform-Specific Code

Use conditional compilation:

```swift
#if os(macOS)
// macOS-only code
Button("Open in Window") {
    openWindow(id: "WorkDetailWindow", value: work.id)
}
#else
// iOS/iPadOS code
Button("Show Details") {
    selectedWorkID = work.id
}
#endif
```

Or check size class at runtime:
```swift
if hSize == .compact {
    // iPhone portrait, compact layout
} else {
    // iPad or iPhone landscape
}
```

---

## Common Tasks

### Access the Current Filters from a Child View

Pass filters as a binding:
```swift
struct MyNewView: View {
    @Binding var filters: WorkFilters
    
    var body: some View {
        Text("Search: \(filters.searchText)")
        Button("Clear") {
            filters.searchText = ""
        }
    }
}

// In WorkView
MyNewView(filters: $filters)
```

---

### Access Lookup Data in a New View

Pass the lookup service:
```swift
struct MyNewView: View {
    let lookupService: WorkLookupService
    let work: WorkModel
    
    var body: some View {
        if let slID = work.studentLessonID,
           let sl = lookupService.studentLessonsByID[slID],
           let lesson = lookupService.lessonsByID[sl.lessonID] {
            Text("Lesson: \(lesson.name)")
        }
    }
}

// In WorkView
MyNewView(lookupService: lookupService, work: someWork)
```

---

### Trigger Work Selection from Outside

Post a notification:
```swift
NotificationCenter.default.post(
    name: Notification.Name("NewWorkRequested"),
    object: nil
)
```

The view listens with:
```swift
.onReceive(NotificationCenter.default.publisher(for: .init("NewWorkRequested"))) { _ in
    isPresentingAddWork = true
}
```

---

### Modify Work Card Display

Edit `WorkCardsGridView` (existing file). You can pass parameters:
```swift
WorkCardsGridView(
    works: filteredWorks,
    studentsByID: lookupService.studentsByID,
    lessonsByID: lookupService.lessonsByID,
    studentLessonsByID: lookupService.studentLessonsByID,
    onTapWork: handleWorkSelection,
    onToggleComplete: handleToggleComplete,
    embedInScrollView: false,           // Controls scrolling
    hideTypeBadge: true                  // Hides type badge
)
```

---

## Testing Examples

### Unit Test for Filters

```swift
import Testing
@testable import YourApp

@Suite("WorkFilters Tests")
struct WorkFiltersTests {
    
    @Test("Filters by selected subject")
    func filterBySubject() {
        let filters = WorkFilters()
        filters.selectedSubject = "Math"
        
        let works = [/* mock work items */]
        let studentLessons = [/* mock */]
        let lessons = [/* mock lessons */]
        
        let filtered = filters.filterWorks(
            works,
            studentLessonsByID: /* ... */,
            lessonsByID: /* ... */
        )
        
        #expect(filtered.allSatisfy { /* check subject */ })
    }
    
    @Test("Search filters by title and notes")
    func searchFilter() {
        let filters = WorkFilters()
        filters.searchText = "homework"
        
        // Test implementation
    }
}
```

---

### Unit Test for Grouping Service

```swift
@Suite("WorkGroupingService Tests")
struct WorkGroupingServiceTests {
    
    @Test("Groups works by type")
    func groupByType() {
        let works = [
            WorkModel(workType: .research, /* ... */),
            WorkModel(workType: .practice, /* ... */),
            WorkModel(workType: .research, /* ... */)
        ]
        
        let grouped = WorkGroupingService.groupByType(works)
        
        #expect(grouped["Research"]?.count == 2)
        #expect(grouped["Practice"]?.count == 1)
    }
    
    @Test("Section order is correct for checkIns grouping")
    func sectionOrderCheckIns() {
        let order = WorkGroupingService.sectionOrder(for: .checkIns)
        #expect(order.first == "Overdue")
        #expect(order.last == "No Check-Ins")
    }
}
```

---

### Unit Test for Lookup Service

```swift
@Suite("WorkLookupService Tests")
struct WorkLookupServiceTests {
    
    @Test("Display name formats correctly")
    func displayName() {
        let student = Student(firstName: "John", lastName: "Doe")
        let service = WorkLookupService(
            students: [student],
            lessons: [],
            studentLessons: []
        )
        
        let name = service.displayName(for: student)
        #expect(name == "John D.")
    }
    
    @Test("Linked date uses givenAt if available")
    func linkedDatePriority() {
        // Test date resolution logic
    }
}
```

---

## Debugging Tips

### Filters Not Working?

1. Check `WorkFilters.filterWorks()` logic
2. Verify filter state is being set (add `print()` statements)
3. Check scene storage sync (might need app restart to clear)
4. Ensure lookup dictionaries are populated

### Grouping Display Issues?

1. Verify `WorkGroupingService.sectionOrder()` returns correct keys
2. Check `itemsForSection()` returns items for those keys
3. Ensure grouping logic in `groupBy*()` methods is correct

### Layout Problems?

1. Check platform conditionals (`#if os(macOS)` vs `hSize == .compact`)
2. Verify correct layout is being used
3. Check frame modifiers and spacers

### Scene Storage Not Persisting?

1. Ensure `@SceneStorage` property names match
2. Verify `syncFiltersFromStorage()` is called in `.onAppear`
3. Verify `syncFiltersToStorage()` is called in `.onChange` modifiers
4. Remember scene storage is per-window/scene, not global

---

## File Responsibilities Cheat Sheet

| File | Purpose | Depends On | SwiftUI? |
|------|---------|------------|----------|
| `WorkView.swift` | Main coordinator | All components | Yes |
| `WorkFilters.swift` | Filter state & logic | None | No |
| `WorkLookupService.swift` | Data lookups | None | No |
| `WorkGroupingService.swift` | Grouping algorithms | None | No |
| `StudentFilterView.swift` | Student picker UI | WorkFilters | Yes |
| `WorkViewSidebar.swift` | Sidebar filters UI | WorkFilters, StudentFilterView | Yes |
| `WorkEmptyStateView.swift` | Empty state UI | None | Yes |
| `WorkContentView.swift` | Content display | All services | Yes |

**Rule of thumb:** 
- Service files (ending in `Service`) = Pure logic, testable
- View files (ending in `View`) = UI only, uses services
- `WorkFilters` = Hybrid (state + logic), but no UI dependencies

---

## Performance Considerations

### Lazy Properties
```swift
lazy var studentsByID: [UUID: Student] = {
    Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
}()
```
These are computed once and cached. Don't recreate `WorkLookupService` unnecessarily.

### Filtering
Filters are applied in one pass in `filterWorks()`. Adding more filters doesn't significantly impact performance.

### Grouping
Grouping creates dictionaries using `Dictionary(grouping:by:)` which is O(n). For large datasets, consider caching grouped results if grouping doesn't change often.

---

## Migration Checklist

When adopting this refactoring in your project:

- [ ] Add all new files to your Xcode project
- [ ] Update `WorkView.swift` with refactored version
- [ ] Test filtering (subject, students, search)
- [ ] Test grouping (all modes)
- [ ] Test empty states
- [ ] Test compact layout (iPhone portrait)
- [ ] Test regular layout (iPad/Mac)
- [ ] Test scene storage persistence
- [ ] Test work selection (both platforms)
- [ ] Test add work sheet
- [ ] Verify no build errors or warnings
- [ ] Run app and verify behavior matches original

---

## Questions?

Refer to:
- `REFACTORING_SUMMARY.md` - Why and what was changed
- `ARCHITECTURE_DIAGRAM.md` - Visual representation of structure
- This file - How to make changes

The architecture is designed to be intuitive. When in doubt:
1. Logic goes in services (`WorkFilters`, `WorkLookupService`, `WorkGroupingService`)
2. UI goes in views
3. State coordination happens in `WorkView`
