import SwiftUI

/// Close Arrival while anyone's unmarked; once closed, an amber "Late" with
/// Reopen Arrival in its menu. Nothing ahead of the day, or on a locked day.
///
/// Closing marks everyone still unmarked absent, so it asks first, naming
/// exactly who: the question doubles as a last look at who's missing. It
/// closes arrival on this device only; another device keeps its own phase
/// and sees the marks. With ParentLocker picked it is Close Arrival & Send:
/// the class goes to ParentLocker once the Undo that follows has gone.
struct AttendanceArrivalControl: View {
    let viewModel: AttendanceViewModel
    let isEditing: Bool
    /// ParentLocker is how the day goes: closing sends the class.
    var sendsToParentLocker = false
    let onClose: () -> Void
    let onReopen: () -> Void

    @State private var confirming = false
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        if isEditing, !viewModel.isFuture, viewModel.phase == .late {
            lateMenu
        } else if viewModel.offersCloseArrival(canMark: isEditing) {
            Button(sendsToParentLocker ? "Close Arrival & Send…" : "Close Arrival…") { confirming = true }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .help(sendsToParentLocker
                    ? "Marks everyone not here yet absent, then sends the class to ParentLocker"
                    : "Marks everyone not here yet absent")
                .accessibilityHint("Asks before marking everyone not here yet absent")
                .confirmationDialog(title, isPresented: $confirming, titleVisibility: .visible) {
                    Button(
                        "Mark \(viewModel.unmarkedCount) Absent" + (sendsToParentLocker ? " & Send" : ""),
                        role: .destructive, action: onClose
                    )
                } message: {
                    Text(message)
                }
        }
    }

    private var lateMenu: some View {
        Menu {
            Button("Reopen Arrival", systemImage: "arrow.uturn.backward", action: onReopen)
        } label: {
            Label("Late", systemImage: "clock.fill")
                .font(AppTheme.ScaledFont.captionSemibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.lateAmber.opacity(0.16), in: Capsule())
                .foregroundStyle(Color.lateAmber)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Arrival is closed")
        .accessibilityLabel("Arrival closed: \(markVerb) marks late")
        .accessibilityHint("Opens Reopen Arrival")
    }

    /// "a tap" on the iPhone's tiles, "a click" on the Mac and iPad.
    private var markVerb: String {
        #if os(iOS)
        hSizeClass == .compact ? "a tap" : "a click"
        #else
        "a click"
        #endif
    }

    private var title: String {
        viewModel.unmarkedCount == 1 ? "Mark 1 child absent?" : "Mark \(viewModel.unmarkedCount) children absent?"
    }

    private var message: String {
        let names = viewModel.unmarkedNames.formatted(.list(type: .and))
        let send = sendsToParentLocker ? " Then the class goes to ParentLocker." : ""
        return "\(names). After this, \(markVerb) marks a child late.\(send)"
    }
}
