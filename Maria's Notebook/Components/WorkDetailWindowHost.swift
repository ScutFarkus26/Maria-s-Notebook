import SwiftUI
import CoreData

struct WorkDetailWindowHost: View {
    let workID: UUID
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        // Try to find CDWorkModel by id first (if already migrated)
        let workModelFetch = { let r = CDWorkModel.fetchRequest() as! NSFetchRequest<CDWorkModel>; r.predicate = NSPredicate(format: "id == %@", workID as CVarArg); return r }()
        if let workModel = viewContext.safeFetchFirst(workModelFetch) {
            WorkDetailView(workID: workModel.id ?? UUID())
                .frame(minWidth: 400, minHeight: 300)
        } else {
            // Fallback: try to find CDWorkModel by legacyContractID (if not yet migrated)
            let legacyFetch = { let r = CDWorkModel.fetchRequest() as! NSFetchRequest<CDWorkModel>; r.predicate = NSPredicate(format: "legacyContractID == %@", workID as CVarArg); return r }()
            if let workModel = viewContext.safeFetchFirst(legacyFetch) {
                WorkDetailView(workID: workModel.id ?? UUID())
                    .frame(minWidth: 400, minHeight: 300)
            } else {
                ContentUnavailableView("Work Not Found", systemImage: "doc.text.magnifyingglass")
            }
        }
    }
}
