import SwiftUI
import CoreData

extension ProjectDetailView {
    var studentProgressSection: some View {
        SectionCard(title: "Student Progress", systemImage: "person.line.dotted.person") {
            if club.memberStudentIDsArray.isEmpty {
                Text("Add students to begin tracking the project group")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(
                        club.memberStudentIDsArray.sorted { studentName(for: $0) < studentName(for: $1) },
                        id: \.self
                    ) { sid in
                        ProjectStudentProgressRow(
                            studentName: studentName(for: sid),
                            works: workModels(forStudentID: sid)
                        )
                    }
                }
            }
        }
    }

    var followUpsSection: some View {
        SectionCard(title: "Progress & Follow-Ups", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                if projectWorks.isEmpty {
                    Text("Create a project check-in to start follow-up work")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: Double(completedWorkCount), total: Double(max(projectWorks.count, 1)))
                    Text("\(completedWorkCount) of \(projectWorks.count) follow-ups complete")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)

                    if openFollowUps.isEmpty {
                        Label("All follow-ups are complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                    } else {
                        VStack(spacing: AppTheme.Spacing.xsmall) {
                            ForEach(openFollowUps.prefix(6), id: \.objectID) { work in
                                ProjectFollowUpRow(
                                    work: work,
                                    lesson: UUID(uuidString: work.lessonID).flatMap { lessonsByID[$0] },
                                    studentName: displayStudents(for: work)
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ProjectStudentProgressRow: View {
    let studentName: String
    let works: [CDWorkModel]

    private var completed: Int { works.filter { $0.status == .complete }.count }
    private var reviewing: Int { works.filter { $0.status == .review }.count }
    private var active: Int { works.filter { $0.status == .active }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
            HStack {
                Text(studentName)
                    .font(AppTheme.ScaledFont.bodySemibold)
                Spacer()
                Text(works.isEmpty ? "No follow-ups" : "\(completed)/\(works.count) complete")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
            }

            if !works.isEmpty {
                ProgressView(value: Double(completed), total: Double(max(works.count, 1)))
                HStack(spacing: AppTheme.Spacing.small) {
                    ProjectStatusPill(title: "Active", count: active, color: AppColors.info)
                    ProjectStatusPill(title: "Review", count: reviewing, color: AppColors.warning)
                    ProjectStatusPill(title: "Complete", count: completed, color: AppColors.success)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .cornerRadius(UIConstants.CornerRadius.small)
    }
}

private struct ProjectStatusPill: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxsmall) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count) \(title)")
                .font(AppTheme.ScaledFont.caption)
        }
        .foregroundStyle(.secondary)
    }
}

private struct ProjectFollowUpRow: View {
    @ObservedObject var work: CDWorkModel
    let lesson: CDLesson?
    let studentName: String

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
            Image(systemName: work.status.iconName)
                .foregroundStyle(work.status.color)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(work.title.isEmpty ? "Untitled follow-up" : work.title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                Text(studentName)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                if let lesson {
                    Text(lesson.name)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let due = work.dueAt {
                Text(due, format: Date.FormatStyle().month().day())
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppTheme.Spacing.small)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
        .cornerRadius(UIConstants.CornerRadius.small)
    }
}
