// CardGridLayout.swift
// Shared grid layout configuration for card-based views

import SwiftUI

/// Provides consistent grid column configuration for card grid views.
/// Uses adaptive layout that adjusts based on device size class.
enum CardGridLayout {
    /// Creates grid columns for card-based layouts.
    /// - Parameter sizeClass: The horizontal size class (compact vs regular)
    /// - Returns: Array of GridItem configured for adaptive card layout
    static func columns(for sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        // iPhone/Compact: Allow smaller cards (approx 160pt wide) to fit 2 columns
        // iPad/Regular: Keep the original 260pt minimum for wider cards
        let minWidth: CGFloat = sizeClass == .compact ? 155 : 260
        let spacing: CGFloat = sizeClass == .compact ? 16 : 24

        return [
            GridItem(.adaptive(minimum: minWidth, maximum: 320), spacing: spacing)
        ]
    }
}
