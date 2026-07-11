import CoreData
import SwiftUI

#if os(macOS)
struct StudentReportWindowHost: View {
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
            ReportGeneratorView(student: student, isWindowWorkspace: true)
        } else {
            ContentUnavailableView(
                "Student Not Found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("This student may have been removed.")
            )
            .frame(minWidth: 500, minHeight: 400)
        }
    }
}
#endif
