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

// MARK: - Search Anchor

extension View {
    /// Marks a card as a place search can scroll to, and outlines it briefly
    /// when a search lands on it. `SettingsGroup(_:)` does this itself; a pane
    /// with its own layout calls it with its `SettingsCopy.Group`.
    @ViewBuilder
    func settingsAnchor(_ anchorID: String?) -> some View {
        if let anchorID {
            modifier(SettingsAnchorModifier(anchorID: anchorID))
        } else {
            self
        }
    }

    func settingsAnchor(_ group: SettingsCopy.Group) -> some View {
        settingsAnchor(group.anchorID)
    }
}

/// The scroll target, plus the accent outline `SettingsPaneScrollView` fades
/// out after a search jump.
private struct SettingsAnchorModifier: ViewModifier {
    let anchorID: String
    @Environment(\.settingsHighlightedAnchor) private var highlightedAnchor

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .opacity(highlightedAnchor == anchorID ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .id(anchorID)
    }

    private static var radius: CGFloat {
        #if os(macOS)
        UIConstants.CornerRadius.medium
        #else
        SettingsStyle.cornerRadius
        #endif
    }
}
