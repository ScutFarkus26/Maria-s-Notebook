// Theme+ViewModifiers.swift
// View extension modifiers extracted from Theme.swift to keep file length manageable.

import SwiftUI

// MARK: - Font Extension for Easy Migration
extension Font {
    /// Creates a rounded font that scales with Dynamic Type
    /// Use this for migrating from fixed-size fonts to scaled fonts
    static func scaledRounded(_ textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(textStyle, design: .rounded, weight: weight)
    }
}

// MARK: - View Extension for Shadow Styles
extension View {
    /// Apply a standardized shadow style
    func shadow(_ style: AppTheme.ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

// MARK: - Font Hierarchy Context Modifier (#25)

/// Hierarchy levels that shift font weights downward for nested contexts.
/// When a card is inside a section inside a page, its internal titles
/// don't need the same weight as standalone titles.
enum FontHierarchyLevel: Int, Sendable {
    case primary = 0    // Default — full weight
    case secondary = 1  // One rung down (bold → semibold, semibold → medium, etc.)
    case tertiary = 2   // Two rungs down
}

private struct FontHierarchyLevelKey: EnvironmentKey {
    static let defaultValue: FontHierarchyLevel = .primary
}

extension EnvironmentValues {
    var fontHierarchyLevel: FontHierarchyLevel {
        get { self[FontHierarchyLevelKey.self] }
        set { self[FontHierarchyLevelKey.self] = newValue }
    }
}

// MARK: - iOS 26 Liquid Glass Preparation
// When targeting iOS 26+, consider replacing CardBackgroundModifier and SubtleCardModifier
// backgrounds with the new .glassEffect() modifier for Apple's Liquid Glass design language.
// The ScaledFont system, opacity constants, and shadow styles are already well-structured
// for a smooth transition to the new visual language.
