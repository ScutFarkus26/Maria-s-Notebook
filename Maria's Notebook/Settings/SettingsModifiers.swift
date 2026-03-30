// SettingsModifiers.swift
// ViewModifiers and View extensions for search highlighting and breadcrumb navigation in Settings.

import SwiftUI

// MARK: - Search Highlight Modifier

/// Highlights a setting label when it matches the current search text
struct SearchHighlightModifier: ViewModifier {
    let searchText: String
    let label: String

    private var isMatch: Bool {
        !searchText.isEmpty && label.lowercased().contains(searchText.lowercased())
    }

    func body(content: Content) -> some View {
        content
            .background(
                isMatch
                    ? RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(AppColors.info.opacity(UIConstants.OpacityConstants.accent))
                        .padding(-4)
                    : nil
            )
    }
}

extension View {
    func settingsHighlight(searchText: String, label: String) -> some View {
        modifier(SearchHighlightModifier(searchText: searchText, label: label))
    }
}

// MARK: - Breadcrumb Modifier

/// Adds a breadcrumb subtitle to the toolbar on compact layouts
struct BreadcrumbModifier: ViewModifier {
    let path: String

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            #endif
    }
}

extension View {
    func settingsBreadcrumb(_ path: String) -> some View {
        modifier(BreadcrumbModifier(path: path))
    }
}
