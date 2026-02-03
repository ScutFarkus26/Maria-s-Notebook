import SwiftUI
import SwiftData

/// A toolbar button for printing open work items.
/// Add this to your work list view's toolbar.
struct WorkPrintButton: View {
    let workItems: [WorkModel]
    let students: [Student]
    let lessons: [Lesson]
    let filterDescription: String
    let sortDescription: String
    
    @State private var showPrintSheet = false
    
    var body: some View {
        Button(action: {
            showPrintSheet = true
        }) {
            Label("Print", systemImage: "printer")
        }
        .disabled(workItems.isEmpty)
        .sheet(isPresented: $showPrintSheet) {
            WorkPrintSheet(
                workItems: workItems,
                students: students,
                lessons: lessons,
                filterDescription: filterDescription,
                sortDescription: sortDescription
            )
        }
    }
}

/// Example usage in a work list view:
///
/// ```swift
/// struct MyWorkListView: View {
///     @Query private var allWork: [WorkModel]
///     @Query private var students: [Student]
///     @Query private var lessons: [Lesson]
///
///     @State private var filterStatus: WorkStatus = .active
///     @State private var sortOrder: SortOrder = .dueDate
///
///     private var filteredWork: [WorkModel] {
///         allWork.filter { $0.status == filterStatus }
///     }
///
///     private var sortedWork: [WorkModel] {
///         // Apply sorting...
///         filteredWork.sorted { ... }
///     }
///
///     var body: some View {
///         List(sortedWork) { work in
///             WorkRow(work: work)
///         }
///         .toolbar {
///             ToolbarItem(placement: .primaryAction) {
///                 WorkPrintButton(
///                     workItems: sortedWork,
///                     students: students,
///                     lessons: lessons,
///                     filterDescription: "Status: \(filterStatus.displayName)",
///                     sortDescription: "By \(sortOrder.displayName)"
///                 )
///             }
///         }
///     }
/// }
/// ```

#Preview("Print Button") {
    NavigationStack {
        List {
            Text("Sample Work Item 1")
            Text("Sample Work Item 2")
            Text("Sample Work Item 3")
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                WorkPrintButton(
                    workItems: [],
                    students: [],
                    lessons: [],
                    filterDescription: "All Open Work",
                    sortDescription: "By Due Date"
                )
            }
        }
    }
}
