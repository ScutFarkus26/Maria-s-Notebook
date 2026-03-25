// swiftlint:disable file_length
import SwiftUI
import SwiftData

// Detail view for viewing and editing a supply
// swiftlint:disable:next type_body_length
struct SupplyDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var supply: Supply

    @State private var isEditing = false
    @State private var editName: String = ""
    @State private var editCategory: SupplyCategory = .other
    @State private var editLocation: String = ""
    @State private var editMinimumThreshold: Int = 0
    @State private var editReorderAmount: Int = 0
    @State private var editUnit: String = ""
    @State private var editNotes: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingOrderSheet = false
    @State private var showingReceiveSheet = false

    private var transactions: [SupplyTransaction] {
        SupplyService.fetchRecentTransactions(for: supply, limit: 20)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Status header
                    statusHeader

                    // Current stock card
                    currentStockCard

                    // Details section
                    if isEditing {
                        editableDetailsSection
                    } else {
                        detailsSection
                    }

                    // Transaction history
                    historySection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle(isEditing ? "Edit Supply" : supply.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                        }
                    } else {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if isEditing {
                        Button("Save") {
                            saveChanges()
                            isEditing = false
                        }
                    } else {
                        Menu {
                            Button {
                                startEditing()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Divider()

                            if supply.isOnOrder {
                                Button {
                                    showingReceiveSheet = true
                                } label: {
                                    Label("Mark as Received", systemImage: "checkmark.circle")
                                }
                            } else {
                                Button {
                                    showingOrderSheet = true
                                } label: {
                                    Label("Mark as Ordered", systemImage: "shippingbox")
                                }
                            }

                            Divider()

                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete Supply",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    SupplyService.deleteSupply(supply, in: modelContext)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete \"\(supply.name)\"? This action cannot be undone.")
            }
        }
        .sheet(isPresented: $showingOrderSheet) {
            MarkAsOrderedSheet(supply: supply)
        }
        .sheet(isPresented: $showingReceiveSheet) {
            MarkAsReceivedSheet(supply: supply)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    // MARK: - Status Header

    private var statusHeader: some View {
        HStack(spacing: 16) {
            // Category icon
            ZStack {
                Circle()
                    .fill(supply.status.color.opacity(0.15))
                    .frame(width: 60, height: 60)

                Image(systemName: supply.category.icon)
                    .font(.title)
                    .foregroundStyle(supply.status.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(supply.category.rawValue)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Image(systemName: supply.status.icon)
                    Text(supply.status.rawValue)
                        .font(.headline)
                }
                .foregroundStyle(supply.status.color)
            }

            Spacer()

            if supply.isOnOrder {
                VStack(alignment: .trailing, spacing: 2) {
                    Label("On Order", systemImage: "shippingbox.fill")
                        .font(.caption.weight(.medium))
                    Text("\(supply.orderedQuantity) \(supply.unit)")
                        .font(.caption2)
                    if let orderDate = supply.orderDate {
                        Text(orderDate, style: .date)
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.blue.opacity(0.15))
                )
                .foregroundStyle(.blue)
            } else if supply.needsReorder {
                Label("Reorder", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(AppColors.warning.opacity(0.15)))
                    .foregroundStyle(AppColors.warning)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(supply.status.color.opacity(0.08))
        )
    }

    // MARK: - Current Stock Card

    private var currentStockCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Stock")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("\(supply.currentQuantity)")
                        .font(AppTheme.ScaledFont.titleXLarge)
                        .foregroundStyle(supply.status.color)
                    Text(supply.unit)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    HStack {
                        Text("Min:")
                            .foregroundStyle(.secondary)
                        Text("\(supply.minimumThreshold)")
                    }
                    .font(.subheadline)

                    HStack {
                        Text("Reorder:")
                            .foregroundStyle(.secondary)
                        Text("\(supply.reorderAmount)")
                    }
                    .font(.subheadline)
                }
            }

            // Progress bar showing stock level
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(supply.status.color)
                        .frame(width: stockPercentage * geometry.size.width)
                }
            }
            .frame(height: 8)
        }
        .padding()
        .cardStyle()
    }

    private var stockPercentage: CGFloat {
        guard supply.minimumThreshold > 0 else { return 1.0 }
        let ratio = CGFloat(supply.currentQuantity) / CGFloat(supply.minimumThreshold * 2)
        return min(1.0, max(0, ratio))
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)

            VStack(spacing: 12) {
                detailRow(label: "Name", value: supply.name)
                detailRow(label: "Category", value: supply.category.rawValue)
                detailRow(label: "Location", value: supply.location.isEmpty ? "Not set" : supply.location)
                detailRow(label: "Unit", value: supply.unit)
                detailRow(label: "Minimum Threshold", value: "\(supply.minimumThreshold)")
                detailRow(label: "Reorder Amount", value: "\(supply.reorderAmount)")

                if !supply.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(supply.notes)
                            .font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }
            .padding()
            .cardStyle()
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    // MARK: - Editable Details Section

    private var editableDetailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Supply name", text: $editName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Category")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Category", selection: $editCategory) {
                        ForEach(SupplyCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.icon)
                                .tag(category)
                        }
                    }
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Storage location", text: $editLocation)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Unit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("e.g., boxes, packs, items", text: $editUnit)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Minimum Threshold")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("0", value: $editMinimumThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reorder Amount")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("0", value: $editReorderAmount, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editNotes)
                        .frame(minHeight: 80)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.08))
                        )
                }
            }
            .padding()
            .cardStyle()
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History")
                .font(.headline)

            if transactions.isEmpty {
                Text("No transactions recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(transactions) { transaction in
                        transactionRow(transaction)

                        if transaction.id != transactions.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .cardStyle(padding: 0)
            }
        }
    }

    private func transactionRow(_ transaction: SupplyTransaction) -> some View {
        HStack(spacing: 12) {
            // Change indicator
            ZStack {
                Circle()
                    .fill(transaction.quantityChange >= 0 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: transaction.quantityChange >= 0 ? "plus" : "minus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(transaction.quantityChange >= 0 ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.reason)
                    .font(.subheadline)

                Text(transaction.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.quantityChange >= 0 ? "+\(transaction.quantityChange)" : "\(transaction.quantityChange)")
                .font(.headline)
                .foregroundStyle(transaction.quantityChange >= 0 ? .green : .red)
        }
        .padding()
    }

    // MARK: - Actions

    private func startEditing() {
        editName = supply.name
        editCategory = supply.category
        editLocation = supply.location
        editMinimumThreshold = supply.minimumThreshold
        editReorderAmount = supply.reorderAmount
        editUnit = supply.unit
        editNotes = supply.notes
        isEditing = true
    }

    private func saveChanges() {
        supply.name = editName
        supply.category = editCategory
        supply.location = editLocation
        supply.minimumThreshold = editMinimumThreshold
        supply.reorderAmount = editReorderAmount
        supply.unit = editUnit
        supply.notes = editNotes
        supply.modifiedAt = Date()
        modelContext.safeSave()
    }

}

// MARK: - Mark as Ordered Sheet

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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark as Received") {
                        SupplyService.markAsReceived(supply, receivedQuantity: receivedQuantity, in: modelContext)
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

#Preview {
    let supply = Supply(
        name: "Crayons (24-pack)",
        category: .art,
        location: "Cabinet A",
        currentQuantity: 12,
        minimumThreshold: 5,
        reorderAmount: 20,
        unit: "boxes",
        notes: "Preferred brand: Crayola. Order from Amazon."
    )

    return SupplyDetailView(supply: supply)
        .previewEnvironment()
}
