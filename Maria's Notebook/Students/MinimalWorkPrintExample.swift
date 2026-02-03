import SwiftUI
import SwiftData

// MARK: - Minimal Integration Example
// This is the simplest possible integration - just add the print button!

struct MinimalWorkViewWithPrint: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    var body: some View {
        NavigationStack {
            List(work) { workItem in
                VStack(alignment: .leading) {
                    Text(workItem.title)
                        .font(.headline)
                    Text(workItem.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Open Work")
            .toolbar {
                // ⭐️ THIS IS ALL YOU NEED TO ADD! ⭐️
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

// MARK: - Before and After Comparison

// ❌ BEFORE: No print capability
struct BeforeWorkView: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    var body: some View {
        NavigationStack {
            List(work) { workItem in
                Text(workItem.title)
            }
            .navigationTitle("Open Work")
        }
    }
}

// ✅ AFTER: Full print capability
struct AfterWorkView: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    var body: some View {
        NavigationStack {
            List(work) { workItem in
                Text(workItem.title)
            }
            .navigationTitle("Open Work")
            .toolbar {
                WorkPrintButton(
                    workItems: work,
                    students: students,
                    lessons: lessons,
                    filterDescription: "All work",
                    sortDescription: "Default"
                )
            }
        }
    }
}

// MARK: - Visual Integration Guide

/*
 
 ┌─────────────────────────────────────────┐
 │  Open Work                      [🖨️]    │  ← Print button in toolbar
 ├─────────────────────────────────────────┤
 │  📝 Algebra Practice                    │
 │     Emma Rodriguez                      │
 │     Due: Feb 5, 2026                    │
 ├─────────────────────────────────────────┤
 │  📝 Reading Comprehension               │
 │     Michael Chen                        │
 │     Due: Feb 6, 2026                    │
 ├─────────────────────────────────────────┤
 │  📝 Spanish Verbs                       │
 │     Sarah Johnson                       │
 │     Due: Feb 3, 2026 (OVERDUE)          │
 └─────────────────────────────────────────┘
 
 When user taps [🖨️]:
 
 ┌─────────────────────────────────────────┐
 │  Print Preview                          │
 │  ┌───────────────────────────────────┐  │
 │  │ Open Work Report   Feb 3, 2026   │  │
 │  │ Filter: All work items            │  │
 │  │ Sort: Default order               │  │
 │  │ 3 work items • 3 students         │  │
 │  │ ───────────────────────────────   │  │
 │  │                                   │  │
 │  │ Emma Rodriguez                    │  │
 │  │   1. ● Algebra Practice       ☐  │  │
 │  │      Practice • Due: Feb 5       │  │
 │  │                                   │  │
 │  │ Michael Chen                      │  │
 │  │   1. ● Reading Comprehension  ☐  │  │
 │  │      Follow Up • Due: Feb 6      │  │
 │  │                                   │  │
 │  │ Sarah Johnson                     │  │
 │  │   1. ● Spanish Verbs          ☐  │  │
 │  │      Practice • Due: Feb 3       │  │
 │  │      (OVERDUE)                    │  │
 │  └───────────────────────────────────┘  │
 │  [Cancel]                     [Print]   │
 └─────────────────────────────────────────┘
 
 Then opens native print dialog! 🎉
 
 */

// MARK: - The Three Lines That Matter

/*
 
 All you really need is this:
 
     .toolbar {
         WorkPrintButton(
             workItems: yourWorkArray,
             students: yourStudentsArray,
             lessons: yourLessonsArray,
             filterDescription: "Description of current filter",
             sortDescription: "Description of current sort"
         )
     }
 
 That's it! Everything else is handled automatically:
 - Button appears in toolbar
 - Button is disabled when no work items
 - Click shows preview sheet
 - Preview shows formatted work items
 - Print opens native dialog
 - PDF export works automatically
 - iOS and macOS both supported
 
 */

// MARK: - Where to Add It

/*
 
 Find your work list view. It probably looks something like:
 
     struct YourWorkView: View {
         @Query private var work: [WorkModel]
         // ... other properties
         
         var body: some View {
             List(work) { item in
                 // ... your work rows
             }
             .navigationTitle("Work")
             .toolbar {
                 // ← ADD THE PRINT BUTTON HERE!
             }
         }
     }
 
 Just add WorkPrintButton inside the .toolbar { } block!
 
 */

// MARK: - Common View Structures

// Structure 1: Basic list
struct Structure1: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    var body: some View {
        List(work) { item in
            Text(item.title)
        }
        .toolbar {
            WorkPrintButton(workItems: work, students: students, lessons: lessons,
                          filterDescription: "All", sortDescription: "Default")
        }
    }
}

// Structure 2: NavigationStack with list
struct Structure2: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    var body: some View {
        NavigationStack {
            List(work) { item in
                Text(item.title)
            }
            .navigationTitle("Work")
            .toolbar {
                WorkPrintButton(workItems: work, students: students, lessons: lessons,
                              filterDescription: "All", sortDescription: "Default")
            }
        }
    }
}

// Structure 3: With existing toolbar items
struct Structure3: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    @State private var showingAddSheet = false
    
    var body: some View {
        List(work) { item in
            Text(item.title)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Add") { showingAddSheet = true }
            }
            
            ToolbarItem(placement: .primaryAction) {
                WorkPrintButton(workItems: work, students: students, lessons: lessons,
                              filterDescription: "All", sortDescription: "Default")
            }
        }
    }
}

// Structure 4: Split view detail pane
struct Structure4: View {
    @Query private var work: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    var body: some View {
        List(work) { item in
            Text(item.title)
        }
        .navigationTitle("Work")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            WorkPrintButton(workItems: work, students: students, lessons: lessons,
                          filterDescription: "All", sortDescription: "Default")
        }
    }
}

// MARK: - With Filtering (One Step More)

struct WithFiltering: View {
    @Query private var allWork: [WorkModel]
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    
    @State private var showOnlyOpen = true
    
    // Add a filtered array
    private var displayedWork: [WorkModel] {
        showOnlyOpen ? allWork.filter { $0.isOpen } : allWork
    }
    
    var body: some View {
        List(displayedWork) { item in
            Text(item.title)
        }
        .toolbar {
            Toggle("Open Only", isOn: $showOnlyOpen)
            
            // Pass the filtered array instead of all work
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

// MARK: - Preview

#Preview("Minimal Integration") {
    MinimalWorkViewWithPrint()
        .previewEnvironment()
}

#Preview("Before") {
    BeforeWorkView()
        .previewEnvironment()
}

#Preview("After") {
    AfterWorkView()
        .previewEnvironment()
}
