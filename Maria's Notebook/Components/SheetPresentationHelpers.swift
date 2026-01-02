import SwiftUI

/// Helper utilities for consistent sheet presentation patterns across the app.
/// Reduces boilerplate and ensures consistent behavior.
extension View {
    /// Presents a sheet when an optional item is set, clearing it when dismissed.
    /// - Parameters:
    ///   - item: Optional item that triggers sheet presentation
    ///   - onDismiss: Optional callback when sheet is dismissed
    ///   - content: Sheet content builder
    /// - Returns: A view with sheet presentation applied
    func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        self.sheet(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            onDismiss: onDismiss
        ) {
            if let item = item.wrappedValue {
                content(item)
            }
        }
    }
    
    /// Presents a sheet for an optional UUID, useful for detail views.
    /// - Parameters:
    ///   - id: Optional UUID that triggers sheet presentation
    ///   - onDismiss: Optional callback when sheet is dismissed
    ///   - content: Sheet content builder
    /// - Returns: A view with sheet presentation applied
    func sheet<Content: View>(
        id: Binding<UUID?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (UUID) -> Content
    ) -> some View {
        self.sheet(
            isPresented: Binding(
                get: { id.wrappedValue != nil },
                set: { if !$0 { id.wrappedValue = nil } }
            ),
            onDismiss: onDismiss
        ) {
            if let id = id.wrappedValue {
                content(id)
            }
        }
    }
}


