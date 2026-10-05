import SwiftUI

/// Leaving Early… on the grid: the pickup-time sheet for the child whose
/// tile asked, holding remote reloads while it's open as the note sheet does.
/// The time goes on the day the sheet opened on, even if the grid moves on
/// meanwhile (a tapped reminder, the morning coming round).
struct AssistantPickupSheet: ViewModifier {
    @Binding var row: AssistantAttendanceViewModel.Row?
    let viewModel: AssistantAttendanceViewModel?
    /// The day on screen when the sheet opened.
    @State private var day: Date?

    func body(content: Content) -> some View {
        content
            .sheet(item: $row) { row in
                if let viewModel {
                    let day = day ?? viewModel.date
                    AttendancePickupSheet(
                        studentName: row.shortName,
                        day: day,
                        current: row.leavesAt,
                        suggested: AttendanceRules.suggestedPickup(for: row, on: day),
                        sharedWith: "Your guide and the other assistants see this on the tile too. "
                            + "Mark Left Early when they go.",
                        onSave: { viewModel.setPickup($0, for: row, on: day) }
                    )
                }
            }
            .onChange(of: row?.id) { _, editing in
                day = editing == nil ? nil : viewModel?.date
                viewModel?.pauseRemoteReloads(editing != nil)
            }
    }
}
