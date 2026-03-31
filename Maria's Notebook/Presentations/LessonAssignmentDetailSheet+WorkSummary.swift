import SwiftUI
import CoreData

// MARK: - Work Summary Section

extension LessonAssignmentDetailSheet {

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func workSummarySection(for presentation: CDLessonAssignment) -> some View {
        let workItems = presentation.fetchRelatedWork(from: viewContext)

        if !workItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(.blue)
                    Text("Related Work")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    // Completion stats
                    let stats = presentation.workCompletionStats(from: viewContext)
                    if stats.total > 0 {
                        HStack(spacing: 4) {
                            Text("\(stats.completed)/\(stats.total)")
                                .font(AppTheme.ScaledFont.captionSemibold)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(stats.completed == stats.total ? .green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill((stats.completed == stats.total ? Color.green : Color.secondary).opacity(UIConstants.OpacityConstants.light))
                        )
                    }
                }

                VStack(spacing: 8) {
                    ForEach(workItems) { work in
                        WorkItemCompactRow(work: work, viewContext: viewContext)
                    }
                }

                // Practice sessions for this presentation's work
                let practiceSessions = presentation.fetchRelatedPracticeSessions(from: viewContext)
                if !practiceSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Practice Sessions (\(practiceSessions.count))")
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                        .foregroundStyle(.purple)

                        ForEach(practiceSessions.prefix(3)) { session in
                            PracticeSessionCompactRow(session: session)
                        }

                        if practiceSessions.count > 3 {
                            Text("+ \(practiceSessions.count - 3) more sessions")
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 8)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(UIConstants.OpacityConstants.hint))
                    )
                }
            }
        }
    }
}
