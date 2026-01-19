import SwiftUI

struct LinkedWorkSection: View {
    let works: [WorkModel]
    let studentsAll: [Student]
    var displayName: (Student) -> String
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
                            WorkCard.compact(
                                work: work,
                                title: workTitle(for: work),
                                workType: WorkCardWorkType(from: work.workType),
                                participants: participants(for: work),
                                onToggle: onToggle
                            )
                        }
                    }
                }
            }
        }
    }

    private func workTitle(for work: WorkModel) -> String {
        let rawTitle = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawTitle.isEmpty {
            return work.workType == .practice ? "Practice" : "Follow Up"
        }
        return rawTitle
    }

    private func participants(for work: WorkModel) -> [WorkCardParticipant] {
        let workParticipants = work.participants ?? []
        return workParticipants.compactMap { participant in
            guard let studentIDUUID = UUID(uuidString: participant.studentID),
                  let student = studentsAll.first(where: { $0.id == studentIDUUID }) else { return nil }
            return WorkCardParticipant(
                id: student.id,
                studentID: student.id,
                name: displayName(student),
                isCompleted: participant.completedAt != nil
            )
        }
    }
}
