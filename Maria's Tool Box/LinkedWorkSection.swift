import SwiftUI

struct LinkedWorkSection: View {
    let works: [WorkModel]
    let studentsAll: [Student]
    var displayName: (Student) -> String
    var iconAndColor: (WorkModel.WorkType) -> (String, Color)
    var onToggle: (WorkModel, UUID) -> Void

    var body: some View {
        Group {
            if !works.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                        Text("Linked Work")
                            .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        ForEach(works, id: \.id) { work in
                            LinkedWorkItem(
                                work: work,
                                studentsAll: studentsAll,
                                displayName: displayName,
                                iconAndColor: iconAndColor,
                                onToggle: onToggle
                            )
                        }
                    }
                }
            }
        }
    }
}
private struct ParticipantChip: View {
    let work: WorkModel
    let student: Student
    let done: Bool
    let color: Color
    let displayName: (Student) -> String
    let onToggle: (WorkModel, UUID) -> Void

    var body: some View {
        Button {
            onToggle(work, student.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                Text(displayName(student))
            }
            .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StudentParticipation: Identifiable {
    let id: UUID
    let student: Student
    let done: Bool
}
private struct LinkedWorkItem: View {
    let work: WorkModel
    let studentsAll: [Student]
    var displayName: (Student) -> String
    var iconAndColor: (WorkModel.WorkType) -> (String, Color)
    var onToggle: (WorkModel, UUID) -> Void

    private var icon: String { iconAndColor(work.workType).0 }
    private var color: Color { iconAndColor(work.workType).1 }

    private var title: String {
        let rawTitle = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTitle.isEmpty {
            return work.workType == .practice ? "Practice" : "Follow Up"
        }
        return rawTitle
    }

    private var participations: [StudentParticipation] {
        let participants = work.participants ?? []
        return participants.compactMap { participant in
            guard let student = studentsAll.first(where: { $0.id == participant.studentID }) else { return nil }
            return StudentParticipation(
                id: student.id,
                student: student,
                done: participant.completedAt != nil
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }

            FlowLayout(spacing: 8) {
                ForEach(participations) { participation in
                    ParticipantChip(
                        work: work,
                        student: participation.student,
                        done: participation.done,
                        color: color,
                        displayName: displayName,
                        onToggle: onToggle
                    )
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}

