import SwiftUI
import SwiftData

struct ContractDetailWindowHost: View {
    let workID: UUID
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        if let contract = (try? modelContext.fetch(FetchDescriptor<WorkContract>(predicate: #Predicate<WorkContract> { $0.id == workID })))?.first {
            WorkContractDetailSheet(contract: contract)
                .frame(minWidth: 400, minHeight: 300)
        } else {
            ContentUnavailableView("Contract Not Found", systemImage: "doc.text.magnifyingglass")
        }
    }
}

