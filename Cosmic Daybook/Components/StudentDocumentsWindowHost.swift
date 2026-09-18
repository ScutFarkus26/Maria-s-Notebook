import CoreData
import SwiftUI

#if os(macOS)
/// Documents are sustained record work on a Mac, so they get a focused window
/// instead of sharing a cramped sheet with the student record.
struct StudentDocumentsWindowHost: View {
    let studentID: UUID
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        if let student = viewContext.object(CDStudent.self, id: studentID) {
            StudentFilesTab(student: student)
                .navigationTitle("Documents — \(student.fullName)")
        } else {
            ContentUnavailableView(
                "Student Not Found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("This student may have been removed.")
            )
            .frame(minWidth: 560, minHeight: 420)
        }
    }
}
#endif
