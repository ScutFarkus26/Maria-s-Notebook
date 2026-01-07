import SwiftUI
import SwiftData

struct ContractDetailWindowHost: View {
    let workID: UUID
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        // Fetch all and filter in memory to avoid predicate issues with WorkContract/UUID
        let allContractsDescriptor = FetchDescriptor<WorkContract>()
        if let allContracts = try? modelContext.fetch(allContractsDescriptor),
           let contract = allContracts.first(where: { $0.id == workID }) {
            WorkContractDetailSheet(contract: contract)
                .frame(minWidth: 400, minHeight: 300)
        } else {
            ContentUnavailableView("Contract Not Found", systemImage: "doc.text.magnifyingglass")
        }
    }
}

