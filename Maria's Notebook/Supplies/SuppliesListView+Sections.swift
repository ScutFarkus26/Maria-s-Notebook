// SuppliesListView+Sections.swift
// Extracted sections to keep SuppliesListView type body within SwiftLint limits.

import SwiftUI
import CoreData

extension SuppliesListView {
    // MARK: - Stats Section

    var statsSection: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Total Supplies",
                value: "\(supplies.count)",
                subtitle: nil,
                systemImage: "shippingbox.fill"
            )

            StatCard(
                title: "Out of Stock",
                value: "\(supplies.filter { $0.currentQuantity <= 0 }.count)",
                subtitle: nil,
                systemImage: "xmark.circle.fill"
            )
        }
    }

    // MARK: - Search Bar

    var searchBar: some View {
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
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
        )
    }

    // MARK: - Grouped Supplies View

    var groupedSuppliesView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(groupedSupplies, id: \.category) { group in
                VStack(alignment: .leading, spacing: 12) {
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

    func suppliesList(_ items: [CDSupply]) -> some View {
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
                        SupplyService.deleteSupply(supply, in: viewContext)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    var emptyState: some View {
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

    var noResultsState: some View {
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

    func handleQuickAdjust(supply: CDSupply, adjustment: Int) {
        if adjustment > 0 {
            SupplyService.addStock(to: supply, amount: adjustment, in: viewContext)
        } else {
            SupplyService.removeStock(from: supply, amount: abs(adjustment), in: viewContext)
        }
    }
}
