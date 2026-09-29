import SwiftUI

/// A locked day or a failed save, above the attendance grid; nothing
/// otherwise.
struct AssistantDayNotices: View {
    let viewModel: AssistantAttendanceViewModel

    static func shows(for viewModel: AssistantAttendanceViewModel) -> Bool {
        viewModel.isLocked || viewModel.errorMessage != nil
    }

    var body: some View {
        if Self.shows(for: viewModel) {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.isLocked {
                    Label("Your guide has locked this day.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
