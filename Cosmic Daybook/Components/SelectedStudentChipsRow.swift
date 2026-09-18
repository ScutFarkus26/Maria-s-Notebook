// SelectedStudentChipsRow.swift
// Shared horizontal row of selected-student chips with remove buttons.
// Used by UnifiedNoteEditor and TodoEditSheet; the label, font, and text
// color are parameterized so each call site keeps its established look.

import SwiftUI
import CoreData

struct SelectedStudentChipsRow: View {
    let students: [CDStudent]
    var label: (CDStudent) -> String = { StudentFormatter.displayName(for: $0) }
    var font: Font = AppTheme.ScaledFont.caption.weight(.medium)
    var textColor: Color = .primary
    let onRemove: (CDStudent) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.small) {
                ForEach(students, id: \.objectID) { student in
                    chip(for: student)
                }
            }
            .padding(.vertical, AppTheme.Spacing.xxsmall)
        }
    }

    private func chip(for student: CDStudent) -> some View {
        let name = label(student)
        return HStack(spacing: AppTheme.Spacing.xsmall) {
            Text(name)
                .font(font)
            Button {
                onRemove(student)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.scaledRounded(.caption2, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Remove \(name)")
        }
        .padding(.horizontal, AppTheme.Spacing.small + AppTheme.Spacing.xxsmall)
        .padding(.vertical, AppTheme.Spacing.verySmall)
        .foregroundStyle(textColor)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.accent))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), selected")
        .accessibilityHint("Contains remove button")
    }
}
