// LessonProgressView+Tabs.swift
// Presentations, Work, and Practice tab content extracted from LessonProgressView

import SwiftUI
import CoreData

extension LessonProgressView {
    // MARK: - Presentations Tab

    @ViewBuilder
    var presentationsContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if presentations.isEmpty {
                emptyStateView(
                    icon: "calendar.badge.clock",
                    title: "No Presentations",
                    message: "This lesson hasn't been presented yet"
                )
            } else {
                ForEach(presentations) { presentation in
                    presentationRow(presentation)
                }
            }
        }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func presentationRow(_ presentation: Presentation) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ZStack {
                    Circle()
                        .fill(
                            presentation.isPresented
                                ? Color.green.opacity(UIConstants.OpacityConstants.accent)
                                : Color.blue.opacity(UIConstants.OpacityConstants.accent)
                        )
                        .frame(width: 44, height: 44)

                    Image(systemName: presentation.isPresented ? "checkmark.circle.fill" : "calendar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(presentation.isPresented ? .green : .blue)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall + 1) {
                    Text(presentation.isPresented ? "Presented" : presentation.isScheduled ? "Scheduled" : "Draft")
                        .font(AppTheme.ScaledFont.bodySemibold)

                    if let date = presentation.presentedAt ?? presentation.scheduledFor {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                let students = presentation.fetchStudents(from: viewContext)
                StatusPill(
                    text: "\(students.count) \(students.count == 1 ? "student" : "students")",
                    color: .secondary,
                    icon: nil
                )
            }

            // Related work summary
            let work = allWork.filter { $0.presentationID == presentation.id?.uuidString }
            if !work.isEmpty {
                HStack(spacing: AppTheme.Spacing.verySmall) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    let completed = work.filter { $0.status == .complete }.count
                    Text("\(work.count) work \(work.count == 1 ? "item" : "items") (\(completed) complete)")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 56)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .stroke(
                    Color.primary.opacity(UIConstants.OpacityConstants.light),
                    lineWidth: UIConstants.StrokeWidth.thin
                )
        )
    }

    // MARK: - Work Tab

    @ViewBuilder
    var workContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if allWork.isEmpty {
                emptyStateView(
                    icon: "folder.badge.gearshape",
                    title: "No Work Items",
                    message: "No work has been created for this lesson yet"
                )
            } else {
                ForEach(allWork) { work in
                    workRow(work)
                }
            }
        }
    }

    @ViewBuilder
    func workRow(_ work: CDWorkModel) -> some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            ZStack {
                Circle()
                    .fill(work.status.color.opacity(UIConstants.OpacityConstants.accent))
                    .frame(width: 44, height: 44)

                Image(systemName: work.status.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(work.status.color)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Text(work.title)
                    .font(AppTheme.ScaledFont.bodySemibold)

                HStack(spacing: AppTheme.Spacing.verySmall) {
                    if let student = work.fetchStudent(from: viewContext) {
                        Text(StudentFormatter.displayName(for: student))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let kind = work.kind {
                        Text("\u{2022}")
                            .foregroundStyle(.tertiary)
                        Text(kind.displayName)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            StatusPill(
                text: work.status.displayName,
                color: work.status.color,
                icon: nil
            )
        }
        .padding(AppTheme.Spacing.compact + 2)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium + 2)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium + 2)
                .stroke(
                    Color.primary.opacity(UIConstants.OpacityConstants.faint),
                    lineWidth: UIConstants.StrokeWidth.thin
                )
        )
    }

    // MARK: - Practice Tab

    @ViewBuilder
    var practiceContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if practiceSessions.isEmpty {
                emptyStateView(
                    icon: "person.2.fill",
                    title: "No Practice Sessions",
                    message: "No practice sessions have been recorded for this lesson"
                )
            } else {
                ForEach(practiceSessions) { session in
                    practiceSessionRow(session)
                }
            }
        }
    }

    @ViewBuilder
    func practiceSessionRow(_ session: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small + 2) {
            HStack(spacing: AppTheme.Spacing.compact) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(UIConstants.OpacityConstants.accent))
                        .frame(width: 44, height: 44)

                    Image(systemName: session.isGroupSession ? "person.2.fill" : "person.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall + 1) {
                    Text(session.isGroupSession ? "Group Practice" : "Solo Practice")
                        .font(AppTheme.ScaledFont.bodySemibold)

                    Text((session.date ?? Date()).formatted(date: .abbreviated, time: .omitted))
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let duration = session.durationFormatted {
                    StatusPill(
                        text: duration,
                        color: .secondary,
                        icon: nil
                    )
                }
            }

            // Students
            let students = session.fetchStudents(from: viewContext)
            if !students.isEmpty {
                HStack(spacing: AppTheme.Spacing.verySmall) {
                    Image(systemName: "person.2")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text(students.map { StudentFormatter.displayName(for: $0) }.joined(separator: ", "))
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(AppTheme.Spacing.compact + 2)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium + 2)
                .fill(Color.purple.opacity(UIConstants.OpacityConstants.veryFaint + 0.01))
        )
    }

    // MARK: - Helper Views

    @ViewBuilder
    func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)

            VStack(spacing: AppTheme.Spacing.verySmall) {
                Text(title)
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(.secondary)

                Text(message)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
