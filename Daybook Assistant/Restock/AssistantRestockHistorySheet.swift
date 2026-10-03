import SwiftUI
import CoreData

/// A staple's history, newest first: "Low · Ana", "Out", "Restocked", with
/// when each happened.
struct AssistantRestockHistorySheet: View {
    let model: AssistantRestockModel
    let staple: CDSupply

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = model.history(for: staple)
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("No changes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries, id: \.objectID) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.reason.isEmpty ? change(entry) : entry.reason)
                            Spacer(minLength: 8)
                            if let date = entry.date {
                                Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(staple.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// A counted change with no reason: "+3", "−2".
    private func change(_ entry: CDSupplyTransaction) -> String {
        entry.quantityChange > 0 ? "+\(entry.quantityChange)" : "−\(abs(entry.quantityChange))"
    }
}
