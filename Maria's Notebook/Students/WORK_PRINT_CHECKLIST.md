# Work Print Feature - Integration Checklist

## Quick Start (5 Minutes)

Follow these steps to add print functionality to your work view:

### ✅ Step 1: Locate Your Work List View
Find the view where you display your list of work items. This is likely:
- `WorkAgendaView.swift`
- `WorkPlanningView.swift`
- Or a similar file in `RootDetailContent.swift`

### ✅ Step 2: Identify Your Data Sources
In that view, find:
- [ ] Your work items array (e.g., `@Query private var work: [WorkModel]`)
- [ ] Your students array (e.g., `@Query private var students: [Student]`)
- [ ] Your lessons array (e.g., `@Query private var lessons: [Lesson]`)
- [ ] Any filtering logic (e.g., `filteredWork` computed property)
- [ ] Any sorting logic (e.g., `sortedWork` computed property)

### ✅ Step 3: Add Print Button to Toolbar
Add this to your view's `.toolbar` modifier:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        WorkPrintButton(
            workItems: yourWorkArray,          // Replace with your work array
            students: yourStudentsArray,       // Replace with your students array
            lessons: yourLessonsArray,         // Replace with your lessons array
            filterDescription: "Describe current filter",  // Update this
            sortDescription: "Describe current sort"       // Update this
        )
    }
}
```

### ✅ Step 4: Test
Build and run your app:
- [ ] Navigate to your work view
- [ ] Click the print button (printer icon)
- [ ] Verify the preview looks correct
- [ ] Try printing or printing to PDF

## Detailed Integration Examples

### Example 1: Simple View with No Filtering

```swift
struct SimpleWorkView: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    var body: some View {
        List(work) { item in
            WorkRow(work: item)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                WorkPrintButton(
                    workItems: work,
                    students: students,
                    lessons: lessons,
                    filterDescription: "All work items",
                    sortDescription: "Default order"
                )
            }
        }
    }
}
```

### Example 2: With Status Filter

```swift
struct FilteredWorkView: View {
    @Query private var allWork: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    @State private var showOnlyOpen = true
    
    private var displayedWork: [WorkModel] {
        showOnlyOpen ? allWork.filter { $0.isOpen } : allWork
    }
    
    var body: some View {
        List(displayedWork) { item in
            WorkRow(work: item)
        }
        .toolbar {
            Toggle("Open Only", isOn: $showOnlyOpen)
            
            ToolbarItem(placement: .primaryAction) {
                WorkPrintButton(
                    workItems: displayedWork,
                    students: students,
                    lessons: lessons,
                    filterDescription: showOnlyOpen ? "Open work only" : "All work",
                    sortDescription: "Default"
                )
            }
        }
    }
}
```

### Example 3: With Multiple Filters and Sorts

```swift
struct AdvancedWorkView: View {
    @Query private var allWork: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    @State private var filterStatus: WorkStatus? = .active
    @State private var sortOrder: SortOrder = .dueDate
    
    private var displayedWork: [WorkModel] {
        var result = allWork
        
        // Apply filter
        if let status = filterStatus {
            result = result.filter { $0.status == status }
        }
        
        // Apply sort
        result = sortOrder.sort(result)
        
        return result
    }
    
    private var filterDescription: String {
        if let status = filterStatus {
            return "Status: \(status.displayName)"
        }
        return "All statuses"
    }
    
    private var sortDescription: String {
        "By \(sortOrder.rawValue)"
    }
    
    var body: some View {
        List(displayedWork) { item in
            WorkRow(work: item)
        }
        .toolbar {
            Menu("Filter & Sort") {
                Picker("Status", selection: $filterStatus) {
                    Text("All").tag(WorkStatus?.none)
                    ForEach(WorkStatus.allCases) { status in
                        Text(status.displayName).tag(Optional(status))
                    }
                }
                
                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
            }
            
            WorkPrintButton(
                workItems: displayedWork,
                students: students,
                lessons: lessons,
                filterDescription: filterDescription,
                sortDescription: sortDescription
            )
        }
    }
}
```

## Troubleshooting

### Print Button is Grayed Out
**Problem**: The print button appears but is disabled.
**Solution**: The button disables when `workItems` is empty. Check that you're passing a non-empty array.

### Nothing Happens When Clicking Print
**Problem**: Button is enabled but clicking does nothing.
**Solution**: 
1. Check console for errors
2. Verify you imported SwiftUI and SwiftData
3. Make sure the sheet modifier is present (it's in `WorkPrintButton`)

### Print Preview is Empty
**Problem**: Print dialog shows but content is blank.
**Solution**:
1. Verify students and lessons arrays have data
2. Check that work items have valid `studentID` and `lessonID` strings
3. Ensure `AppColors.color(forSubject:)` is available

### Students Not Grouping Correctly
**Problem**: Print shows but students aren't grouped properly.
**Solution**:
1. Verify work items have valid `studentID` strings (UUID format)
2. Ensure students array contains matching UUIDs
3. Check console for any parsing errors

### macOS Print Dialog Not Appearing
**Problem**: On macOS, nothing happens when clicking print.
**Solution**:
1. Check that your app has the required entitlements
2. Verify `NSPrintOperation` calls aren't failing silently
3. Check console for any permissions errors

## Testing Checklist

Before considering this feature complete:

- [ ] Print button appears in toolbar
- [ ] Button is enabled when work items exist
- [ ] Button is disabled when no work items
- [ ] Clicking button shows preview sheet
- [ ] Preview shows correct data
- [ ] Students are properly grouped
- [ ] Lesson names display correctly
- [ ] Subject colors appear
- [ ] Due dates are formatted properly
- [ ] Overdue items show in red
- [ ] Filter description is accurate
- [ ] Sort description is accurate
- [ ] Clicking "Print" opens native dialog
- [ ] iOS: Print dialog shows
- [ ] macOS: Print preview opens
- [ ] PDF export works (print to PDF)
- [ ] Actual printing works
- [ ] Empty state handled gracefully
- [ ] Multiple pages handled if needed

## Advanced: Customizing Filter/Sort Descriptions

If you have complex filtering, create helper functions:

```swift
// In your view
private var filterDescription: String {
    var parts: [String] = []
    
    if let status = filterStatus {
        parts.append("Status: \(status.displayName)")
    }
    
    if let kind = filterKind {
        parts.append("Kind: \(kind.displayName)")
    }
    
    if let student = filterStudent {
        parts.append("Student: \(student.fullName)")
    }
    
    if hasSearchText {
        parts.append("Search: \"\(searchText)\"")
    }
    
    return parts.isEmpty ? "No filters" : parts.joined(separator: " • ")
}

private var sortDescription: String {
    switch sortOrder {
    case .dueDate:
        return "By Due Date" + (sortAscending ? " ↑" : " ↓")
    case .studentName:
        return "By Student Name"
    case .lessonName:
        return "By Lesson"
    default:
        return "Custom order"
    }
}
```

## Need Help?

Refer to:
- `WORK_PRINT_INTEGRATION.md` - Detailed feature documentation
- `WORK_PRINT_VISUAL_GUIDE.md` - Visual layout guide
- `ExampleWorkListViewWithPrint.swift` - Complete working example
- `WorkPrintView.swift` - Implementation details

The example file shows a complete, working implementation with filtering, sorting, and search that you can reference.
