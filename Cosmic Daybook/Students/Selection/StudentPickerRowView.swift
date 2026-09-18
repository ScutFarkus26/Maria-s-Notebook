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
//

import SwiftUI

struct StudentPickerRowView: View {
    let row: StudentPickerRow
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        if let block = row.block {
            blockedRow(block)
        } else {
            Button(action: onToggle) { selectableRow }
                .buttonStyle(.plain)
        }
    }

    /// A child who has left: listed so the guide can see why she is not on
    /// offer, and not selectable.
    private func blockedRow(_ block: StudentEnrollmentBlock) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.candidate.displayName)
                Text(block.shortReason)
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .disabled(true)
        .accessibilityHint(block.shortReason)
    }

    private var selectableRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.candidate.displayName)
                    .foregroundStyle(.primary)
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

            // The tick keeps its slot when a row is unselected, so the ages stay in a column.
            Image(systemName: "checkmark")
                .foregroundStyle(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(!isSelected)
                .frame(width: 14)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
