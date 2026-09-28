import SwiftUI

/// One student's row: full name, current mark, the day's note, and — when
/// absent — a reason. Swipe or long-press for the note.
///
/// Full names throughout, deliberately. This classroom has two Ettys and two
/// Sarahs, and a first name alone would be a coin flip.
struct AssistantAttendanceRow: View {
    let row: AssistantAttendanceViewModel.Row
    let canMark: Bool
    let onCycle: () -> Void
    let onReason: (AbsenceReason) -> Void
    let onNote: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.student.fullName)
                    .font(.body)

                if row.status == .absent, row.absenceReason != .none {
                    Label(row.absenceReason.displayName, systemImage: row.absenceReason.icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !row.note.isEmpty {
                    Label(row.note, systemImage: "note.text")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if row.status == .absent, canMark {
                Menu {
                    ForEach(AbsenceReason.allCases, id: \.self) { reason in
                        Button(reason == .none ? "No reason" : reason.displayName) {
                            onReason(reason)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            statusChip
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { if canMark { onCycle() } }
        .swipeActions(edge: .trailing) {
            if canMark {
                Button("Note", systemImage: "note.text", action: onNote)
                    .tint(.indigo)
            }
        }
        .contextMenu {
            if canMark {
                Button(row.note.isEmpty ? "Add Note" : "Edit Note", systemImage: "note.text", action: onNote)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.student.fullName), \(row.status.displayName)")
        .accessibilityValue(row.note)
        .accessibilityHint(canMark ? "Double tap to change" : "")
        .accessibilityAction(named: "Note", onNote)
    }

    private var statusChip: some View {
        Text(row.status.displayName)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(row.status.color, in: Capsule())
            .foregroundStyle(row.status == .unmarked ? .secondary : .primary)
    }
}
