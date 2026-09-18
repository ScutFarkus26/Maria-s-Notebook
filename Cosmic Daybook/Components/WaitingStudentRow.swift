// WaitingStudentRow.swift
// One child in a waiting list, with how long they have gone without the guide.
//
// The urgency signal is the app's existing one — the 3pt coloured bar down the
// leading edge that already marks an aging work card and an aging presentation
// pill, on the same guide-configurable thresholds. A guide who has learned to
// read that bar reads this list for free.
//
// The row is told its colour and its wording rather than working them out. Both
// columns that use it — lessons on the left of Presentations, work on the left
// of Work — read five settings to colour that bar, and reading them here meant
// five store lookups per child per body pass. `WaitingStudentsColumn` reads
// them once for the whole list instead.

import SwiftUI

struct WaitingStudentRow: View {
    let entry: WaitingStudent
    /// The bar down the leading edge, already resolved from the column's
    /// thresholds.
    let ageColor: Color
    /// The line under the name: "Never taught", "12 school days ago".
    let detail: String
    /// Secondary while the child is fresh, the urgency colour once they are not.
    let detailTint: Color
    /// What tapping this row does, for VoiceOver.
    let selectionHint: String
    let isSelected: Bool
    let onTap: () -> Void

    private var accessibilityDescription: String {
        "\(StudentFormatter.displayName(for: entry.student)), \(detail.lowercased())"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Rectangle()
                    .fill(ageColor)
                    .frame(width: UIConstants.ageIndicatorWidth)
                    .accessibilityHidden(true)

                HStack(spacing: AppTheme.Spacing.small) {
                    StudentAvatarView(student: entry.student, size: 28)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                        Text(StudentFormatter.displayName(for: entry.student))
                            .font(AppTheme.ScaledFont.bodySemibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Text(detail)
                            .font(AppTheme.SemanticFont.metadata)
                            .foregroundStyle(detailTint)
                            .lineLimit(1)
                    }

                    Spacer(minLength: AppTheme.Spacing.small)
                }
                .padding(.vertical, AppTheme.Spacing.verySmall)
                .padding(.horizontal, AppTheme.Spacing.small)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selectionBackground)
        .hoverableRow()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(selectionHint)
    }

    /// Selection is the accent colour, never the urgency colour — otherwise
    /// picking a child would read as that child becoming urgent.
    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: UIConstants.StrokeWidth.thin)
                )
        }
    }
}
