import CoreData
import SwiftUI

#if os(macOS)
/// Documents are sustained record work on a Mac, so they get a focused window
/// instead of sharing a cramped sheet with the student record.
struct StudentDocumentsWindowHost: View {
    let studentID: UUID
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        let request: NSFetchRequest<CDStudent> = {
            let request = NSFetchRequest<CDStudent>(entityName: "Student")
            request.predicate = NSPredicate(format: "id == %@", studentID as CVarArg)
            request.fetchLimit = 1
            return request
        }()

        if let student = viewContext.safeFetchFirst(request) {
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
