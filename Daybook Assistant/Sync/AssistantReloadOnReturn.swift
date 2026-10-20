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
struct AssistantReloadOnReturn: ViewModifier {
    let viewModel: AssistantAttendanceViewModel?
    /// Runs on every change to a phase other than active.
    var onLeaveActive: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            if phase != .active { onLeaveActive() }
            guard let viewModel else { return }
            // Imports don't reload the day while the app is away: the load
            // below shows them.
            viewModel.followScene(isActive: phase == .active)
            // After a night away, today, whatever day was left on screen
            // (bug hunt 2026-10-20, #1); within the day, the day she left.
            // The day she was last here is the view model's, not this
            // modifier's: the screen's own `.task` checks it too.
            if phase == .active { viewModel.reloadAfterAway() }
        }
    }
}
