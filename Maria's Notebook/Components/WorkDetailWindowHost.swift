import SwiftUI
import CoreData

struct WorkDetailWindowHost: View {
    let workID: UUID
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        let workModelFetch: NSFetchRequest<CDWorkModel> = {
            let r = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
            r.predicate = NSPredicate(format: "id == %@", workID as CVarArg)
            return r
        }()
        if let workModel = viewContext.safeFetchFirst(workModelFetch) {
            WorkDetailView(workID: workModel.id ?? UUID())
                .frame(minWidth: 400, minHeight: 300)
        } else {
            ContentUnavailableView("Work Not Found", systemImage: "doc.text.magnifyingglass")
        }
    }
}
