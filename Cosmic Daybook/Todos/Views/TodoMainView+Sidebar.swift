// TodoMainView+Sidebar.swift
// Sidebar navigation for the todo list

import SwiftUI
import CoreData

extension TodoMainView {
    // MARK: - Sidebar View

    /// Check-ins, the Tide lists, "Not yet in Tide" while it holds anything,
    /// and Done (simplify round two, 2026-11-03: tags, Someday and the date
    /// lists went with the rest of the notebook's own to-do list).
    var sidebar: some View {
        List {
            Section {
                filterRow(filter: .checkIns)
            }

            tideListsSection

            Section {
                if countForFilter(.notInTide) > 0 {
                    filterRow(filter: .notInTide)
                }
                filterRow(filter: .done)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Filter Row Helper

    @ViewBuilder
    private func filterRow(filter: TodoListFilter) -> some View {
        let isActive = selectedTideList == nil && selectedFilter == filter
        Button {
            clearSidebarSelection()
            selectedFilter = filter
            showSelectedListIfCompact()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: filter.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(filter.color)
                    .frame(width: 28, height: 28)
                    .background(
                        filter.color.opacity(UIConstants.OpacityConstants.accent),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                Text(filter.title)
                    .font(AppTheme.ScaledFont.body)
                    .fontWeight(isActive ? .semibold : .regular)

                Spacer()

                let count = countForFilter(filter)
                if count > 0, filter != .done {
                    Text("\(count)")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isActive
                ? Color.accentColor.opacity(UIConstants.OpacityConstants.light)
                : Color.clear
        )
    }
}
