import SwiftUI

/// Reloads the attendance screen's day each time the app comes back to the
/// foreground.
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

    /// Whether the screen was on today when the app last left the foreground:
    /// only then does coming back move it on to the new today.
    @State private var followsToday = true
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { oldPhase, phase in
            if phase != .active { onLeaveActive() }
            guard let viewModel else { return }
            if phase == .active {
                // Left open overnight on today, the screen moves on to the new
                // today; left on another day, it stays there.
                if followsToday, !viewModel.isToday {
                    viewModel.load(Date())
                } else {
                    viewModel.load()
                }
            } else if oldPhase == .active {
                // Noted on the way out only: coming back passes through
                // .inactive after midnight, when "today" has already moved.
                followsToday = viewModel.isToday
            }
        }
    }
}
