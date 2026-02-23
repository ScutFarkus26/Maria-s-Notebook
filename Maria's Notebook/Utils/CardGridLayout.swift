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
        // Narrower cards for taller 3:4 paper-like aspect ratio
        // iPhone/Compact: ~150pt wide for 2 columns
        // iPad/Regular: ~200pt wide for more columns, paper-like proportions
        let minWidth: CGFloat = sizeClass == .compact ? 150 : 200
        let maxWidth: CGFloat = sizeClass == .compact ? 180 : 240
        let spacing: CGFloat = sizeClass == .compact ? 12 : 20

        return [
            GridItem(.adaptive(minimum: minWidth, maximum: maxWidth), spacing: spacing)
        ]
    }
}
