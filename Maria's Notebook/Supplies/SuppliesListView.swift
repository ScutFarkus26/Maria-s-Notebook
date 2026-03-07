// swiftlint:disable file_length
import SwiftUI
import SwiftData

/// Main view for managing classroom supplies
struct SuppliesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Supply.name) private var supplies: [Supply]

    @State private var searchText = ""
    @State private var selectedCategory: SupplyCategory?
    @State private var showingAddSheet = false
    @State private var selectedSupply: Supply?
    @State private var showingQuickAdjustSheet = false
    @State private var quickAdjustSupply: Supply?

    private var stats: SupplyStats {
        SupplyService.getSupplyStats(in: modelContext)
    }

    private var filteredSupplies: [Supply] {
        SupplyService.fetchSupplies(
            in: modelContext,
            category: selectedCategory,
            searchText: searchText
        )
    }

    private var groupedSupplies: [(category: SupplyCategory, supplies: [Supply])] {
        SupplyService.fetchSuppliesGroupedByCategory(
            in: modelContext,
            searchText: searchText
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ViewHeader(title: "Supplies") {
                HStack(spacing: 12) {
                    // Category filter
                    Menu {
                        Button("All Categories") {
                            selectedCategory = nil
                        }
                        Divider()
                        ForEach(SupplyCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.icon)
                            }
                        }
                    } label: {
                        Label(
                            selectedCategory?.rawValue ?? "All",
                            systemImage: selectedCategory?.icon ?? "square.grid.2x2"
                        )
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Add button
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Supply", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Stats cards
                    statsSection

                    // Search bar
                    searchBar

                    // Supplies list
                    if supplies.isEmpty {
                        emptyState
                    } else if filteredSupplies.isEmpty {
                        noResultsState
                    } else if selectedCategory != nil {
                        // Single category view
                        suppliesList(filteredSupplies)
                    } else {
                        // Grouped by category
                        groupedSuppliesView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddSupplySheet()
        }
        .sheet(item: $selectedSupply) { supply in
            SupplyDetailView(supply: supply)
        }
        .sheet(item: $quickAdjustSupply) { supply in
            QuickAdjustSheet(supply: supply)
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCard(
                title: "Total Supplies",
                value: "\(stats.totalSupplies)",
                subtitle: nil,
                systemImage: "shippingbox.fill"
            )

            StatCard(
                title: "Low Stock",
                value: "\(stats.lowStock)",
                subtitle: stats.lowStock > 0 ? "Needs attention" : nil,
                systemImage: "exclamationmark.triangle.fill"
            )

            StatCard(
                title: "Out of Stock",
                value: "\(stats.outOfStock)",
                subtitle: stats.outOfStock > 0 ? "Order now" : nil,
                systemImage: "xmark.circle.fill"
            )

            StatCard(
                title: "Needs Reorder",
                value: "\(stats.needsReorder)",
                subtitle: nil,
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search supplies...", text: $searchText)
                .textFieldStyle(.plain)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }

    // MARK: - Grouped Supplies View

    private var groupedSuppliesView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groupedSupplies, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
                    // Category header
                    HStack(spacing: 10) {
                        Image(systemName: group.category.icon)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text(group.category.rawValue)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(group.supplies.count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    suppliesList(group.supplies)
                }
            }
        }
    }

    // MARK: - Supplies List

    private func suppliesList(_ items: [Supply]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { supply in
                SupplyRow(supply: supply) { adjustment in
                    handleQuickAdjust(supply: supply, adjustment: adjustment)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedSupply = supply
                }
                .contextMenu {
                    Button {
                        selectedSupply = supply
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    Button {
                        quickAdjustSupply = supply
                    } label: {
                        Label("Adjust Stock", systemImage: "plus.forwardslash.minus")
                    }

                    Divider()

                    Button(role: .destructive) {
                        SupplyService.deleteSupply(supply, in: modelContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Supplies Yet")
                .font(.title2.weight(.semibold))

            Text("Add supplies to track your classroom inventory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showingAddSheet = true
            } label: {
                Label("Add First Supply", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            Text("No supplies found")
                .font(.headline)

            Text("Try adjusting your search or filter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Actions

    private func handleQuickAdjust(supply: Supply, adjustment: Int) {
        let reason = adjustment > 0 ? "Quick add" : "Quick remove"
        if adjustment > 0 {
            SupplyService.addStock(to: supply, amount: adjustment, reason: reason, in: modelContext)
        } else {
            SupplyService.removeStock(from: supply, amount: abs(adjustment), reason: reason, in: modelContext)
        }
    }
}

// MARK: - Quick Adjust Sheet

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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

#Preview {
    SuppliesListView()
        .previewEnvironment()
}
