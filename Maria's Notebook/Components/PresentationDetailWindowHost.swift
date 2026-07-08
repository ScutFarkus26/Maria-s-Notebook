import SwiftUI
import CoreData

#if os(macOS)
struct PresentationDetailWindowHost: View {
    let lessonAssignmentID: UUID
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        let fetchRequest: NSFetchRequest<CDLessonAssignment> = {
            let request = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
            request.predicate = NSPredicate(format: "id == %@", lessonAssignmentID as CVarArg)
            return request
        }()

        if let lessonAssignment = viewContext.safeFetchFirst(fetchRequest) {
            PresentationDetailView(lessonAssignment: lessonAssignment)
                .frame(minWidth: 720, minHeight: 640)
                .navigationTitle(windowTitle(for: lessonAssignment))
        } else {
            ContentUnavailableView("Presentation Not Found", systemImage: "rectangle.badge.magnifyingglass")
                .frame(minWidth: 400, minHeight: 300)
        }
    }

    private func windowTitle(for lessonAssignment: CDLessonAssignment) -> String {
        if let lessonName = lessonAssignment.lesson?.name, !lessonName.isEmpty {
            return lessonName
        }
        return "Presentation"
    }
}
#endif
