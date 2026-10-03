import SwiftUI

// MARK: - Sheet(id:) Helper

/// Presents a sheet driven by an optional UUID binding.
/// When the binding becomes non-nil the sheet is presented; dismissing sets it back to nil.
extension View {
    func sheet<Content: View>(
        id binding: Binding<UUID?>,
        @ViewBuilder content: @escaping (UUID) -> Content
    ) -> some View {
        self.sheet(
            item: Binding<IdentifiableUUID?>(
                get: { binding.wrappedValue.map(IdentifiableUUID.init) },
                set: { binding.wrappedValue = $0?.id }
            )
        ) { wrapper in
            content(wrapper.id)
        }
    }
}

/// Lightweight Identifiable wrapper around UUID for use with `.sheet(item:)`.
private struct IdentifiableUUID: Identifiable {
    let id: UUID
}
