// TodoMainView+TideLists.swift
// The sidebar's "From Tide" section: the to-dos shared with Tide, by Tide list.

import SwiftUI

extension TodoMainView {
    /// The Tide lists that hold a to-do here, by name.
    var tideListFiles: [String] {
        cachedTideListCounts.keys.sorted {
            TideActionLink.listName(ofFile: $0).localizedCaseInsensitiveCompare(TideActionLink.listName(ofFile: $1))
                == .orderedAscending
        }
    }

    /// One row per Tide list, shown once any to-do is shared with Tide.
    @ViewBuilder var tideListsSection: some View {
        if !cachedTideListCounts.isEmpty {
            Section("From Tide") {
                ForEach(tideListFiles, id: \.self) { file in
                    tideListRow(file)
                }
            }
        }
    }

    /// Clears every sidebar selection, before one is picked.
    func clearSidebarSelection() {
        selectedFilter = nil
        selectedTag = nil
        selectedFolder = nil
        selectedTideList = nil
    }

    private func tideListRow(_ file: String) -> some View {
        let isActive = selectedTideList == file
        return Button {
            clearSidebarSelection()
            selectedTideList = file
            showSelectedListIfCompact()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "water.waves")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 28, height: 28)
                    .background(
                        Color.teal.opacity(UIConstants.OpacityConstants.accent),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                Text(TideActionLink.listName(ofFile: file))
                    .font(AppTheme.ScaledFont.body)
                    .fontWeight(isActive ? .semibold : .regular)
                Spacer()
                let count = cachedTideListCounts[file] ?? 0
                if count > 0 {
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
        .listRowBackground(isActive ? Color.accentColor.opacity(UIConstants.OpacityConstants.light) : Color.clear)
    }
}
