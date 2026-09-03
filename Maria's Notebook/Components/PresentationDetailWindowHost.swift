import SwiftUI
import CoreData

#if os(macOS)
struct PresentationDetailWindowHost: View {
    let lessonAssignmentID: UUID
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        if let lessonAssignment = viewContext.object(CDLessonAssignment.self, id: lessonAssignmentID) {
            // Done, Cancel and Delete all mean "close this window", so the
            // window is named rather than left to the ambient `dismiss`, which
            // has no presentation to close out here and quietly does nothing.
            PresentationDetailView(lessonAssignment: lessonAssignment) {
                dismissWindow(id: "PresentationDetailWindow", value: lessonAssignmentID)
            }
            .frame(minWidth: 720, minHeight: 640)
            .navigationTitle(windowTitle(for: lessonAssignment))
            .background(FullScreenAuxiliaryWindow())
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
