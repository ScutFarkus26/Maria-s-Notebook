import SwiftUI
import SwiftData

struct MarkAsOrderedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let supply: Supply

    @State private var quantity: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Supply")
                        Spacer()
                        Text(supply.name)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Current Stock")
                        Spacer()
                        Text("\(supply.currentQuantity) \(supply.unit)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Order Quantity") {
                    HStack {
                        TextField("0", value: $quantity, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $quantity, in: 1...9999)
                            .labelsHidden()
                        Text(supply.unit)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mark as Ordered")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark as Ordered") {
                        SupplyService.markAsOrdered(supply, quantity: quantity, in: modelContext)
                        dismiss()
                    }
                    .disabled(quantity <= 0)
                }
            }
        }
        .onAppear {
            quantity = supply.reorderAmount > 0 ? supply.reorderAmount : 1
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 250)
        #endif
    }
}

// MARK: - Mark as Received Sheet

struct MarkAsReceivedSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let supply: Supply

    @State private var receivedQuantity: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Supply")
                        Spacer()
                        Text(supply.name)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Current Stock")
                        Spacer()
                        Text("\(supply.currentQuantity) \(supply.unit)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Ordered")
                        Spacer()
                        Text("\(supply.orderedQuantity) \(supply.unit)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Received Quantity") {
                    HStack {
                        TextField("0", value: $receivedQuantity, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $receivedQuantity, in: 0...9999)
                            .labelsHidden()
                        Text(supply.unit)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("New Total")
                        Spacer()
                        Text("\(supply.currentQuantity + receivedQuantity) \(supply.unit)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Mark as Received")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark as Received") {
                        SupplyService.markAsReceived(
                            supply, receivedQuantity: receivedQuantity, in: modelContext
                        )
                        dismiss()
                    }
                    .disabled(receivedQuantity <= 0)
                }
            }
        }
        .onAppear {
            receivedQuantity = supply.orderedQuantity
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }
}
