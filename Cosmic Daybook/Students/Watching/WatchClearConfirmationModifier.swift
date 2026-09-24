import SwiftUI
import CoreData

extension View {
    /// The confirmation both Watching lists put up before clearing a flag that
    /// other children share. `item` is the row awaiting an answer.
    func watchClearConfirmation(_ item: Binding<WatchItem?>) -> some View {
        modifier(WatchClearConfirmationModifier(item: item))
    }
}

private struct WatchClearConfirmationModifier: ViewModifier {
    @Binding var item: WatchItem?
    @Environment(\.managedObjectContext) private var viewContext

    func body(content: Content) -> some View {
        content.confirmationDialog(
            WatchClearConfirmation.title,
            isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(WatchClearConfirmation.action, role: .destructive) {
                if let pending = item { WatchListActions.clear(pending, in: viewContext) }
                item = nil
            }
        } message: {
            Text(WatchClearConfirmation.message)
        }
    }
}
