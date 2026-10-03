import CoreData
import SwiftUI

#if os(macOS)
struct StudentReportWindowHost: View {
    let studentID: UUID

    var body: some View {
        EntityWindowHost(
            id: studentID,
            notFound: WindowHostNotFound(
                "Student Not Found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("This student may have been removed."),
                minSize: CGSize(width: 500, height: 400)
            )
        ) { (student: CDStudent) in
            ReportGeneratorView(student: student, isWindowWorkspace: true)
        }
    }
}
#endif
