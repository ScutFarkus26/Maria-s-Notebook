import CoreData
import SwiftUI

struct WorkDetailWindowHost: View {
    let workID: UUID
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        EntityWindowHost(
            id: workID,
            minSize: CGSize(width: 400, height: 300),
            notFound: WindowHostNotFound("Work Not Found", systemImage: "doc.text.magnifyingglass")
        ) { (workModel: CDWorkModel) in
            // Save, Cancel and Delete all mean "close this window", so the
            // window is named rather than left to the ambient `dismiss`, which
            // has no presentation to close out here and quietly does nothing.
            WorkDetailView(workID: workModel.id ?? UUID()) {
                dismissWindow(id: "WorkDetailWindow", value: workID)
            }
            .navigationTitle(workModel.title.isEmpty ? "Work" : workModel.title)
        }
    }
}
