// StickyLeftItem.swift
// Reusable sticky left column component for scrollable grids

import SwiftUI

/// A sticky left item that stays fixed when the user scrolls horizontally.
/// Use within a ScrollView that has a coordinateSpace named "gridSpace".
///
/// The push is `max(0, -minX)` of the item's slot in "gridSpace". It used to
/// be read by a GeometryReader around every realized row, which rebuilt the
/// content and its shadow on every scroll frame, vertical ones included. Now
/// only that one number is watched: vertical scrolling leaves it at the same
/// value and does no work, and horizontal scrolling sets it exactly as before.
struct StickyLeftItem<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: () -> Content

    /// How far the content is pushed right to stay at the grid's leading
    /// edge; greater than zero exactly when the slot has scrolled past it.
    @State private var stickOffset: CGFloat = 0

    var body: some View {
        content()
            .frame(width: width, height: height, alignment: .topLeading)
            // An offset, not a position, so the content hit-tests where it draws.
            .offset(x: stickOffset)
            // Add shadow when stuck to separate from content
            .shadow(
                color: stickOffset > 0 ? Color.black.opacity(UIConstants.OpacityConstants.light) : .clear,
                radius: 2, x: 2, y: 0
            )
            // Measured after the offset, so it reads the slot, not the pushed content.
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(0, -proxy.frame(in: .named("gridSpace")).minX)
            } action: { offset in
                stickOffset = offset
            }
            .zIndex(99) // Keep above standard cells
    }
}
