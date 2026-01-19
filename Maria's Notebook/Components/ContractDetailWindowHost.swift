import SwiftUI
import SwiftData

struct ContractDetailWindowHost: View {
    let workID: UUID
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        // Try to find WorkModel by id first (if already migrated)
        let workModelFetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == workID })
        if let workModel = try? modelContext.fetch(workModelFetch).first {
            WorkDetailView(workID: workModel.id)
                .frame(minWidth: 400, minHeight: 300)
        } else {
            // Fallback: try to find WorkModel by legacyContractID (if not yet migrated)
            let legacyFetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.legacyContractID == workID })
            if let workModel = try? modelContext.fetch(legacyFetch).first {
                WorkDetailView(workID: workModel.id)
                    .frame(minWidth: 400, minHeight: 300)
            } else {
                ContentUnavailableView("Work Not Found", systemImage: "doc.text.magnifyingglass")
            }
        }
    }
}

