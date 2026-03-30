// HoverableRow.swift
// Reusable ViewModifier for macOS hover states on row components.

import SwiftUI

/// ViewModifier that adds hover state feedback on macOS.
/// On iOS, this is a no-op.
private struct HoverableRowModifier: ViewModifier {
    @State private var isHovered = false
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? Color.primary.opacity(UIConstants.OpacityConstants.trace) : Color.clear)
            )
            .onHover { hovering in
                _ = adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
        #else
        content
        #endif
    }
}

extension View {
    /// Applies subtle hover feedback on macOS. No effect on iOS.
    /// - Parameter cornerRadius: The corner radius for the hover background (default: 8)
    /// - Returns: A view with hover feedback applied
    func hoverableRow(cornerRadius: CGFloat = 8) -> some View {
        modifier(HoverableRowModifier(cornerRadius: cornerRadius))
    }
}
