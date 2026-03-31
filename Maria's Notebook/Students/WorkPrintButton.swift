import SwiftUI
import CoreData

/// A toolbar button for printing open work items.
/// Add this to your work list view's toolbar.
struct WorkPrintButton: View {
    let workItems: [CDWorkModel]
    let students: [CDStudent]
    let lessons: [CDLesson]
    let filterDescription: String
    let sortDescription: String
    
    @State private var showPrintSheet = false
    
    var body: some View {
        Button(action: {
            showPrintSheet = true
        }, label: {
            Label("Print", systemImage: "printer")
        })
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
