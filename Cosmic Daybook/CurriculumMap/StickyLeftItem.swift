// StickyLeftItem.swift
// Reusable sticky left column component for scrollable grids

import SwiftUI

/// A sticky left item that stays fixed when the user scrolls horizontally.
/// Use within a ScrollView that has `.stickyLeftScrollTracking()` applied, and
/// place it at the leading edge of its row.
///
/// The push is how far the content has scrolled past the grid's leading edge.
/// It used to be measured by every realized row (first a GeometryReader, then
/// `onGeometryChange` into a per-row `@State`); now the scroll view reads it
/// once and every sticky item takes it from the environment. Only the small
/// push modifier depends on it, so a scroll frame doesn't rebuild the content.
struct StickyLeftItem<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: () -> Content

    var body: some View {
        content()
            .frame(width: width, height: height, alignment: .topLeading)
            .modifier(StickyLeftPush())
            .zIndex(99) // Keep above standard cells
    }
}

/// Offsets the item by the shared scroll reading, with a shadow only while stuck.
private struct StickyLeftPush: ViewModifier {
    @Environment(\.stickyLeftOffset) private var stickOffset

    func body(content: Content) -> some View {
        content
            // An offset, not a position, so the content hit-tests where it draws.
            .offset(x: stickOffset)
            // Add shadow when stuck to separate from content
            .shadow(
                color: stickOffset > 0 ? Color.black.opacity(UIConstants.OpacityConstants.light) : .clear,
                radius: 2, x: 2, y: 0
            )
    }
}
