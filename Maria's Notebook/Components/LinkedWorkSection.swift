import SwiftUI

struct LinkedWorkSection: View {
    let works: [CDWorkModel]
    let studentsAll: [CDStudent]
    var displayName: (CDStudent) -> String
    var onToggle: (CDWorkModel, UUID) -> Void

    var body: some View {
        Group {
            if !works.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16))
                        Text("Linked Work")
                            .font(AppTheme.ScaledFont.calloutSemibold)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        ForEach(works, id: \.id) { work in
                            WorkCard.compact(
                                work: work,
                                title: workTitle(for: work),
                                workType: workCardType(for: work),
                                participants: participants(for: work),
                                onToggle: onToggle
                            )
                        }
                    }
                }
            }
        }
    }

    private func workCardType(for work: CDWorkModel) -> WorkCardWorkType {
        // All work should have kind set after migration
        return WorkCardWorkType(from: work.kind ?? .research)
    }

    private func workTitle(for work: CDWorkModel) -> String {
        let rawTitle = work.title.trimmed()
        if rawTitle.isEmpty {
            // Use kind for default title
            let kind = work.kind ?? .research
            return kind == .practiceLesson ? "Practice" : "Follow Up"
        }
        return rawTitle
    }

    private func participants(for work: CDWorkModel) -> [WorkCardParticipant] {
        let workParticipants = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        return workParticipants.compactMap { participant in
            guard let studentIDUUID = UUID(uuidString: participant.studentID),
                  let student = studentsAll.first(where: { $0.id == studentIDUUID }) else { return nil }
            let sid = student.id ?? UUID()
            return WorkCardParticipant(
                id: sid,
                studentID: sid,
                name: displayName(student),
                isCompleted: participant.completedAt != nil
            )
        }
    }
}
