import SwiftUI
import CoreData

struct WorkDetailWindowHost: View {
    let workID: UUID
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let workModelFetch: NSFetchRequest<CDWorkModel> = {
            let r = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
            r.predicate = NSPredicate(format: "id == %@", workID as CVarArg)
            return r
        }()
        if let workModel = viewContext.safeFetchFirst(workModelFetch) {
            // Save, Cancel and Delete all mean "close this window", so the
            // window is named rather than left to the ambient `dismiss`, which
            // has no presentation to close out here and quietly does nothing.
            WorkDetailView(workID: workModel.id ?? UUID()) {
                dismissWindow(id: "WorkDetailWindow", value: workID)
            }
            .frame(minWidth: 400, minHeight: 300)
            .navigationTitle(workModel.title.isEmpty ? "Work" : workModel.title)
        } else {
            ContentUnavailableView("Work Not Found", systemImage: "doc.text.magnifyingglass")
        }
    }
}
