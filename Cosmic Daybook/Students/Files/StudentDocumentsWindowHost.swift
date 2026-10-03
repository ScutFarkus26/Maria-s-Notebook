import CoreData
import SwiftUI

#if os(macOS)
/// Documents are sustained record work on a Mac, so they get a focused window
/// instead of sharing a cramped sheet with the student record.
struct StudentDocumentsWindowHost: View {
    let studentID: UUID

    var body: some View {
        EntityWindowHost(
            id: studentID,
            notFound: WindowHostNotFound(
                "Student Not Found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("This student may have been removed."),
                minSize: CGSize(width: 560, height: 420)
            )
        ) { (student: CDStudent) in
            StudentFilesTab(student: student)
                .navigationTitle("Documents — \(student.fullName)")
        }
    }
}
#endif
