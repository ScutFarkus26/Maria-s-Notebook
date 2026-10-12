// QuickNoteGlassButton+Placement.swift
// Where the floating quick-capture button may sit: its size and resting
// insets, and the limit that keeps a dragged-away button inside the window.

import SwiftUI

extension QuickNoteGlassButton {
    static let buttonSize: CGFloat = 56
    static let trailingInset: CGFloat = AppTheme.Spacing.large
    #if os(iOS)
    // 32 + 16 = 48pt base, plus 37pt for safe area
    static let bottomInset: CGFloat = AppTheme.Spacing.xlarge + AppTheme.Spacing.medium
    #else
    static let bottomInset: CGFloat = AppTheme.Spacing.medium + AppTheme.Spacing.small // 16 + 8 = 24pt base
    #endif
    /// How much of the window's edge the button keeps clear of.
    static let edgeMargin: CGFloat = 8

    /// `offset` limited so the button, resting `trailingInset` from the
    /// container's trailing edge and `bottomInset` from its bottom, stays
    /// wholly inside the container with a small margin. An offset already
    /// inside comes back unchanged; a container too small to move in gives zero.
    static func clampedOffset(
        _ offset: CGSize, in container: CGSize, buttonSize: CGFloat, trailingInset: CGFloat, bottomInset: CGFloat
    ) -> CGSize {
        func clamp(_ value: CGFloat, length: CGFloat, inset: CGFloat) -> CGFloat {
            let lowest = -(length - inset - buttonSize - edgeMargin)
            let highest = max(inset - edgeMargin, 0)
            guard lowest <= highest else { return 0 }
            return min(max(value, lowest), highest)
        }
        return CGSize(
            width: clamp(offset.width, length: container.width, inset: trailingInset),
            height: clamp(offset.height, length: container.height, inset: bottomInset)
        )
    }
}
