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

// MARK: - Tracking View Modifiers (#12-14)
extension View {
    /// Apply display-level tight tracking for large titles
    func displayTracking() -> some View {
        self.tracking(AppTheme.Tracking.display)
    }

    /// Apply overline styling: uppercase section label with wide tracking (#12)
    func overlineStyle() -> some View {
        self
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .tracking(AppTheme.Tracking.overline)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    /// Apply badge tracking for small text in pills (#14)
    func badgeTracking() -> some View {
        self.tracking(AppTheme.Tracking.badge)
    }
}

// MARK: - Structural Hierarchy Helpers (#18-19)

/// A consistent page-level weight ladder (#18):
/// page title (.heavy 32pt) → section header (.bold 20pt) → item title (.semibold 16-18pt)
/// → body (.regular 14pt) → metadata (.light 13pt)
///
/// These are convenience wrappers that enforce the ladder consistently.
extension View {
    /// Page-level title — heaviest weight, largest size
    func pageTitleStyle() -> some View {
        self
            .font(AppTheme.ScaledFont.titleXLarge)
            .tracking(AppTheme.Tracking.display)
    }

    /// Major section header — bold weight, clear section boundary
    func majorSectionHeaderStyle() -> some View {
        self
            .font(AppTheme.ScaledFont.titleMedium)
    }

    /// List row primary text — semibold weight for scannability (#19)
    func rowTitleStyle() -> some View {
        self
            .font(AppTheme.ScaledFont.calloutSemibold)
            .foregroundStyle(.primary)
    }

    /// List row secondary text — light weight for clear hierarchy (#19)
    func rowSubtitleStyle() -> some View {
        self
            .font(AppTheme.ScaledFont.caption)
            .foregroundStyle(.secondary)
    }

    /// Metadata text — lightest weight, smallest size
    func metadataStyle() -> some View {
        self
            .font(AppTheme.SemanticFont.metadata)
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Data-Dense View Helpers (#21, #23)
extension View {
    /// Highlighted data series in charts — semibold for focus effect (#21)
    func chartHighlightStyle() -> some View {
        self
            .font(AppTheme.SemanticFont.chartLabel)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }

    /// Non-highlighted data series — light weight for visual recession (#21)
    func chartDimmedStyle() -> some View {
        self
            .font(AppTheme.SemanticFont.chartLabel)
            .fontWeight(.light)
            .foregroundStyle(.secondary)
    }

    /// Dense grid cell style — medium weight for legibility at small sizes (#23)
    func denseGridStyle() -> some View {
        self
            .font(AppTheme.SemanticFont.denseGridCell)
            .foregroundStyle(.primary)
    }

    /// Tabular number style for vertically-aligned numeric columns (#22)
    func tabularNumberStyle() -> some View {
        self
            .font(AppTheme.SemanticFont.tabularNumber)
            .foregroundStyle(.primary)
    }
}

// MARK: - Color-Weight Combination Modifiers (#15-17)
extension View {
    /// Use weight instead of color for primary/secondary distinction (#15).
    /// Label: regular weight, primary color. Value: semibold weight, primary color.
    /// Reserves color differences for meaning (status, subject, alert level).
    func formLabelStyle() -> some View {
        self
            .font(AppTheme.SemanticFont.label)
            .foregroundStyle(.primary)
    }

    /// Form value style — semibold weight at primary color (#15)
    func formValueStyle() -> some View {
        self
            .font(AppTheme.SemanticFont.value)
            .foregroundStyle(.primary)
    }

    /// Muted-but-heavy style for inactive/disabled states (#16).
    /// Maintains structural hierarchy while appearing visually receded.
    func mutedHeavyStyle() -> some View {
        self
            .font(AppTheme.ScaledFont.bodySemibold)
            .foregroundStyle(.primary.opacity(0.45))
    }

    /// Light weight at full opacity for elegant de-emphasis (#17).
    /// Preserves contrast for accessibility while creating visual hierarchy.
    func deemphasizedStyle() -> some View {
        self
            .font(AppTheme.ScaledFont.bodyLight)
            .foregroundStyle(.primary)
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

extension View {
    /// Sets the font hierarchy level for this view and its children (#25).
    /// Child text that reads the hierarchy level can automatically shift
    /// weights downward to prevent competing visual weight in nested layouts.
    func fontHierarchy(_ level: FontHierarchyLevel) -> some View {
        self.environment(\.fontHierarchyLevel, level)
    }
}

extension Font.Weight {
    /// Shift weight down by the given number of steps.
    /// heavy → bold → semibold → medium → regular → light → thin → ultraLight
    func shifted(by steps: Int) -> Font.Weight {
        let ladder: [Font.Weight] = [
            .heavy, .bold, .semibold, .medium, .regular, .light, .thin, .ultraLight
        ]
        guard let index = ladder.firstIndex(of: self) else { return self }
        let newIndex = min(index + steps, ladder.count - 1)
        return ladder[newIndex]
    }
}

// MARK: - iOS 26 Liquid Glass Preparation
// When targeting iOS 26+, consider replacing CardBackgroundModifier and SubtleCardModifier
// backgrounds with the new .glassEffect() modifier for Apple's Liquid Glass design language.
// The ScaledFont system, opacity constants, and shadow styles are already well-structured
// for a smooth transition to the new visual language.
