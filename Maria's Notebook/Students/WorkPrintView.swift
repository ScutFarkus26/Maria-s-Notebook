import SwiftUI
import SwiftData

/// A consolidated, print-friendly view of open work items.
/// Designed to conserve paper while maintaining readability.
struct WorkPrintView: View {
    let workItems: [WorkModel]
    let students: [Student]
    let lessons: [Lesson]
    let filterDescription: String
    let sortDescription: String

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            PrintHeaderContent(
                filterDescription: filterDescription,
                sortDescription: sortDescription,
                workItemCount: workItems.count,
                studentCount: groupedWork.count
            )

            Divider()
                .padding(.vertical, 8)

            // Work items grouped by student
            ForEach(Array(groupedWork.enumerated()), id: \.offset) { index, group in
                PrintStudentSectionContent(
                    title: group.title,
                    works: group.works,
                    lessons: lessons
                )

                if index < groupedWork.count - 1 {
                    Divider()
                        .padding(.vertical, 12)
                }
            }

            Spacer()

            // Footer
            PrintFooterContent()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}

// MARK: - Standalone Sub-Views for Independent Rendering

/// Header block for the print view — renderable independently for pagination.
struct PrintHeaderContent: View {
    let filterDescription: String
    let sortDescription: String
    let workItemCount: Int
    let studentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Open Work Report")
                    .font(AppTheme.ScaledFont.titleSmall)
                Spacer()
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }

            if !filterDescription.isEmpty {
                Text("Filter: \(filterDescription)")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }

            if !sortDescription.isEmpty {
                Text("Sort: \(sortDescription)")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }

            Text(
                "\(workItemCount) work item\(workItemCount == 1 ? "" : "s")" +
                " \u{2022} \(studentCount) student\(studentCount == 1 ? "" : "s")"
            )
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.top, 8)
        }
    }
}

/// A single student section with all their work items — renderable independently.
struct PrintStudentSectionContent: View {
    let title: String
    let works: [WorkModel]
    let lessons: [Lesson]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Student name header
            Text(title)
                .font(AppTheme.ScaledFont.bodySemibold)
                .padding(.bottom, 4)

            // Work items for this student
            ForEach(Array(works.enumerated()), id: \.offset) { index, work in
                printWorkItemRow(work: work, index: index + 1)
            }
        }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func printWorkItemRow(work: WorkModel, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // Index number
                Text("\(index).")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)

                VStack(alignment: .leading, spacing: 3) {
                    // Lesson name
                    if let lessonID = UUID(uuidString: work.lessonID),
                       let lesson = lessons.first(where: { $0.id == lessonID }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AppColors.color(forSubject: lesson.subject))
                                .frame(width: 6, height: 6)

                            Text(lesson.name)
                                .font(AppTheme.ScaledFont.captionSemibold)
                        }
                    } else {
                        Text("Lesson")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)
                    }

                    // Work kind and status
                    HStack(spacing: 8) {
                        if let kind = work.kind {
                            Text(kind.displayName)
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)
                        }

                        if work.status != .active {
                            Text("\u{2022}")
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)

                            Text(work.status.displayName)
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)
                        }

                        // Due date
                        if let dueAt = work.dueAt {
                            Text("\u{2022}")
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(.secondary)

                            Text("Due: \(dueAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(AppTheme.ScaledFont.captionSmall)
                                .foregroundStyle(dueAt < Date() ? .red : .secondary)
                        }
                    }

                    // Title (if present)
                    if !work.title.isEmpty {
                        Text(work.title)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.primary)
                    }

                    // Notes (if present and brief)
                    if !work.latestUnifiedNoteText.isEmpty {
                        Text(work.latestUnifiedNoteText)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.top, 1)
                    }

                    // Steps summary (for reports)
                    if work.isReport {
                        let progress = work.stepProgress
                        if progress.total > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "checklist")
                                    .font(.system(size: 9))
                                Text("\(progress.completed)/\(progress.total) steps completed")
                                    .font(AppTheme.ScaledFont.captionSmall)
                            }
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        }
                    }
                }

                Spacer()

                // Checkbox for tracking
                Image(systemName: "square")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.02))
        )
    }
}

/// Footer block for the print view — renderable independently.
struct PrintFooterContent: View {
    var body: some View {
        HStack {
            Text("Generated by Maria's Notebook")
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

// MARK: - Extensions
// Note: WorkKind and WorkStatus displayName properties are defined in WorkTypes.swift
