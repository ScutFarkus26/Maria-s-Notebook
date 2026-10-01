import SwiftUI

/// Leaving Early… on the grid: the pickup-time sheet for the child whose
/// tile asked, holding remote reloads while it's open as the note sheet does.
struct AssistantPickupSheet: ViewModifier {
    @Binding var row: AssistantAttendanceViewModel.Row?
    let viewModel: AssistantAttendanceViewModel?

    func body(content: Content) -> some View {
        content
            .sheet(item: $row) { row in
                if let viewModel {
                    AttendancePickupSheet(
                        studentName: row.shortName,
                        day: viewModel.date,
                        current: row.leavesAt,
                        suggested: AttendanceRules.suggestedPickup(for: row, on: viewModel.date),
                        sharedWith: "Your guide and the other assistants see this on the tile too. "
                            + "Mark Left Early when they go.",
                        onSave: { viewModel.setPickup($0, for: row) }
                    )
                }
            }
            .onChange(of: row?.id) { _, editing in
                viewModel?.pauseRemoteReloads(editing != nil)
            }
    }
}
