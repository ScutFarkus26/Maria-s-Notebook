import SwiftUI

/// Compact mode content for WorkCard
/// Displays: work type icon, title, participant chips with completion toggles
/// Used in LinkedWorkSection for showing related work items
struct WorkCardCompactContent: View {
    let config: WorkCard.CompactModeConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: config.workType.icon)
                    .foregroundStyle(config.workType.color)
                Text(config.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)
                Spacer()
            }

            FlowLayout(spacing: 8) {
                ForEach(config.participants) { participant in
                    Button {
                        config.onToggle(config.work, participant.studentID)
                    } label: {
                        StudentChip(
                            participant.name,
                            tint: config.workType.color,
                            leadingSystemImage: participant.isCompleted ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.whisper))
        )
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct WorkCardCompactPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext
        let work = CDWorkModel(context: ctx)
        work.status = .active; work.studentID = UUID().uuidString; work.lessonID = UUID().uuidString

        return WorkCard.compact(
            work: work,
            title: "Practice Division",
            workType: .practice,
            participants: [
                WorkCardParticipant(id: UUID(), studentID: UUID(), name: "Ada L.", isCompleted: true),
                WorkCardParticipant(id: UUID(), studentID: UUID(), name: "Grace H.", isCompleted: false),
                WorkCardParticipant(id: UUID(), studentID: UUID(), name: "Marie C.", isCompleted: false)
            ],
            onToggle: { _, _ in }
        )
        .padding()
        .previewEnvironment(using: stack)
    }
}

#Preview {
    WorkCardCompactPreview()
}
