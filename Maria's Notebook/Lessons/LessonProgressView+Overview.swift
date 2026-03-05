// LessonProgressView+Overview.swift
// Overview tab content extracted from LessonProgressView

import SwiftUI
import SwiftData

extension LessonProgressView {
    // MARK: - Overview Tab

    @ViewBuilder
    var overviewContent: some View {
        if let stats = stats {
            VStack(spacing: AppTheme.Spacing.large) {
                // Stats cards
                statsCards(stats: stats)

                // Journey timeline
                VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                    Text("Lesson Journey")
                        .font(AppTheme.ScaledFont.titleSmall)

                    LessonJourneyTimeline(lesson: lesson, modelContext: modelContext)
                        .frame(height: 350)
                }

                // Quick insights
                quickInsights(stats: stats)
            }
        }
    }

    @ViewBuilder
    func statsCards(stats: LessonStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.Spacing.medium) {
            statCard(
                title: "Presentations",
                value: "\(stats.presentedCount)",
                subtitle: "\(stats.scheduledCount) scheduled",
                icon: "calendar.badge.checkmark",
                color: .green
            )

            statCard(
                title: "Work Items",
                value: "\(stats.completedWorkItems)/\(stats.totalWorkItems)",
                subtitle: stats.totalWorkItems > 0 ? "\(Int(stats.workCompletionRate * 100))% complete" : "No work yet",
                icon: "folder.badge.gearshape",
                color: .blue
            )

            statCard(
                title: "Active Work",
                value: "\(stats.activeWorkItems)",
                subtitle: stats.activeWorkItems == 0 ? "All caught up!" : "In progress",
                icon: "circle.dashed",
                color: .orange
            )

            statCard(
                title: "Practice Sessions",
                value: "\(stats.totalPracticeSessions)",
                subtitle: stats.totalPracticeSessions > 0 ? "Last: \(stats.lastPresentedDate?.formatted(date: .abbreviated, time: .omitted) ?? "N/A")" : "None yet",
                icon: "person.2.fill",
                color: .purple
            )
        }
    }

    @ViewBuilder
    func statCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(AppTheme.ScaledFont.titleLarge)

                Text(title)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)

                Text(subtitle)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(AppTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                .fill(color.opacity(UIConstants.OpacityConstants.faint))
        )
    }

    @ViewBuilder
    func quickInsights(stats: LessonStats) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Insights")
                .font(AppTheme.ScaledFont.titleSmall)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                if stats.activeWorkItems > 0 {
                    insightRow(
                        icon: "exclamationmark.circle",
                        text: "\(stats.activeWorkItems) work \(stats.activeWorkItems == 1 ? "item" : "items") still in progress",
                        color: .orange
                    )
                }

                if stats.workCompletionRate == 1.0 && stats.totalWorkItems > 0 {
                    insightRow(
                        icon: "checkmark.circle.fill",
                        text: "All work completed! Great progress.",
                        color: .green
                    )
                }

                if stats.totalPracticeSessions == 0 && stats.totalWorkItems > 0 {
                    insightRow(
                        icon: "info.circle",
                        text: "No practice sessions recorded yet",
                        color: .blue
                    )
                }

                if stats.totalPresentations > 0 && stats.totalWorkItems == 0 {
                    insightRow(
                        icon: "arrow.forward.circle",
                        text: "Consider creating follow-up work",
                        color: .purple
                    )
                }
            }
        }
    }

    @ViewBuilder
    func insightRow(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: AppTheme.Spacing.small + 2) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)

            Text(text)
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.primary)
        }
        .padding(AppTheme.Spacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium + 2)
                .fill(color.opacity(UIConstants.OpacityConstants.faint))
        )
    }
}
