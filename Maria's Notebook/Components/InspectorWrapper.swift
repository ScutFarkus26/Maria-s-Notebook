// InspectorWrapper.swift
// Reusable wrapper for macOS 14+ inspector panels with availability check.

import SwiftUI

#if os(macOS)
/// A wrapper that conditionally adds inspector support on macOS 14+.
/// On earlier versions or iOS, the inspector is not shown.
@available(macOS 14.0, *)
struct InspectorModifier<InspectorContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder let inspectorContent: () -> InspectorContent

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: $isPresented) {
                inspectorContent()
                    .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
            }
    }
}

extension View {
    /// Adds an inspector panel on macOS 14+. No-op on earlier versions.
    /// - Parameters:
    ///   - isPresented: Binding to control inspector visibility
    ///   - content: The content to display in the inspector
    @ViewBuilder
    func inspectorPanel<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        if #available(macOS 14.0, *) {
            self.modifier(InspectorModifier(isPresented: isPresented, inspectorContent: content))
        } else {
            self
        }
    }
}
#endif
