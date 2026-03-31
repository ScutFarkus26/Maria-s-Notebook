// GroupedWorkListRows.swift
// Grouped/compound work list row components for TodayView

import SwiftUI

// MARK: - Grouped Scheduled Work Row

struct GroupedScheduledWorkListRow: View {
    let items: [ScheduledWorkItem]
    let studentNames: [String]
    let lessonName: String
    let isFlexible: Bool
    var onTap: (UUID) -> Void

    @State private var isExpanded: Bool = false

    private var studentNamesDisplay: String {
        studentNames.joined(separator: ", ")
    }

    private var accessibilityLabelText: String {
        "Group check-in for \(studentNamesDisplay), \(lessonName), \(items.count) students"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main grouped row
            Button {
                if isFlexible {
                    adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } else if let first = items.first, let workID = first.work.id {
                    onTap(workID)
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(items.count)")
                                .font(AppTheme.ScaledFont.captionSmallSemibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange))
                            Text(studentNamesDisplay)
                                .font(AppTheme.ScaledFont.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        Text(lessonName)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isFlexible {
                        Image(systemName: isExpanded ? SFSymbol.Navigation.chevronUp : SFSymbol.Navigation.chevronDown)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if let date = items.first?.checkIn.date {
                        Text(date, style: .date)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.subtleRow)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint(
                isFlexible
                    ? "Double tap to expand individual students"
                    : "Double tap to view group check-in"
            )

            // Expanded individual rows (flexible mode only)
            if isFlexible && isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(zip(items, studentNames)), id: \.0.id) { item, name in
                        Button {
                            if let workID = item.work.id { onTap(workID) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: SFSymbol.People.personFill)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(.leading, 28)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.subtleRow)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Grouped Follow-Up Work Row

struct GroupedFollowUpWorkListRow: View {
    let items: [FollowUpWorkItem]
    let studentNames: [String]
    let lessonName: String
    let isFlexible: Bool
    var onTap: (UUID) -> Void

    @State private var isExpanded: Bool = false

    private var studentNamesDisplay: String {
        studentNames.joined(separator: ", ")
    }

    private var maxDaysSinceTouch: Int {
        items.map(\.daysSinceTouch).max() ?? 0
    }

    private var accessibilityLabelText: String {
        "Group follow-up for \(studentNamesDisplay), \(lessonName), \(maxDaysSinceTouch) days since last update"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isFlexible {
                    adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } else if let first = items.first, let workID = first.work.id {
                    onTap(workID)
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(items.count)")
                                .font(AppTheme.ScaledFont.captionSmallSemibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.purple))
                            Text(studentNamesDisplay)
                                .font(AppTheme.ScaledFont.callout)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        Text(lessonName)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if isFlexible {
                        Image(systemName: isExpanded ? SFSymbol.Navigation.chevronUp : SFSymbol.Navigation.chevronDown)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(maxDaysSinceTouch)d ago")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.subtleRow)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityHint(
                isFlexible
                    ? "Double tap to expand individual students"
                    : "Double tap to view group follow-up"
            )

            if isFlexible && isExpanded {
                VStack(spacing: 4) {
                    ForEach(Array(zip(items, studentNames)), id: \.0.id) { item, name in
                        Button {
                            if let workID = item.work.id { onTap(workID) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: SFSymbol.People.personFill)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(item.daysSinceTouch)d")
                                    .font(AppTheme.ScaledFont.caption)
                                    .foregroundStyle(.quaternary)
                            }
                            .padding(.leading, 28)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.subtleRow)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
