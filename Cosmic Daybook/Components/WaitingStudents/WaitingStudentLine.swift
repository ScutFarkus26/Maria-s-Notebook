// WaitingStudentLine.swift
// One child in the grouped waiting list: a name on the left, a number on the
// right, and nothing else.
//
// The two-line row with an avatar fit about nine children in the rail, and the
// avatar's color (the child's level) sat next to the urgency color and read
// as more of it. On one line the whole class nearly fits, and the number is
// enough because the group label above it already says what the number means.
// The full sentence is still there for anyone who wants it, as the VoiceOver
// label and as a tooltip on a Mac.

import SwiftUI

struct WaitingStudentLine: View {
    let entry: WaitingStudent
    /// "15", or the vocabulary's words for a child with nothing to count.
    let trailing: String
    /// "15 school days since their last lesson".
    let sentence: String
    /// The overdue color for a child in the long-wait group; `nil` keeps the
    /// number secondary, so color only ever appears where it means something.
    let tint: Color?
    /// What tapping this line does, for VoiceOver.
    let selectionHint: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppTheme.Spacing.small) {
                Text(entry.student.shortName)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: AppTheme.Spacing.small)

                // The number never truncates; a long name gives way to it.
                Text(trailing)
                    .font(AppTheme.SemanticFont.metadata)
                    .monospacedDigit()
                    .foregroundStyle(tint ?? Color.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.vertical, AppTheme.Spacing.xsmall)
            .padding(.horizontal, AppTheme.Spacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(WaitingStudentSelectionBackground(isSelected: isSelected))
        .hoverableRow()
        .help(sentence)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.student.shortName), \(sentence)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(selectionHint)
    }
}
