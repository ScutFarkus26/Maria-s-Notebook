import SwiftUI

// MARK: - View Modifier

/// View modifier to add toast overlay to a view
struct ToastOverlayModifier: ViewModifier {
    @Bindable var toastService: ToastService

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ToastOverlay(toastService: toastService)
                    .padding(.top, 8)
            }
    }
}

extension View {
    /// Add toast overlay support to a view (requires explicit service parameter)
    func toastOverlay(_ service: ToastService) -> some View {
        modifier(ToastOverlayModifier(toastService: service))
    }
}
