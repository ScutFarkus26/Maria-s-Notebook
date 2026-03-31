import SwiftUI
import CoreData

/// Main view for managing classroom supplies
struct SuppliesListView: View {
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDSupply.name, ascending: true)]) private var supplies: FetchedResults<CDSupply>

    @State var searchText = ""
    @State private var selectedCategory: SupplyCategory?
    @State var showingAddSheet = false
    @State var selectedSupply: CDSupply?
    @State private var showingQuickAdjustSheet = false
    @State var quickAdjustSupply: CDSupply?
    @State var orderSupply: CDSupply?
    @State var receiveSupply: CDSupply?

    var stats: SupplyStats {
        let lowStock = supplies.filter { $0.status == .low || $0.status == .critical }.count
        let outOfStock = supplies.filter { $0.status == .outOfStock }.count
        let needsReorder = supplies.filter(\.needsReorder).count
        let onOrder = supplies.filter(\.isOnOrder).count
        return SupplyStats(
            totalSupplies: supplies.count,
            lowStock: lowStock,
            outOfStock: outOfStock,
            needsReorder: needsReorder,
            onOrder: onOrder
        )
    }

    var filteredSupplies: [CDSupply] {
        var result = Array(supplies)

        if let category = selectedCategory {
            result = result.filter { $0.category == category }
        }

        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(searchLower) ||
                $0.location.lowercased().contains(searchLower) ||
                $0.notes.lowercased().contains(searchLower)
            }
        }

        return result
    }

    var groupedSupplies: [(category: SupplyCategory, supplies: [CDSupply])] {
        let searchFiltered = filteredSupplies
        let grouped = Dictionary(grouping: searchFiltered) { $0.category }
        return SupplyCategory.allCases.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else { return nil }
            return (category: category, supplies: items)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Supplies") {
                HStack(spacing: 12) {
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

                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add CDSupply", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statsSection
                    searchBar

                    if supplies.isEmpty {
                        emptyState
                    } else if filteredSupplies.isEmpty {
                        noResultsState
                    } else if selectedCategory != nil {
                        suppliesList(filteredSupplies)
                    } else {
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
        .sheet(item: $orderSupply) { supply in
            MarkAsOrderedSheet(supply: supply)
        }
        .sheet(item: $receiveSupply) { supply in
            MarkAsReceivedSheet(supply: supply)
        }
    }
}

#Preview {
    SuppliesListView()
        .previewEnvironment()
}
