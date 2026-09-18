// PresentationFollowUpList.swift
// Lessons already given that still carry an unresolved responsibility.
//
// These rows were the "Observe or Decide" section of the workspace's Attention
// tab, which stacked them above children's work — two different jobs in one
// list, because the workspace split by state before it split by kind. They now
// live behind the Presentations half's Follow Up pill, beside the other
// presentation states.
//
// The view is pure: `ReadyToPresentSection` builds the groups once, so the
// pill's count and this list can't disagree, and renders rows rather than a
// `List` because it sits inside the pane's own scroll view.

import SwiftUI

struct PresentationFollowUpList: View {
    let groups: [FollowingPresentationGroup]
    let focusedPresentationID: UUID?
    let onOpen: (CDLessonAssignment) -> Void

    var body: some View {
        LazyVStack(spacing: AppTheme.Spacing.verySmall) {
            ForEach(groups) { group in
                row(group)
                    .id(group.id)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.compact)
    }

    private func row(_ group: FollowingPresentationGroup) -> some View {
        let isFocused = group.id == focusedPresentationID
        // Hoisted: folded into the modifier chain, these ternaries pushed the
        // row's type-check past the project's long-body warning threshold.
        let fill: Color = isFocused
            ? Color.accentColor.opacity(0.12)
            : Color.primary.opacity(UIConstants.OpacityConstants.trace)
        let stroke: Color = isFocused
            ? Color.accentColor
            : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
        let strokeWidth: CGFloat = isFocused ? 2 : 1
        return Button {
            if let assignment = group.assignment { onOpen(assignment) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "eye.circle.fill")
                    .foregroundStyle(AppColors.info)
                    .imageScale(.large)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.lessonName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(group.childNames)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(group.actionSummary) • \(timingText(for: group))")
                        .font(.caption)
                        .foregroundStyle(AppColors.info)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(stroke, lineWidth: strokeWidth))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(group.assignment == nil)
        .accessibilityLabel(
            "Follow \(group.lessonName) for \(group.childNames). \(group.actionSummary)."
        )
    }

    private func timingText(for group: FollowingPresentationGroup) -> String {
        if let date = group.earliestReviewAt {
            return "Review \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        let days = group.schoolDaysSincePresentation
        return days == 0 ? "Presented today" : "\(days) school day\(days == 1 ? "" : "s") ago"
    }
}
