import SwiftUI

/// One student's row: full name, current mark, and — when absent — a reason.
///
/// Full names throughout, deliberately. This classroom has two Ettys and two
/// Sarahs, and a first name alone would be a coin flip.
struct AssistantAttendanceRow: View {
    let row: AssistantAttendanceViewModel.Row
    let canMark: Bool
    let onCycle: () -> Void
    let onReason: (AbsenceReason) -> Void

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.student.fullName), \(row.status.displayName)")
        .accessibilityHint(canMark ? "Double tap to change" : "")
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
