import SwiftUI

/// The meeting pane before a child is chosen, beside the queue on a wide
/// screen. (A phone shows the queue alone and pushes a meeting over it.)
struct MeetingsEmptyState: View {
    /// Someone is waiting, so the first meeting can start from here.
    let canStart: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)

            Text("Select a Student")
                .font(.title2.weight(.medium))

            Text("Choose a student from the queue to start their weekly meeting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if canStart {
                Button(action: onStart) {
                    Label("Start First Meeting", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
