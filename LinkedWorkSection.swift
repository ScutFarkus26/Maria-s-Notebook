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
                            let (icon, color) = iconAndColor(work.workType)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: icon)
                                        .foregroundStyle(color)
                                    Text(work.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (work.workType == .practice ? "Practice" : "Follow Up") : work.title)
                                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }

                                FlowLayout(spacing: 8) {
                                    ForEach(work.participants, id: \.id) { participant in
                                        if let student = studentsAll.first(where: { $0.id == participant.studentID }) {
                                            let done = participant.completedAt != nil
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
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.03))
                            )
                        }
                    }
                }
            }
        }
    }
}
