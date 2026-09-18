// WorkspaceFilterPillRow.swift
// The one pill row both halves of the Lessons & Work workspace filter with.
//
// Presentations had this row first — All / Suggested Next / Brewing / Overdue
// / Recently Missed — drawn inline inside `ReadyToPresentSection`. Work had no
// row at all: its state slices *were* the workspace's top-level tabs, so the
// two halves of one screen were filtered by two different mechanisms sitting
// at two different levels.
//
// Now that kind is the top-level axis (`WorkspaceKind`), state is a pill row
// on both sides. This is that row, written once, so the two cannot drift.

import SwiftUI

/// One pill in a workspace filter row.
///
/// Conformers are plain enums — the row needs a title, a glyph, and an accent
/// drawn from the same status ramp the cards and badges use, so a pill and the
/// cards it reveals are never two different colours for one idea.
protocol WorkspaceFilterChip: CaseIterable, Hashable, Identifiable, Sendable {
    var title: String { get }
    var systemImage: String { get }
    var accent: Color { get }
}

/// A horizontal row of filter pills with live counts.
///
/// Re-tapping the selected pill returns to `unfiltered`, so the row always has
/// a way back to everything without a separate "clear" affordance.
struct WorkspaceFilterPillRow<Chip: WorkspaceFilterChip>: View {
    @Binding var selection: Chip
    /// The pill that means "no filter" — where a re-tap lands.
    let unfiltered: Chip
    /// Count shown on each pill. Zero hides the badge rather than showing "0".
    let count: (Chip) -> Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.verySmall) {
                ForEach(Array(Chip.allCases)) { chip in
                    pill(chip)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
        }
    }

    private func pill(_ chip: Chip) -> some View {
        let isSelected = selection == chip
        let accent = chip.accent
        let badge = count(chip)
        return Button {
            adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                selection = isSelected ? unfiltered : chip
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xxsmall) {
                Image(systemName: chip.systemImage)
                    .font(.caption2)
                Text(chip.title)
                    .font(.caption.weight(.medium))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                isSelected
                                    ? Color.white.opacity(0.25)
                                    : accent.opacity(UIConstants.OpacityConstants.accent)
                            )
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.white : accent)
            .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
            .padding(.vertical, AppTheme.Spacing.verySmall)
            .background(
                Capsule().fill(isSelected
                    ? accent
                    : accent.opacity(UIConstants.OpacityConstants.accent))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(badge > 0 ? "\(chip.title), \(badge)" : chip.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
