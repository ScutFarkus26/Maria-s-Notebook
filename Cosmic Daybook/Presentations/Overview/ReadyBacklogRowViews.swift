// ReadyBacklogRowViews.swift
// The small pieces a backlog row is drawn from: a child's chip, a flag badge,
// the row's two layouts, and the drag preview.
//
// They take plain values, not managed objects, so a row costs no fetch and a
// drag preview — which renders detached from the app's environment — has
// nothing to look up.

import SwiftUI

/// One child on a backlog row, resolved once per render by the section.
struct BacklogChip: Identifiable {
    let id: UUID
    let name: String
    /// "15" or "new" — set only for a child at or past the long-wait
    /// threshold, so an ordinary chip stays just a name.
    let waitBadge: String?
    /// The wait said in full, for VoiceOver ("15 school days since a lesson").
    let spokenWait: String?
    /// The child's own work is what keeps a brewing lesson waiting.
    let isBlocking: Bool

    var isLongWait: Bool { waitBadge != nil }

    var accessibilityText: String {
        guard let spokenWait else { return name }
        return "\(name), \(spokenWait)"
    }
}

struct BacklogStudentChip: View {
    let chip: BacklogChip
    /// The Waiting Longest rail's own overdue color, so a tinted chip and a
    /// red bar in the rail mean the same thing.
    let longWaitColor: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xxsmall) {
            Text(chip.name)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .foregroundStyle(.primary)
            if let badge = chip.waitBadge {
                Text("· \(badge)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(longWaitColor)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .capsuleFill(
            chip.isLongWait
                ? longWaitColor.opacity(UIConstants.OpacityConstants.accent)
                : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
        )
        .overlay(
            Capsule()
                .stroke(AppColors.color(for: .brewing), lineWidth: chip.isBlocking ? 1.5 : 0)
        )
    }
}

/// "Overdue" / "Missed" at the end of a row, so a flag still shows when no
/// flag filter is on.
struct BacklogFlagBadge: View {
    let flag: PresentationsFilterChip

    var body: some View {
        Text(flag.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(flag.accent)
            .padding(.horizontal, UIConstants.CardSize.statusPillHorizontal)
            .padding(.vertical, 2)
            .capsuleFill(flag.accent.opacity(UIConstants.OpacityConstants.accent))
            .fixedSize()
    }
}

/// The area dot and lesson title that lead every row.
struct BacklogLessonTitle: View {
    let title: String
    let areaColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.verySmall) {
            Circle()
                .fill(areaColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(title)
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

/// Title beside its content where there is room, above it where there is not.
///
/// Side by side, the title sits in a fixed leading column so the chips of
/// every row start at the same x and read down the list as a column; on a
/// phone that column would leave the chips no room, so the title goes on top.
struct BacklogRowLayout<Title: View, Content: View>: View {
    let isCompact: Bool
    let titleWidth: CGFloat
    @ViewBuilder let title: Title
    @ViewBuilder let content: Content

    var body: some View {
        if isCompact {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                title
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .top, spacing: AppTheme.Spacing.compact) {
                title
                    .frame(width: titleWidth, alignment: .leading)
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// What follows the pointer while a backlog line is dragged to the calendar.
/// Reads nothing from the environment; the section still re-injects the
/// context, as every drag preview in the app does, so a later edit that
/// reaches for it cannot crash a drag lift.
struct BacklogDragPreview: View {
    let title: String
    let areaColor: Color
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
            BacklogLessonTitle(title: title, areaColor: areaColor)
            if !names.isEmpty {
                Text(names.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(AppTheme.Spacing.small)
        .frame(width: 240, alignment: .leading)
        .background(
            .background,
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium, style: .continuous)
        )
        .opacity(UIConstants.OpacityConstants.nearSolid)
    }
}
