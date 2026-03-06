import OSLog
import SwiftUI
import SwiftData

struct WorkStepRow: View {
    private static let logger = Logger.work

    @Environment(\.modelContext) private var modelContext
    @Bindable var step: WorkStep
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button {
                toggleCompletion()
            } label: {
                Image(systemName: step.iconName)
                    .foregroundStyle(step.statusColor)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)

            // Step number
            Text("\(step.orderIndex + 1).")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            // Step content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.title.isEmpty ? "Untitled Step" : step.title)
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .strikethrough(step.isCompleted)
                        .foregroundStyle(step.isCompleted ? .secondary : .primary)

                    // Completion outcome badge
                    if step.isCompleted, let outcome = step.completionOutcome {
                        HStack(spacing: 3) {
                            Image(systemName: outcome.iconName)
                                .font(.system(size: 10))
                            Text(outcome.displayName)
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                        .foregroundStyle(outcome.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(outcome.color.opacity(0.12)))
                    }
                }

                if !step.instructions.isEmpty {
                    Text(step.instructions)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Edit indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }

    private func toggleCompletion() {
        let service = WorkStepService(context: modelContext)
        do {
            try service.toggleCompletion(step)
        } catch {
            Self.logger.warning("Failed to toggle step completion: \(error)")
        }
    }
}
