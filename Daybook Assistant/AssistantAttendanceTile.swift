import SwiftUI

/// One child's tile in the attendance grid: full name, a soft wash of the
/// mark's colour, and the time it was made. Tap to mark (what a tap means
/// depends on the phase); long-press for every status, a reason and a note.
///
/// Full names throughout, deliberately. This classroom has two Ettys and two
/// Sarahs, and a first name alone would be a coin flip.
struct AssistantAttendanceTile: View {
    let row: AssistantAttendanceViewModel.Row
    let phase: AssistantAttendanceViewModel.Phase
    let canMark: Bool
    let onTap: () -> Void
    let onSetStatus: (AttendanceStatus) -> Void
    let onReason: (AbsenceReason) -> Void
    let onNote: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.student.fullName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)

            detailLine
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(fill, in: shape)
        .overlay(shape.strokeBorder(stroke, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture { if canMark { onTap() } }
        .contextMenu { menu }
        .animation(.smooth(duration: 0.25), value: row.status)
        .sensoryFeedback(.selection, trigger: row.status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(row.note)
        .accessibilityHint(canMark ? tapHint : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if canMark { onTap() } }
        .accessibilityAction(named: "Note", onNote)
    }

    // MARK: - Pieces

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    /// The mark's time, then small glyphs for a reason and a note. An
    /// unmarked child with neither shows an empty line, so every tile in a
    /// row keeps the same height.
    private var detailLine: some View {
        HStack(spacing: 6) {
            if let markedAt = row.markedAt {
                Text(markedAt, format: .dateTime.hour().minute())
                    .monospacedDigit()
                    .foregroundStyle(hue ?? .secondary)
            } else {
                Text(" ")
            }
            if row.status == .absent, row.absenceReason != .none {
                Image(systemName: row.absenceReason.icon)
            }
            if !row.note.isEmpty {
                Image(systemName: "text.alignleft")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var menu: some View {
        if canMark {
            Section {
                ForEach(Self.menuStatuses, id: \.self) { status in
                    Button {
                        onSetStatus(status)
                    } label: {
                        if status == row.status {
                            Label(status.displayName, systemImage: "checkmark")
                        } else {
                            Text(status.displayName)
                        }
                    }
                }
            }
            if row.status == .absent {
                Menu("Reason") {
                    ForEach(AbsenceReason.allCases, id: \.self) { reason in
                        Button(reason == .none ? "No Reason" : reason.displayName) { onReason(reason) }
                    }
                }
            }
            Button(row.note.isEmpty ? "Add Note" : "Edit Note", systemImage: "text.alignleft", action: onNote)
        }
    }

    private static let menuStatuses: [AttendanceStatus] = [.present, .absent, .tardy, .leftEarly, .unmarked]

    // MARK: - Colour

    /// The status's hue, or nil while unmarked.
    private var hue: Color? {
        switch row.status {
        case .unmarked: return nil
        case .present: return .green
        case .absent: return .red
        case .tardy: return .blue
        case .leftEarly: return .purple
        }
    }

    private var fill: Color {
        guard let hue else { return Color(.secondarySystemGroupedBackground) }
        return hue.opacity(colorScheme == .dark ? 0.24 : 0.14)
    }

    private var stroke: Color {
        guard let hue else { return Color.primary.opacity(0.06) }
        return hue.opacity(colorScheme == .dark ? 0.45 : 0.35)
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        var text = "\(row.student.fullName), \(row.status.displayName)"
        if let markedAt = row.markedAt {
            text += " at \(markedAt.formatted(date: .omitted, time: .shortened))"
        }
        if row.status == .absent, row.absenceReason != .none {
            text += ", \(row.absenceReason.displayName)"
        }
        return text
    }

    private var tapHint: String {
        switch AssistantAttendanceViewModel.statusAfterTap(from: row.status, in: phase) {
        case .present: return "Double tap to mark present"
        case .tardy: return "Double tap to mark tardy"
        case .absent: return "Double tap to mark absent again"
        case .unmarked: return "Double tap to clear the mark"
        default: return "Touch and hold for more"
        }
    }
}
