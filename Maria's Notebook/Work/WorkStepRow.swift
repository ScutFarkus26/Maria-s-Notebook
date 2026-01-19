import SwiftUI
import SwiftData

struct WorkStepRow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var step: WorkStep
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Completion toggle
            Button {
                toggleCompletion()
            } label: {
                Image(systemName: step.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(step.isCompleted ? .green : .secondary)
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)

            // Step number
            Text("\(step.orderIndex + 1).")
                .font(.system(size: AppTheme.FontSize.caption, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

            // Step content
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title.isEmpty ? "Untitled Step" : step.title)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .strikethrough(step.isCompleted)
                    .foregroundStyle(step.isCompleted ? .secondary : .primary)

                if !step.instructions.isEmpty {
                    Text(step.instructions)
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                        .foregroundColor(.secondary)
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
        try? service.toggleCompletion(step)
    }
}
