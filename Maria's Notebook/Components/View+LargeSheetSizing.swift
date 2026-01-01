import SwiftUI

/// ViewModifier that conditionally applies presentationSizing for macOS 15.0+
private struct PresentationSizingModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content.presentationSizing(.fitted)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Applies presentation sizing that fits content, with availability check for macOS 15.0+
    func presentationSizingFitted() -> some View {
        self.modifier(PresentationSizingModifier())
    }
    
    @ViewBuilder
    func largeSheetSizing() -> some View {
        #if os(macOS)
        self
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizingFitted()
        #else
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}
