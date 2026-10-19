// ClassGridShared.swift
// Pieces drawn in more than one place: a column's angled name, Three Years'
// key, and the marks' short key the child's own Three-Year View shows.

import SwiftUI

/// A column's name in the header, angled up and to the right, as the Checklist's
/// are. Opens the child.
struct ClassGridAngledName: View {
    let name: String
    let help: String
    let studentID: UUID?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Button {
            if let studentID { AppRouter.shared.requestOpenStudentDetail(studentID) }
        } label: {
            ChecklistHeaderName(studentID: studentID, name: name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 96, alignment: .leading)
                .rotationEffect(.degrees(-55), anchor: .bottomLeading)
                .offset(x: width * 0.42, y: -8)
                .frame(width: width, height: height, alignment: .bottomLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityHint("Opens the child's record")
    }
}

/// Three Years' key: the five marks it draws and the three recall rings.
struct ClassGridYearsLegend: View {
    /// The line at the key's end ("Click a mark…"); none on the iPhone, where
    /// the key scrolls sideways.
    let hint: String?

    var body: some View {
        HStack(spacing: 16) {
            item(.notReady, nil, "Not yet")
            item(.presented, nil, "Presented")
            item(.practicing, nil, "Practicing")
            item(.reviewing, nil, "Reviewing")
            item(.mastered, nil, "Mastered")
            item(.mastered, .retained, "Still has it")
            item(.mastered, .shaky, "Shaky")
            item(.reviewing, .forgotten, "Forgotten")
            if let hint {
                Spacer(minLength: 8)
                Text(hint)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
        }
        .font(.caption)
        .padding(.leading, 12)
        .padding(.trailing, hint == nil ? 12 : 92)
        .frame(height: ChecklistStatusBar.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Key: dot not yet, quarter filled presented, half practicing, three quarters reviewing, "
                + "green with a check mastered. A ring is the latest recall check: green still has it, "
                + "dashed orange shaky, dotted red forgotten."
        )
    }

    private func item(_ status: ChecklistDisplayStatus, _ recall: RecallOutcome?, _ label: String) -> some View {
        HStack(spacing: 6) {
            ChecklistMark(status: status, recall: recall, size: 13)
                .frame(width: 20)
            Text(label)
        }
        .fixedSize()
    }
}

/// The marks' key in one short line, for the child's own Three-Year View on her page:
/// the five rungs it draws and the recall ring.
struct ClassGridMarksLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(ClassGridYearsView.filterStates, id: \.self) { status in
                HStack(spacing: 4) {
                    ChecklistMark(status: status, size: 10)
                    Text(ClassGridYearsView.filterTitle(status))
                }
            }
            HStack(spacing: 4) {
                ChecklistMark(status: .mastered, recall: .shaky, size: 10)
                    .padding(.horizontal, 2)
                Text("Recall ring")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Key: dot not yet, quarter filled presented, half practicing, three quarters reviewing, "
                + "green with a check mastered; a ring is the latest recall check"
        )
    }
}
