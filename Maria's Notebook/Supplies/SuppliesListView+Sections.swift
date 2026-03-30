// SuppliesListView+Sections.swift
// Extracted sections to keep SuppliesListView type body within SwiftLint limits.

import SwiftUI
import SwiftData

extension SuppliesListView {
    // MARK: - Stats Section

    var statsSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
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

            StatCard(
                title: "On Order",
                value: "\(stats.onOrder)",
                subtitle: stats.onOrder > 0 ? "Awaiting delivery" : nil,
                systemImage: "shippingbox.and.arrow.backward.fill"
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

    func suppliesList(_ items: [Supply]) -> some View {
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

                    if supply.isOnOrder {
                        Button {
                            receiveSupply = supply
                        } label: {
                            Label("Mark as Received", systemImage: "checkmark.circle")
                        }
                    } else {
                        Button {
                            orderSupply = supply
                        } label: {
                            Label("Mark as Ordered", systemImage: "shippingbox")
                        }
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

    func handleQuickAdjust(supply: Supply, adjustment: Int) {
        let reason = adjustment > 0 ? "Quick add" : "Quick remove"
        if adjustment > 0 {
            SupplyService.addStock(to: supply, amount: adjustment, reason: reason, in: modelContext)
        } else {
            SupplyService.removeStock(from: supply, amount: abs(adjustment), reason: reason, in: modelContext)
        }
    }
}
