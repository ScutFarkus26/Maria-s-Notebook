//
//  StudentPickerRowView.swift
//  Cosmic Daybook
//
//  One line of the roster popover: her name, what the record holds for her on
//  this lesson, her age, and the tick.
//
//  A child who has left the classroom renders as the same row in grey, with
//  the reason where the record caption would be and no tick at all, so a
//  withdrawal reads as a fact about her rather than as a gap in the list.
//  If she is still ticked (the presentation named her before she left), the
//  tick shows and a tap takes her off: `StudentPickerModel.toggling` allows
//  that, and the row used to be disabled outright (bug hunt 2026-10-12 #56).
//
//  A child ready for the picker's lesson carries a small green "Ready" tag
//  beside her name, in the Groups page's ready color, so the tag still reads
//  when a search mixes the runs.
//

import SwiftUI

struct StudentPickerRowView: View {
    let row: StudentPickerRow
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        if let block = row.block {
            if isSelected {
                Button(action: onToggle) { blockedRow(block) }
                    .buttonStyle(.plain)
                    .accessibilityHint("Takes \(row.candidate.displayName) off. \(block.shortReason)")
            } else {
                blockedRow(block)
                    .disabled(true)
                    .accessibilityHint(block.shortReason)
            }
        } else {
            Button(action: onToggle) { selectableRow }
                .buttonStyle(.plain)
        }
    }

    /// A child who has left: listed so the guide can see why she is not on
    /// offer. Never selectable; the tick shows only while she is still ticked.
    private func blockedRow(_ block: StudentEnrollmentBlock) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.candidate.displayName)
                Text(block.shortReason)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            tick
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var selectableRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.candidate.displayName)
                        .foregroundStyle(.primary)
                    if row.isReady {
                        readyTag
                    }
                }
                if let given = row.record {
                    StudentRecordCaption(given: given)
                }
            }

            Spacer(minLength: 8)

            if let birthday = row.candidate.birthday {
                Text(AgeUtils.quarterGlyphAgeString(for: birthday))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(AgeUtils.verboseQuarterAgeString(for: birthday))
            }

            tick
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    /// "Ready" in the ready queue's green: the Groups page's word and color.
    private var readyTag: some View {
        Text("Ready")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppColors.success)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(AppColors.success.opacity(0.15)))
            .accessibilityLabel("Ready for this lesson")
    }

    /// The tick keeps its slot when a row is unselected, so the ages stay in a column.
    private var tick: some View {
        Image(systemName: "checkmark")
            .foregroundStyle(Color.accentColor)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(!isSelected)
            .frame(width: 14)
    }
}
