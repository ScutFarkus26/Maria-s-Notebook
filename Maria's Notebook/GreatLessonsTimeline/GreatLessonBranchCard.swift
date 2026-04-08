// GreatLessonBranchCard.swift
// Card view for a single Great Lesson branch showing progress and subject breakdown.

import SwiftUI

struct GreatLessonBranchCard: View {
    let branch: GreatLessonBranch

    private var gl: GreatLesson { branch.greatLesson }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            Divider()
            subjectCapsules
            statsRow
            gapIndicator
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(UIConstants.OpacityConstants.subtle), radius: 4, y: 2)
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(gl.color)
                .frame(width: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 12) {
            Image(systemName: gl.icon)
                .font(.title2)
                .foregroundStyle(gl.color)
                .frame(width: 36, height: 36)
                .background(
                    gl.color.opacity(UIConstants.OpacityConstants.medium),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(gl.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(gl.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            progressRing
        }
    }

    // MARK: - Progress Ring

    private var progressRing: some View {
        let rate = branch.overallCompletionRate

        return ZStack {
            Circle()
                .stroke(gl.color.opacity(UIConstants.OpacityConstants.light), lineWidth: 4)
            Circle()
                .trim(from: 0, to: rate)
                .stroke(gl.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(rate * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(gl.color)
        }
        .frame(width: 40, height: 40)
    }

    // MARK: - Subject Capsules

    private var subjectCapsules: some View {
        FlowLayout(spacing: 6) {
            ForEach(branch.subjectGroups) { group in
                subjectCapsule(group)
            }
        }
    }

    private func subjectCapsule(_ group: BranchSubjectGroup) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(AppColors.color(forSubject: group.subject))
                .frame(width: 6, height: 6)
            Text("\(group.subject) · \(group.lessons.count)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(AppColors.color(forSubject: group.subject).opacity(UIConstants.OpacityConstants.light))
        )
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 16) {
            statBadge(
                count: branch.totalLessons,
                label: "lessons",
                icon: "book",
                color: gl.color
            )
            statBadge(
                count: branch.studentsWithPresentations,
                label: "students",
                icon: "person.2",
                color: .primary
            )
            if branch.totalActiveWork > 0 {
                statBadge(
                    count: branch.totalActiveWork,
                    label: "active work",
                    icon: "tray.full",
                    color: .blue
                )
            }
        }
    }

    private func statBadge(count: Int, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(count) \(label)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Gap Indicator

    @ViewBuilder
    private var gapIndicator: some View {
        let gaps = branch.studentsWithGaps
        if gaps > 0 {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
                Text("\(gaps) student\(gaps == 1 ? "" : "s") with no presentations")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } else if !branch.studentProgress.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                    .font(.caption2)
                    .foregroundStyle(AppColors.success)
                Text("All students have presentations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
