# Work Print Feature - Quick Reference

## 🚀 Copy-Paste Solutions

### Basic Integration (Copy This!)

```swift
// Add to your work view's toolbar
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        WorkPrintButton(
            workItems: work,              // Your work array
            students: students,           // Your students array  
            lessons: lessons,             // Your lessons array
            filterDescription: "All open work",
            sortDescription: "Default"
        )
    }
}
```

### With Open-Only Filter

```swift
private var openWork: [WorkModel] {
    work.filter { $0.isOpen }
}

// In toolbar:
WorkPrintButton(
    workItems: openWork,
    students: students,
    lessons: lessons,
    filterDescription: "Open work only",
    sortDescription: "Default"
)
```

### With Due Date Sort

```swift
private var sortedWork: [WorkModel] {
    work.sorted { w1, w2 in
        switch (w1.dueAt, w2.dueAt) {
        case (let d1?, let d2?): return d1 < d2
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return w1.assignedAt < w2.assignedAt
        }
    }
}

// In toolbar:
WorkPrintButton(
    workItems: sortedWork,
    students: students,
    lessons: lessons,
    filterDescription: "All work",
    sortDescription: "By due date"
)
```

### With Status Filter Picker

```swift
@State private var filterStatus: WorkStatus = .active

private var filteredWork: [WorkModel] {
    work.filter { $0.status == filterStatus }
}

// In toolbar:
Picker("Status", selection: $filterStatus) {
    ForEach(WorkStatus.allCases) { status in
        Text(status.rawValue).tag(status)
    }
}

WorkPrintButton(
    workItems: filteredWork,
    students: students,
    lessons: lessons,
    filterDescription: "Status: \(filterStatus.rawValue)",
    sortDescription: "Default"
)
```

## 📋 Common Patterns

### Pattern 1: Print Current View
**When**: You want to print exactly what's displayed in the list

```swift
var body: some View {
    List(displayedWork) { work in
        WorkRow(work: work)
    }
    .toolbar {
        WorkPrintButton(
            workItems: displayedWork,  // Same array shown in List
            students: students,
            lessons: lessons,
            filterDescription: currentFilterText,
            sortDescription: currentSortText
        )
    }
}
```

### Pattern 2: Print with Date Range
**When**: You want to print work due within a specific timeframe

```swift
private var workDueThisWeek: [WorkModel] {
    let now = Date()
    let weekFromNow = Calendar.current.date(byAdding: .day, value: 7, to: now)!
    return work.filter { work in
        guard let due = work.dueAt else { return false }
        return due >= now && due <= weekFromNow
    }
}

// In toolbar:
WorkPrintButton(
    workItems: workDueThisWeek,
    students: students,
    lessons: lessons,
    filterDescription: "Due this week",
    sortDescription: "By due date"
)
```

### Pattern 3: Print for Specific Student
**When**: You want to print work for one student only

```swift
@State private var selectedStudentID: UUID?

private var studentWork: [WorkModel] {
    guard let id = selectedStudentID else { return work }
    let idString = id.uuidString
    return work.filter { $0.studentID == idString }
}

private var studentName: String {
    guard let id = selectedStudentID,
          let student = students.first(where: { $0.id == id }) else {
        return "All students"
    }
    return student.fullName
}

// In toolbar:
Picker("Student", selection: $selectedStudentID) {
    Text("All").tag(UUID?.none)
    ForEach(students) { student in
        Text(student.fullName).tag(Optional(student.id))
    }
}

WorkPrintButton(
    workItems: studentWork,
    students: students,
    lessons: lessons,
    filterDescription: studentName,
    sortDescription: "Default"
)
```

### Pattern 4: Print Overdue Only
**When**: You want to focus on overdue work items

```swift
private var overdueWork: [WorkModel] {
    let now = Date()
    return work.filter { work in
        guard let due = work.dueAt else { return false }
        return due < now && work.status != .complete
    }
}

// In toolbar:
WorkPrintButton(
    workItems: overdueWork,
    students: students,
    lessons: lessons,
    filterDescription: "Overdue items only",
    sortDescription: "By due date"
)
```

## 🎨 Customization Snippets

### Change Print View Title
Edit `WorkPrintView.swift`, find:
```swift
Text("Open Work Report")
    .font(.system(size: 18, weight: .bold))
```
Change to:
```swift
Text("Weekly Work Summary")  // Your custom title
    .font(.system(size: 18, weight: .bold))
```

