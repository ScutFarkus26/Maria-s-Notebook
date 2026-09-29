import SwiftUI

/// One child's tile in the attendance grid: name, a soft wash of the mark's
/// colour with its glyph (so the mark never rests on colour alone), and the
/// time the child arrived. Tap to mark (what a tap means depends on the
/// phase); long-press for every status, a reason and a note.
///
/// Phones show the shortest name that still tells children apart ("Ari", but
/// "Etty G" and "Etty R": this classroom has two Ettys and two Sarahs) so a
/// class of 22 fits three across on one screen.
struct AssistantAttendanceTile: View {
    let row: AssistantAttendanceViewModel.Row
    let phase: AssistantAttendanceViewModel.Phase
    let canMark: Bool
    let usesShortName: Bool
    let onTap: () -> Void
    let onSetStatus: (AttendanceStatus) -> Void
    let onReason: (AbsenceReason) -> Void
    let onNote: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// Set by a tap that does nothing in this phase (a present child during
    /// Late), so the tile can say why instead of ignoring it.
    @State private var showsHoldHint = false
    @State private var holdHintTaps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // A short name stays on one line, shrinking rather than wrapping:
            // one taller tile makes its whole row taller and pushes the last
            // row off the screen.
            Text(usesShortName ? row.shortName : row.student.fullName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(usesShortName ? 1 : 2)
                .minimumScaleFactor(usesShortName ? 0.7 : 0.85)
                .multilineTextAlignment(.leading)

            detailLine
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(fill, in: shape)
        .overlay(shape.strokeBorder(stroke, lineWidth: 1))
        .contentShape(shape)
        .onTapGesture(perform: tap)
        .contextMenu { menu }
        .animation(.smooth(duration: 0.25), value: row.status)
        .animation(.smooth(duration: 0.2), value: showsHoldHint)
        .sensoryFeedback(.selection, trigger: row.status)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: holdHintTaps)
        .task(id: holdHintTaps) {
            guard showsHoldHint, (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
            showsHoldHint = false
        }
        .onChange(of: row.status) { showsHoldHint = false }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(row.note)
        .accessibilityHint(canMark ? tapHint : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if canMark { onTap() } }
        .accessibilityAction(named: "Note", onNote)
    }

    private func tap() {
        guard canMark else { return }
        if AssistantAttendanceViewModel.statusAfterTap(from: row.status, in: phase) == nil {
            showsHoldHint = true
            holdHintTaps += 1
        } else {
            onTap()
        }
    }

    // MARK: - Pieces

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    /// The mark's glyph, then when the child arrived, or for an absent child
    /// the reason (the time would only say when Late was switched on), then a
    /// glyph for a note. An unmarked child with no note shows an empty line,
    /// so every tile in a row keeps the same height.
    private var detailLine: some View {
        HStack(spacing: 5) {
            if let glyph, let hue, !showsHoldHint {
                Image(systemName: glyph)
                    .fontWeight(.bold)
                    .foregroundStyle(hue)
            }
            if showsHoldHint {
                Text("Hold to change")
            } else {
                switch row.status {
                case .absent where row.absenceReason != .none:
                    Label(row.absenceReason.displayName, systemImage: row.absenceReason.icon)
                        .labelStyle(.titleAndIcon)
                        .imageScale(.small)
                case .absent:
                    Text("Absent")
                case .unmarked:
                    Text(" ")
                default:
                    if let markedAt = row.markedAt {
                        Text(markedAt, format: .dateTime.hour().minute())
                            .monospacedDigit()
                    } else {
                        Text(" ")
                    }
                }
                if !row.note.isEmpty {
                    Image(systemName: "text.alignleft")
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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

    /// The status's shape, beside its hue, or nil while unmarked.
    private var glyph: String? {
        switch row.status {
        case .unmarked: return nil
        case .present: return "checkmark"
        case .absent: return "xmark"
        case .tardy: return "clock"
        case .leftEarly: return "arrow.right"
        }
    }

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
        default: return "Touch and hold to change the mark"
        }
    }
}
