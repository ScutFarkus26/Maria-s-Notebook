import SwiftUI
import CoreData

/// Main view for managing classroom supplies
struct SuppliesListView: View {
    @Environment(\.managedObjectContext) var viewContext
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDSupply.name, ascending: true)
    ]) var supplies: FetchedResults<CDSupply>

    @State var searchText = ""
    @State private var selectedCategory: SupplyCategory?
    @State var showingAddSheet = false
    @State var selectedSupply: CDSupply?
    @State private var showingQuickAdjustSheet = false
    @State var quickAdjustSupply: CDSupply?

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
            #if os(iOS)
            ViewHeader(title: "Supplies") {
                HStack(spacing: 12) {
                    categoryMenu
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    addSupplyButton
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Divider()
            #endif

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
        .navigationTitle("Supplies")
        #if os(macOS)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                categoryMenu
                addSupplyButton
            }
        }
        #endif
    }

    private var categoryMenu: some View {
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
                selectedCategory?.rawValue ?? "All Categories",
                systemImage: selectedCategory?.icon ?? "square.grid.2x2"
            )
        }
        .help("Filter supplies by category")
    }

    private var addSupplyButton: some View {
        Button {
            showingAddSheet = true
        } label: {
            Label("Add Supply", systemImage: "plus")
        }
        .help("Add a classroom supply")
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct SuppliesListViewPreview: View {
    var body: some View {
        SuppliesListView()
            .previewEnvironment()
    }
}

#Preview {
    SuppliesListViewPreview()
}