### Hide Notes from Print
Edit `WorkPrintView.swift`, comment out:
```swift
// Notes (if present and brief)
// if !work.notes.isEmpty {
//     Text(work.notes)
//         .font(.system(size: 10))
//         .foregroundStyle(.secondary)
//         .lineLimit(2)
//         .padding(.top, 1)
// }
```

### Change Font Sizes
Edit `WorkPrintView.swift`, adjust these values:
```swift
// For larger text (easier reading):
.font(.system(size: 14))  // Change from 12
.font(.system(size: 12))  // Change from 11
.font(.system(size: 11))  // Change from 10

// For smaller text (more items per page):
.font(.system(size: 10))  // Change from 12
.font(.system(size: 9))   // Change from 11
.font(.system(size: 8))   // Change from 10
```

### Group by Lesson Instead of Student
Edit `WorkPrintView.swift`, replace `groupedWork`:
```swift
private var groupedWork: [(Lesson, [WorkModel])] {
    let lessonDict = Dictionary(grouping: workItems) { work in
        work.lessonID
    }
    
    return lessonDict.compactMap { (lessonIDString, works) in
        guard let lessonID = UUID(uuidString: lessonIDString),
              let lesson = lessons.first(where: { $0.id == lessonID }) else {
            return nil
        }
        let sorted = works.sorted { $0.assignedAt < $1.assignedAt }
        return (lesson, sorted)
    }.sorted { $0.0.name < $1.0.name }
}
```

Then update `studentSection` to `lessonSection`:
```swift
@ViewBuilder
private func lessonSection(lesson: Lesson, works: [WorkModel]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 6) {
            Circle()
                .fill(AppColors.color(forSubject: lesson.subject))
                .frame(width: 8, height: 8)
            Text(lesson.name)
                .font(.system(size: 14, weight: .semibold))
        }
        .padding(.bottom, 4)
        
        ForEach(Array(works.enumerated()), id: \.offset) { index, work in
            workItemRow(work: work, index: index + 1)
        }
    }
}
```

## 📱 Platform-Specific Notes

### iOS
- Uses native `UIPrintInteractionController`
- Shows iOS-style print dialog
- Supports AirPrint printers
- Can print to PDF via "Save PDF to Files"

### macOS  
- Uses `NSPrintOperation`
- Shows macOS print preview window
- Supports all macOS printers
- Can print to PDF via "Save as PDF" button

## ⚡ Performance Tips

### For Large Lists (100+ items)
Consider adding pagination or limiting print items:

```swift
private var printableWork: [WorkModel] {
    // Limit to first 50 items
    Array(displayedWork.prefix(50))
}

WorkPrintButton(
    workItems: printableWork,
    students: students,
    lessons: lessons,
    filterDescription: "\(printableWork.count) of \(displayedWork.count) items",
    sortDescription: "Default"
)
```

### For Slow Rendering
If print preview is slow to generate:

```swift
// Reduce preview scale in WorkPrintSheet
.frame(width: 612 * 0.3, height: 792 * 0.3) // Changed from 0.5
.scaleEffect(0.3) // Changed from 0.5
```

## 🐛 Quick Fixes

### "AppColors not found"
Make sure you're using your app's color utility, or replace with:
```swift
Color.blue  // Replace AppColors.color(forSubject: lesson.subject)
```

### "WorkStatus/WorkKind not found"
Verify your WorkModel enums match, or use:
```swift
work.statusRaw  // Instead of work.status.displayName
```

### Students Not Showing
Debug with:
```swift
// In WorkPrintView, add debugging:
private var groupedWork: [(Student, [WorkModel])] {
    print("Total work items: \(workItems.count)")
    print("Total students: \(students.count)")
    // ... rest of code
}
```

### Print Dialog Not Showing
Check your Info.plist includes:
```xml
<key>NSPrintingEnabled</key>
<true/>
```

## 📞 Support

If you run into issues:

1. **Check the example**: `ExampleWorkListViewWithPrint.swift` has a complete working implementation
2. **Review integration guide**: `WORK_PRINT_INTEGRATION.md` has detailed explanations
3. **Verify your data**: Use print statements to check your arrays have data
4. **Test incrementally**: Start with the basic example, then add filtering/sorting

## 🎯 Success Checklist

- [ ] Print button appears in toolbar
- [ ] Clicking shows preview
- [ ] Preview displays your work items
- [ ] Print dialog opens correctly
- [ ] Printed output is readable
- [ ] Filter description is accurate
- [ ] Sort description is accurate

That's it! You should now have a working print feature. 🎉
