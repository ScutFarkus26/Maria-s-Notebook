// SettingsModifiers.swift
// ViewModifiers and View extensions for search highlighting and breadcrumb navigation in Settings.

import SwiftUI

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
