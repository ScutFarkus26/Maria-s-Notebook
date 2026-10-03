import CoreData
import SwiftUI

#if os(macOS)
struct PresentationDetailWindowHost: View {
    let lessonAssignmentID: UUID
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        EntityWindowHost(
            id: lessonAssignmentID,
            notFound: WindowHostNotFound(
                "Presentation Not Found",
                systemImage: "rectangle.badge.magnifyingglass",
                minSize: CGSize(width: 400, height: 300)
            )
        ) { (lessonAssignment: CDLessonAssignment) in
            // Done, Cancel and Delete all mean "close this window", so the
            // window is named rather than left to the ambient `dismiss`, which
            // has no presentation to close out here and quietly does nothing.
            PresentationDetailView(lessonAssignment: lessonAssignment) {
                dismissWindow(id: "PresentationDetailWindow", value: lessonAssignmentID)
            }
            .frame(minWidth: 720, minHeight: 640)
            .navigationTitle(windowTitle(for: lessonAssignment))
            .background(FullScreenAuxiliaryWindow())
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
