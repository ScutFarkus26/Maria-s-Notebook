// QuickAdjustSheet.swift
// Extracted from SuppliesListView.swift to reduce type body length.

import SwiftUI
import SwiftData

struct QuickAdjustSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let supply: Supply

    @State private var adjustmentAmount: Int = 0
    @State private var adjustmentType: AdjustmentType = .add
    @State private var reason: String = ""

    enum AdjustmentType: String, CaseIterable {
        case add = "Add"
        case remove = "Remove"
        case set = "Set to"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Current Stock")
                        Spacer()
                        Text("\(supply.currentQuantity) \(supply.unit)")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Adjustment") {
                    Picker("Type", selection: $adjustmentType) {
                        ForEach(AdjustmentType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $adjustmentAmount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Text(supply.unit)
                            .foregroundStyle(.secondary)
                    }

                    if adjustmentType != .set {
                        HStack {
                            Text("New Total")
                            Spacer()
                            Text("\(newTotal) \(supply.unit)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Reason") {
                    TextField("Reason for adjustment", text: $reason)
                }
            }
            .navigationTitle("Adjust Stock")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAdjustment()
                        dismiss()
                    }
                    .disabled(adjustmentAmount == 0 && adjustmentType != .set)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    private var newTotal: Int {
        switch adjustmentType {
        case .add:
            return supply.currentQuantity + adjustmentAmount
        case .remove:
            return max(0, supply.currentQuantity - adjustmentAmount)
        case .set:
            return adjustmentAmount
        }
    }

    private func saveAdjustment() {
        let adjustmentReason = reason.isEmpty ? adjustmentType.rawValue : reason

        switch adjustmentType {
        case .add:
            SupplyService.addStock(to: supply, amount: adjustmentAmount, reason: adjustmentReason, in: modelContext)
        case .remove:
            SupplyService.removeStock(
                from: supply,
                amount: adjustmentAmount,
                reason: adjustmentReason,
                in: modelContext
            )
        case .set:
            SupplyService.updateQuantity(
                for: supply,
                newQuantity: adjustmentAmount,
                reason: adjustmentReason,
                in: modelContext
            )
        }
    }
}
