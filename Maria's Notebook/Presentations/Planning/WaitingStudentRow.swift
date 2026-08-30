// WaitingStudentRow.swift
// One child in the waiting list, with how long they have gone without a lesson.
//
// The urgency signal is the app's existing one — the 3pt coloured bar down the
// leading edge that already marks an aging work card and an aging presentation
// pill, on the same guide-configurable thresholds. A guide who has learned to
// read that bar reads this list for free.

import SwiftUI

struct WaitingStudentRow: View {
    let entry: WaitingStudent
    let isSelected: Bool
    let onTap: () -> Void

    @SyncedAppStorage(UserDefaultsKeys.lessonAgeWarningDays)
    private var ageWarningDays: Int = LessonAgeDefaults.warningDays
    @SyncedAppStorage(UserDefaultsKeys.lessonAgeOverdueDays)
    private var ageOverdueDays: Int = LessonAgeDefaults.overdueDays
    @SyncedAppStorage(UserDefaultsKeys.lessonAgeFreshColorHex)
    private var ageFreshColorHex: String = LessonAgeDefaults.freshColorHex
    @SyncedAppStorage(UserDefaultsKeys.lessonAgeWarningColorHex)
    private var ageWarningColorHex: String = LessonAgeDefaults.warningColorHex
    @SyncedAppStorage(UserDefaultsKeys.lessonAgeOverdueColorHex)
    private var ageOverdueColorHex: String = LessonAgeDefaults.overdueColorHex

    /// A child who has never been taught is the most overdue thing on the list,
    /// not an unknown.
    private var ageStatus: LessonAgeStatus {
        guard let days = entry.daysWaiting else { return .overdue }
        if days >= max(0, ageOverdueDays) { return .overdue }
        if days >= max(0, ageWarningDays) { return .warning }
        return .fresh
    }

    private var ageColor: Color {
        switch ageStatus {
        case .fresh: ColorUtils.color(from: ageFreshColorHex)
        case .warning: ColorUtils.color(from: ageWarningColorHex)
        case .overdue: ColorUtils.color(from: ageOverdueColorHex)
        }
    }

    private var waitLabel: String {
        guard let days = entry.daysWaiting else { return "Never taught" }
        switch days {
        case 0: return "Taught today"
        case 1: return "1 school day ago"
        default: return "\(days) school days ago"
        }
    }

    private var waitTint: Color {
        switch ageStatus {
        case .fresh: .secondary
        case .warning, .overdue: ageColor
        }
    }

    private var accessibilityDescription: String {
        "\(StudentFormatter.displayName(for: entry.student)), \(waitLabel.lowercased())"
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
                        Text(waitLabel)
                            .font(AppTheme.SemanticFont.metadata)
                            .foregroundStyle(waitTint)
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
        .accessibilityHint("Shows only lessons ready for this child")
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
