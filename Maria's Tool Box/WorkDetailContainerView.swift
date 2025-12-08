import SwiftUI
import SwiftData

struct WorkDetailContainerView: View {
    let workID: UUID
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var work: WorkModel? = nil

    var body: some View {
        Group {
            if let w = work {
                WorkDetailView(work: w) {
                    onDone?() ?? dismiss()
                }
            } else {
                ProgressView("Loading…")
                    .padding()
                    .task { await load() }
            }
        }
    }

    @MainActor
    private func load() async {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == workID })
        if let fetched = try? modelContext.fetch(descriptor).first {
            work = fetched
        } else {
            // If not found, dismiss immediately
            onDone?() ?? dismiss()
        }
    }
}
