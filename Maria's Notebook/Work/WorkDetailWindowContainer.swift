import SwiftUI
import SwiftData

struct WorkDetailWindowContainer: View {
    let workID: UUID
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let contract = try? modelContext.fetch(
            FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == workID })
        ).first {
            WorkContractDetailSheet(contract: contract)
                #if os(macOS)
                .frame(minWidth: 500, minHeight: 400)
                #endif
        } else if let legacyWork = try? modelContext.fetch(
            FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == workID })
        ).first {
            ContentUnavailableView {
                Label("Legacy Work UI Removed", systemImage: "exclamationmark.triangle")
            } description: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This work was created with the legacy Work UI which has been removed. Please use Contracts.")
                    if !legacyWork.title.isEmpty {
                        Text("Work title: \(legacyWork.title)")
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 400, minHeight: 200)
            #endif
        } else {
            ContentUnavailableView("Work not found", systemImage: "doc.questionmark")
                #if os(macOS)
                .frame(minWidth: 400, minHeight: 200)
                #endif
        }
    }
}
