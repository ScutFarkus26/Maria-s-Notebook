// StickyLeftItem.swift
// Reusable sticky left column component for scrollable grids

import SwiftUI

/// A sticky left item that stays fixed when the user scrolls horizontally.
/// Use within a ScrollView that has a coordinateSpace named "gridSpace".
struct StickyLeftItem<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let minX = geo.frame(in: .named("gridSpace")).minX
            content()
                .offset(x: max(0, -minX))
                // Add shadow when stuck to separate from content
                .shadow(color: minX < 0 ? Color.black.opacity(UIConstants.OpacityConstants.light) : .clear, radius: 2, x: 2, y: 0)
        }
        .frame(width: width, height: height)
        .zIndex(99) // Keep above standard cells
    }
}
