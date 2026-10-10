import SwiftUI
import CoreData

/// A staple's history, newest first: "Low · Ana", "Out", "Restocked", with
/// when each happened, each person named as they go by now.
struct AssistantRestockHistorySheet: View {
    let model: AssistantRestockModel
    let staple: CDSupply

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = model.history(for: staple)
        let names = model.author.names
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("No changes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries, id: \.objectID) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Self.line(for: entry, names: names))
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

    /// The entry's reason, naming who made it as they go by now (`names`,
    /// `RestockHistoryLine`); a counted change with no reason: "Added 3", "Removed 2".
    static func line(for entry: CDSupplyTransaction, names: ClassroomNames.Snapshot) -> String {
        let reason = RestockHistoryLine.text(reason: entry.reason, changedByID: entry.changedByID, names: names)
        guard reason.isEmpty else { return reason }
        return entry.quantityChange > 0 ? "Added \(entry.quantityChange)" : "Removed \(abs(entry.quantityChange))"
    }
}
