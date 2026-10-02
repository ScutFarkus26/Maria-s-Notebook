// StickyLeftScrollTracking.swift
// The one scroll-offset reading a grid's sticky left column needs.

import SwiftUI

/// Watches the scroll view's horizontal offset once and hands it to every
/// `StickyLeftItem` inside through the environment. Each sticky cell used to
/// measure its own slot with `onGeometryChange` and keep the result in its own
/// `@State`; with one reading there is one value per scroll frame, however many
/// rows are realized. Vertical scrolling leaves the value where it is and does no work.
struct StickyLeftScrollTracking: ViewModifier {
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // A sticky cell sits at the content's leading edge, so its slot's minX in
                // the scroll view is -contentOffset.x; the push is max(0, -minX).
                max(0, geometry.contentOffset.x)
            } action: { _, newValue in
                offset = newValue
            }
            .environment(\.stickyLeftOffset, offset)
    }
}

extension View {
    /// Apply to the ScrollView whose content holds `StickyLeftItem`s.
    func stickyLeftScrollTracking() -> some View { modifier(StickyLeftScrollTracking()) }
}
