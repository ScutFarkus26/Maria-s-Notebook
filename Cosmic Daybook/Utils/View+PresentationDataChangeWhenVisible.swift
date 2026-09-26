import CoreData
import SwiftUI

/// The Presentations pattern in one modifier: every change signal bumps a
/// counter, on screen or not, and `onChangeWhenVisible` turns the counter
/// into the action only while the screen can be seen. Hidden (a `TabView`
/// keeps visited iPad tabs alive; a covered or minimized Mac window) a change
/// only marks the screen stale, and it catches up once when it is back.
///
/// The counter is this modifier's state, not the screen's, so a change that
/// arrives while the screen is hidden re-runs this modifier's body only.
private struct PresentationDataChangeWhenVisible: ViewModifier {
    let entityNames: Set<String>
    let context: NSManagedObjectContext
    let catchUpOnAppear: Bool
    let action: () -> Void
    @State private var changes = 0

    func body(content: Content) -> some View {
        content
            .onPresentationDataChange(of: entityNames, in: context) { _ in
                changes &+= 1
            }
            .onChangeWhenVisible(of: changes, catchUpOnAppear: catchUpOnAppear, perform: action)
    }
}

extension View {
    /// `onPresentationDataChange(of:in:)` that runs `action` only while the
    /// view is on screen (see `onChangeWhenVisible`). Pass
    /// `catchUpOnAppear: false` when the screen's own `.task` / `.onAppear`
    /// already reloads on return.
    func onPresentationDataChangeWhenVisible(
        of entityNames: Set<String>,
        in context: NSManagedObjectContext,
        catchUpOnAppear: Bool = true,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(PresentationDataChangeWhenVisible(
            entityNames: entityNames, context: context, catchUpOnAppear: catchUpOnAppear, action: action
        ))
    }
}
