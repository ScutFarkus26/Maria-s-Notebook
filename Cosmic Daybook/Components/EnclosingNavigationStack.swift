import SwiftUI

/// Pushes a value onto the navigation stack a page was pushed into: the iPhone
/// More tab's stack (`RootMoreTab`). The page registers the value's
/// `navigationDestination` itself, as it would inside its own stack.
struct NavigationPushAction {
    private let push: @MainActor @Sendable (any Hashable) -> Void

    init(_ push: @escaping @MainActor @Sendable (any Hashable) -> Void) {
        self.push = push
    }

    @MainActor func callAsFunction(_ value: some Hashable) {
        push(value)
    }
}

/// A root page's own `NavigationStack`, left out when the page was pushed into
/// another stack: a second stack there draws a second navigation bar, with a
/// second back button, under the first.
struct PageNavigationStack<Content: View>: View {
    @Environment(\.navigationPush) private var enclosingPush
    @ViewBuilder let content: () -> Content

    var body: some View {
        if enclosingPush != nil {
            content()
        } else {
            NavigationStack(root: content)
        }
    }
}
