import Combine
import SwiftUI

/// Reload work that should only run while a screen is on screen.
///
/// On iPhone and iPad the root is a `TabView`, which keeps every tab the
/// guide has visited alive after she leaves it: its `@State` survives, and so
/// do its `.onReceive` subscriptions and `.onChange` handlers. A screen that
/// reloads on every save or import therefore goes on reloading behind another
/// tab all day. `.task` is the exception — it is cancelled on disappear and
/// runs again on appear.
///
/// These modifiers track visibility with `onAppear` / `onDisappear` and, while
/// the screen is hidden, only remember that a reload was asked for. On the
/// next appearance they run the action once (`catchUpOnAppear`), or leave it
/// to the screen when its own `.task` / `.onAppear` already reloads there.
///
/// On macOS the detail of a `NavigationSplitView` is torn down when the
/// sidebar selection changes, so a hidden screen does not exist to be gated;
/// the modifiers then behave exactly like `onChange` / `onReceive`.
extension View {

    /// `onChange(of:)` that runs `action` only while the view is visible.
    func onChangeWhenVisible<Value: Equatable>(
        of value: Value,
        catchUpOnAppear: Bool = true,
        perform action: @escaping () -> Void
    ) -> some View {
        modifier(ChangeWhenVisible(value: value, catchUpOnAppear: catchUpOnAppear, action: action))
    }

    /// `onReceive(_:)` that runs `action` only while the view is visible.
    func onReceiveWhenVisible<P: Publisher>(
        _ publisher: P,
        catchUpOnAppear: Bool = true,
        perform action: @escaping () -> Void
    ) -> some View where P.Failure == Never {
        modifier(ReceiveWhenVisible(publisher: publisher, catchUpOnAppear: catchUpOnAppear, action: action))
    }
}

private struct ChangeWhenVisible<Value: Equatable>: ViewModifier {
    let value: Value
    let catchUpOnAppear: Bool
    let action: () -> Void
    @State private var gate = WhenVisibleGate()

    func body(content: Content) -> some View {
        content
            .onChange(of: value) { _, _ in
                if gate.request() { action() }
            }
            .modifier(VisibilityTracking(gate: $gate, catchUpOnAppear: catchUpOnAppear, action: action))
    }
}

private struct ReceiveWhenVisible<P: Publisher>: ViewModifier where P.Failure == Never {
    let publisher: P
    let catchUpOnAppear: Bool
    let action: () -> Void
    @State private var gate = WhenVisibleGate()

    func body(content: Content) -> some View {
        content
            .onReceive(publisher) { _ in
                if gate.request() { action() }
            }
            .modifier(VisibilityTracking(gate: $gate, catchUpOnAppear: catchUpOnAppear, action: action))
    }
}

private struct VisibilityTracking: ViewModifier {
    @Binding var gate: WhenVisibleGate
    let catchUpOnAppear: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if gate.appear(catchUp: catchUpOnAppear) { action() }
            }
            .onDisappear {
                gate.disappear()
            }
    }
}

/// The decision itself, kept free of SwiftUI so it can be tested.
struct WhenVisibleGate: Equatable {
    private(set) var isVisible = false
    private(set) var isStale = false

    /// A trigger fired: true when the action should run now; otherwise the
    /// screen is hidden and is only marked stale.
    mutating func request() -> Bool {
        guard isVisible else {
            isStale = true
            return false
        }
        return true
    }

    /// The screen appeared: true when a request arrived while it was hidden
    /// and the caller wants it caught up here.
    mutating func appear(catchUp: Bool) -> Bool {
        isVisible = true
        defer { isStale = false }
        return catchUp && isStale
    }

    mutating func disappear() {
        isVisible = false
    }
}
