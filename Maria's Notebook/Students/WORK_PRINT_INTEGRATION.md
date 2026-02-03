# Work Print Feature Integration Guide

## Overview

I've created a complete print feature for your Work view that allows you to print all open work items in a consolidated, paper-efficient format. The print view automatically groups work by student and includes all relevant information.

## Files Created

1. **WorkPrintView.swift** - The main print view component
   - `WorkPrintView` - The consolidated, print-friendly layout
   - `WorkPrintSheet` - Sheet presentation with preview
   - `WorkPrintController` - Platform-specific print controllers (iOS/macOS)

2. **WorkPrintButton.swift** - Reusable toolbar button
   - `WorkPrintButton` - Simple button you can add to any toolbar

3. **ExampleWorkListViewWithPrint.swift** - Complete example
   - Shows how to integrate print into your work list
   - Includes filter/sort examples
   - Complete working implementation

## Quick Integration

### Step 1: Add Print Button to Your Work View

Find your work list view (likely in `WorkAgendaView` or similar) and add the print button to the toolbar:

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        WorkPrintButton(
            workItems: displayedWork,        // Your filtered/sorted work array
            students: students,              // Your students array
            lessons: lessons,                // Your lessons array
            filterDescription: "Open items only",  // Description of current filter
            sortDescription: "By Due Date"   // Description of current sort
        )
    }
}
```

### Step 2: Customize Filter/Sort Descriptions

The print view includes a header showing what filters and sorting are applied. Update these dynamically based on your UI state:

```swift
private var filterDescription: String {
    switch yourFilterState {
    case .openOnly: return "Open items only"
    case .dueToday: return "Due today"
    // ... etc
    }
}

private var sortDescription: String {
    switch yourSortState {
    case .dueDate: return "By Due Date"
    case .student: return "By Student Name"
    // ... etc
    }
}
```

## Features

### Print Layout
- **Paper-efficient design** - Compact layout that fits more items per page
- **Grouped by student** - All work for each student is grouped together
- **Clear information hierarchy** - Student name → Work items with details
- **Checkbox for tracking** - Each item has a checkbox for manual tracking

### What's Printed
For each work item:
- Lesson name with color indicator
- Work kind (Practice, Follow Up, Research, Report)
- Status (if not Active)
- Due date (highlighted in red if overdue)
- Title and notes (if present)
- Step progress (for report-type work)

### Print Header Includes
- Report title and date
- Current filter description
- Current sort description
- Total count of items and students

## Platform Support

### iOS
- Uses `UIPrintInteractionController`
- Shows native iOS print dialog
- Includes preview in the sheet

### macOS
- Uses `NSPrintOperation`
- Opens standard macOS print dialog with preview
- Supports print-to-PDF

## Example Usage Patterns

### Simple Integration
```swift
struct MyWorkView: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    var body: some View {
        List(work) { item in
            WorkRow(work: item)
        }
        .toolbar {
            WorkPrintButton(
                workItems: work,
                students: students,
                lessons: lessons,
                filterDescription: "All work",
                sortDescription: "Default order"
            )
        }
    }
}
```

### With Filtering
```swift
struct MyWorkView: View {
    @Query private var allWork: [WorkModel]
    @State private var showOnlyOpen = true
    
    private var filteredWork: [WorkModel] {
        showOnlyOpen ? allWork.filter { $0.isOpen } : allWork
    }
    
    var body: some View {
        List(filteredWork) { item in
            WorkRow(work: item)
        }
        .toolbar {
            Toggle("Open Only", isOn: $showOnlyOpen)
            
            WorkPrintButton(
                workItems: filteredWork,
                students: students,
                lessons: lessons,
                filterDescription: showOnlyOpen ? "Open items only" : "All items",
                sortDescription: "Default"
            )
        }
    }
}
```

### With Dynamic Filtering and Sorting
See `ExampleWorkListViewWithPrint.swift` for a complete example with:
- Multiple filter options
- Multiple sort orders
- Search functionality
- Dynamic descriptions that update based on selections

## Customization Options

### Modify Print Layout
Edit `WorkPrintView.swift` to customize:
- Font sizes (currently optimized for readability)
- Spacing and padding
- What information is displayed
- Grouping strategy (currently by student)

### Paper Size
The views are currently sized for US Letter (612 x 792 points):
```swift
.frame(width: 612, height: 792)
```

To change to A4 or other sizes, update these dimensions in:
- `WorkPrintView` rendering calls
- `WorkPrintController` implementations

### Color vs. Black & White
The current implementation includes color indicators (subject colors). These will print in grayscale on B&W printers automatically, but you can force grayscale by modifying the `AppColors.color(forSubject:)` calls.

## Testing

1. **Preview**: The print sheet includes a scaled preview so users can see what will print
2. **Empty state**: The print button is disabled when there are no items
3. **Platform testing**: Test on both iOS and macOS to ensure proper print dialog behavior

## Future Enhancements

Potential improvements you could add:
- Export to PDF directly (without print dialog)
- Email the print view as PDF
- Customizable grouping (by lesson, by due date, etc.)
- Include/exclude completed items toggle
- Print multiple pages if content exceeds one page
- Page numbers and headers on multi-page prints

## Questions?

The implementation follows Apple's standard patterns for printing:
- iOS: `UIPrintInteractionController` for native print dialogs
- macOS: `NSPrintOperation` with `NSView` rendering
- Both: `ImageRenderer` for SwiftUI → PDF conversion

All code is properly commented and follows your app's existing patterns.
