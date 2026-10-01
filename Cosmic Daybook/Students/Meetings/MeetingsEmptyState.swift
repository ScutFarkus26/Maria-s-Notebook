import SwiftUI

/// The meeting pane before a child is chosen, beside the queue on a wide
/// screen. (A phone shows the queue alone and pushes a meeting over it.)
struct MeetingsEmptyState: View {
    /// The first child in Up Next, or nil when nobody is waiting.
    let firstName: String?
    /// Children still to meet this cycle (absent ones included).
    let remaining: Int
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: remaining == 0 ? "checkmark.circle" : "person.2.circle")
                .font(.system(size: 64))
                .foregroundStyle(remaining == 0 ? AnyShapeStyle(AppColors.success) : AnyShapeStyle(.tertiary))

            Text(remaining == 0 ? "Everyone Has Met" : "\(remaining) to Meet This Cycle")
                .font(.title2.weight(.medium))

            Text(remaining == 0
                 ? "Every child has had a meeting this cycle."
                 : "Choose a child from the queue, or start with the one who has waited longest.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if let firstName {
                Button(action: onStart) {
                    Label("Start with \(firstName)", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
