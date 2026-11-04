import SwiftUI

/// Reloads the attendance screen's day each time the app comes back to the
/// foreground, and moves it to today once the calendar day has turned
/// (`AssistantAttendanceViewModel.reloadAfterAway`).
///
/// A modifier of its own so that the scene phase is read here rather than by
/// the attendance screen. The phase changes four times on every trip away and
/// back (active, inactive, background, inactive, active), and read in the
/// screen's body each change redrew the whole grid: 88 of the 110 tile draws a
/// trip cost on 2026-09-29 (22 tiles). Read here, a change redraws only this
/// modifier.
///
/// A return from a moment inactive that never reached the background
/// (Control Center, a system alert) loads only when something came in
/// meanwhile (`AssistantAttendanceViewModel.returnedToApp`).
struct AssistantReloadOnReturn: ViewModifier {
    let viewModel: AssistantAttendanceViewModel?
    /// Runs on every change to a phase other than active.
    var onLeaveActive: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    /// The app reached the background since it was last active.
    @State private var reachedBackground = false

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            if phase != .active { onLeaveActive() }
            guard phase == .active else {
                if phase == .background { reachedBackground = true }
                // Imports don't reload the day while the app is away: the
                // return's load shows them.
                viewModel?.followScene(isActive: false)
                return
            }
            let fromBackground = reachedBackground
            reachedBackground = false
            // After a night away, today, whatever day was left on screen
            // (bug hunt 2026-10-20, #1); within the day, the day she left.
            // The day she was last here is the view model's, not this
            // modifier's: the screen's own `.task` checks it too.
            viewModel?.returnedToApp(fromBackground: fromBackground)
        }
    }
}
