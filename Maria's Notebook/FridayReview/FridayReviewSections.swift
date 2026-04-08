// FridayReviewSections.swift
// Section subviews for the Friday Review Ritual.

import SwiftUI

// MARK: - Week Summary Section

struct FridayReviewWeekSummarySection: View {
    let summary: WeekSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This Week")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                statCard(
                    value: summary.presentationsGiven,
                    label: "Presentations",
                    icon: SFSymbol.Education.book,
                    color: .blue
                )
                statCard(
                    value: summary.notesRecorded,
                    label: "Notes",
                    icon: "square.and.pencil",
                    color: .purple
                )
                statCard(
                    value: summary.workCompleted,
                    label: "Completed",
                    icon: SFSymbol.Action.checkmarkCircleFill,
                    color: AppColors.success
                )
            }
        }
    }

    private func statCard(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyle()
    }
}

// MARK: - Unobserved Students Section

struct FridayReviewUnobservedSection: View {
    let students: [UnobservedStudent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Unobserved Students")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if students.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                            .font(.caption)
                            .foregroundStyle(AppColors.success)
                        Text("All observed")
                            .font(.caption)
                            .foregroundStyle(AppColors.success)
                    }
                } else {
                    Text("\(students.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.warning)
                }
            }

            if students.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "party.popper")
                        .foregroundStyle(AppColors.success)
                    Text("Every student was observed this week!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .cardStyle()
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(students) { student in
                        studentCapsule(student)
                    }
                }
            }
        }
    }

    private func studentCapsule(_ student: UnobservedStudent) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(AppColors.color(forLevel: student.level).gradient)
                .frame(width: 8, height: 8)

            Text(student.displayName)
                .font(.caption)
                .fontWeight(.medium)

            if let days = student.daysSinceLastNote {
                Text("\(days)d")
                    .font(.system(size: 9))
                    .foregroundStyle(days > 14 ? AppColors.destructive : AppColors.warning)
            } else {
                Text("never")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.destructive)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(AppColors.warning.opacity(UIConstants.OpacityConstants.light))
        )
    }
}

// MARK: - Follow-Up Section

struct FridayReviewFollowUpSection: View {
    let items: [FollowUpItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Needs Follow-Up")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(items.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }

            LazyVStack(spacing: 8) {
                ForEach(items) { item in
                    followUpCard(item)
                }
            }
        }
    }

    private func followUpCard(_ item: FollowUpItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.lessonTitle)
                .font(.subheadline)
                .fontWeight(.medium)

            HStack(spacing: 6) {
                if item.needsPractice {
                    flagBadge("Practice", color: .blue)
                }
                if item.needsAnotherPresentation {
                    flagBadge("Re-present", color: .purple)
                }
            }

            if !item.studentNames.isEmpty {
                Text(item.studentNames.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Presented \(item.presentedAt, format: .dateTime.month(.abbreviated).day())")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func flagBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9))
            .fontWeight(.medium)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(UIConstants.OpacityConstants.light))
            )
    }
}

// MARK: - Stale Work Section

struct FridayReviewStaleWorkSection: View {
    let items: [StaleWorkItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stale Work")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(items.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColors.destructive)
            }

            LazyVStack(spacing: 8) {
                ForEach(items) { item in
                    staleWorkCard(item)
                }
            }
        }
    }

    private func staleWorkCard(_ item: StaleWorkItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(item.studentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(item.daysSinceTouch)d")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(item.daysSinceTouch >= 7 ? AppColors.destructive : AppColors.warning)

                Text("untouched")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle()
    }
}

// MARK: - Monday Priorities Section

struct FridayReviewMondayPrioritiesSection: View {
    let priorities: [MondayPriority]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Monday Priorities")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            VStack(spacing: 0) {
                ForEach(Array(priorities.enumerated()), id: \.element.id) { index, priority in
                    if index > 0 {
                        Divider()
                    }
                    priorityRow(priority, number: index + 1)
                }
            }
            .cardStyle()
        }
    }

    private func priorityRow(_ priority: MondayPriority, number: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(priority.priorityType.color.gradient, in: Circle())

            Image(systemName: priority.priorityType.icon)
                .font(.caption)
                .foregroundStyle(priority.priorityType.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(priority.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(priority.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}
