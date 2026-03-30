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
                    ParticipantChipView(
                        participant: participant,
                        color: config.workType.color,
                        onToggle: { config.onToggle(config.work, participant.studentID) }
                    )
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

/// Participant chip with completion toggle for compact mode
private struct ParticipantChipView: View {
    let participant: WorkCardParticipant
    let color: Color
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: participant.isCompleted ? "checkmark.circle.fill" : "circle")
                Text(participant.name)
            }
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(UIConstants.OpacityConstants.accent))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WorkCard.compact(
        work: WorkModel(status: .active, studentID: UUID().uuidString, lessonID: UUID().uuidString),
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
}
