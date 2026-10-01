// ReadyToPresentFilterBar.swift
// The Presentations half's filter: a segmented control of the lesson's state
// and, beside it, toggles for the flags that narrow Ready.
//
// It replaced a row of six pills (`WorkspaceFilterPillRow`, which the Work half
// still uses) whose counts overlapped and could not add up. Every lesson is in
// exactly one segment, so the three segment counts are a true partition; the
// flags are subsets of what they narrow, and say so by keeping Ready lit.

import SwiftUI

struct ReadyToPresentFilterBar: View {
    @Binding var selection: PresentationsFilterChip
    /// Rows behind each segment or flag; zero hides the number.
    let count: (PresentationsFilterChip) -> Int

    var body: some View {
        // One line where it fits; on a phone the flags drop under the segments
        // rather than squeezing either.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.Spacing.compact) {
                segments
                    .fixedSize()
                Spacer(minLength: 0)
                flags
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                segments
                flags
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
    }

    private var segmentBinding: Binding<PresentationsFilterChip> {
        Binding(
            get: { selection.segment },
            set: { newValue in
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) { selection = newValue }
            }
        )
    }

    private var segments: some View {
        Picker("Lessons", selection: segmentBinding) {
            ForEach(PresentationsFilterChip.segments) { chip in
                Text(label(for: chip))
                    .tag(chip)
                    .accessibilityLabel(spokenLabel(for: chip))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var flags: some View {
        HStack(spacing: AppTheme.Spacing.verySmall) {
            ForEach(PresentationsFilterChip.flags) { flag in
                flagToggle(flag)
            }
        }
        .fixedSize()
    }

    private func label(for chip: PresentationsFilterChip) -> String {
        let number = count(chip)
        return number > 0 ? "\(chip.title) \(number)" : chip.title
    }

    private func spokenLabel(for chip: PresentationsFilterChip) -> String {
        let number = count(chip)
        guard number > 0 else { return chip.title }
        return "\(chip.title), \(number) \(number == 1 ? "lesson" : "lessons")"
    }

    private func help(for flag: PresentationsFilterChip) -> String {
        switch flag {
        case .overdue: return "Show ready lessons that have waited more than 14 school days"
        case .recentlyMissed: return "Show lessons a child missed by being absent in the last 14 days"
        default: return "Suggest what to present next"
        }
    }

    /// Suggest carries no number: it is a ranking of Ready, always its top few,
    /// so a count would only repeat the limit.
    private func flagToggle(_ flag: PresentationsFilterChip) -> some View {
        let isOn = selection == flag
        let number = flag == .suggestedNext ? 0 : count(flag)
        return Button {
            adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                selection = flag.flagTapped(from: selection)
            }
        } label: {
            HStack(spacing: AppTheme.Spacing.xxsmall) {
                Image(systemName: flag.systemImage)
                    .font(.caption2)
                Text(number > 0 ? "\(flag.title) \(number)" : flag.title)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            .foregroundStyle(isOn ? Color.white : flag.accent)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, AppTheme.Spacing.xsmall)
            .capsuleFill(isOn ? flag.accent : flag.accent.opacity(UIConstants.OpacityConstants.accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Show every ready lesson" : help(for: flag))
        .accessibilityLabel(number > 0 ? "\(flag.title), \(number)" : flag.title)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}
