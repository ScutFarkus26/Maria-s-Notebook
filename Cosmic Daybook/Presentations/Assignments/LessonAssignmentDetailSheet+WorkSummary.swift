import SwiftUI
import CoreData

// MARK: - Work Summary Section

extension LessonAssignmentDetailSheet {

    func reloadWorkSummary() {
        workSummary = assignment.map { PresentationWorkSummary.load(for: $0, context: viewContext) }
    }

    @ViewBuilder
    var workSummarySection: some View {
        let workItems = workSummary?.workItems ?? []

        if let summary = workSummary, !workItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(.blue)
                    Text("Related Work")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    // Completion stats
                    let stats = summary.stats
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
                        .capsuleFill(
                            (stats.completed == stats.total ? Color.green : Color.secondary)
                                .opacity(UIConstants.OpacityConstants.light)
                        )
                    }
                }

                VStack(spacing: 8) {
                    ForEach(workItems) { work in
                        WorkItemCompactRow(work: work, student: summary.student(for: work))
                    }
                }

                // Practice sessions for this presentation's work
                let practiceSessions = summary.practiceSessions
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
                    .surface(
                        UIConstants.CornerRadius.control,
                        fill: Color.purple.opacity(UIConstants.OpacityConstants.hint)
                    )
                }
            }
        }
    }
}

// MARK: - Loaded data

/// Everything the "Related Work" section draws, read once. The section used to
/// run the related-work fetch three times per body pass (list, stats, and
/// again inside the practice-session lookup), read the whole practice-session
/// table, and fetch each row's student separately.
struct PresentationWorkSummary {
    let workItems: [CDWorkModel]
    let stats: (completed: Int, total: Int)
    let practiceSessions: [CDPracticeSession]
    /// Students named by `workItems`, by id — first row per id, as the
    /// per-row `fetchLimit = 1` lookup returned.
    let studentsByID: [UUID: CDStudent]

    func student(for work: CDWorkModel) -> CDStudent? {
        guard !work.studentID.isEmpty, let uuid = UUID(uuidString: work.studentID) else { return nil }
        return studentsByID[uuid]
    }

    static func load(for presentation: CDLessonAssignment, context: NSManagedObjectContext) -> PresentationWorkSummary {
        let workItems = presentation.fetchRelatedWork(from: context)
        let completed = workItems.filter { $0.status.isClosed }.count
        let practiceSessions = presentation.fetchRelatedPracticeSessions(from: context, relatedWork: workItems)

        let studentIDs = Set(workItems.compactMap { UUID(uuidString: $0.studentID) })
        var studentsByID: [UUID: CDStudent] = [:]
        if !studentIDs.isEmpty {
            let request = CDFetchRequest(CDStudent.self)
            request.predicate = NSPredicate(format: "id IN %@", Array(studentIDs))
            for student in context.safeFetch(request) {
                guard let id = student.id, studentsByID[id] == nil else { continue }
                studentsByID[id] = student
            }
        }
        return PresentationWorkSummary(
            workItems: workItems,
            stats: (completed, workItems.count),
            practiceSessions: practiceSessions,
            studentsByID: studentsByID
        )
    }
}
