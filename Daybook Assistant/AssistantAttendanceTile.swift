import SwiftUI

/// One child's tile in the attendance grid. The mark shows in the tile's
/// shape, not in color alone: a solid tile is a child who is here, an outlined
/// one isn't marked yet, a dashed one is absent, and a small corner glyph says
/// late or left early. Tap to mark (what a tap means depends on the phase);
/// long-press for every status, a reason and a note.
///
/// Phones show one line: the shortest name that still tells children apart
/// ("Ari", but "Etty G" and "Etty R": this classroom has two Ettys and two
/// Sarahs), with nothing beside it, so even "Hadassah" keeps its full size and
/// a class of 22 fits three across on one SE screen. The arrival time and an
/// absence reason move to the long-press menu's header. Wider screens keep
/// full names with that detail on a second line.
struct AssistantAttendanceTile: View {
    let row: AssistantAttendanceViewModel.Row
    let phase: AssistantAttendanceViewModel.Phase
    let canMark: Bool
    let usesShortName: Bool
    let onTap: () -> Void
    let onSetStatus: (AttendanceStatus) -> Void
    let onReason: (AbsenceReason) -> Void
    let onNote: () -> Void

    /// A phone tile's height: 8 rows of 22 children fit between the SE's
    /// top bar and the Arrival/Late bar on iOS 26 with the status bar hidden,
    /// with about 20 points to spare.
    static let phoneHeight: CGFloat = 52

    /// Set by a tap that does nothing in this phase (a present child during
    /// Late), so the tile can say why instead of ignoring it.
    @State private var showsHoldHint = false
    @State private var holdHintTaps = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if usesShortName && showsHoldHint {
                Text("Hold to change")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                // A short name stays on one line, shrinking rather than
                // wrapping: one taller tile makes its whole row taller and
                // pushes the last row off the screen.
                Text(usesShortName ? row.shortName : row.student.fullName)
                    .font(.body.weight(.medium))
                    .lineLimit(usesShortName ? 1 : 2)
                    .minimumScaleFactor(usesShortName ? 0.7 : 0.85)
                    .multilineTextAlignment(.leading)
            }

            if !usesShortName {
                detailLine
            }
        }
        .foregroundStyle(nameStyle)
        .frame(
            maxWidth: .infinity,
            minHeight: usesShortName ? Self.phoneHeight : 42,
            alignment: usesShortName ? .leading : .topLeading
        )
        .padding(.horizontal, usesShortName ? 12 : 14)
        .padding(.vertical, usesShortName ? 0 : 12)
        .background(fill, in: shape)
        .overlay { border }
        .overlay(alignment: .topTrailing) { cornerGlyph }
        .overlay(alignment: .bottomTrailing) { phoneNoteGlyph }
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
        .accessibilityLabel("\(row.student.fullName), \(markSummary ?? row.status.displayName)")
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

    /// Wider screens only: when the child arrived, or for an absent child the
    /// reason (the time would only say when Late was switched on), then a
    /// glyph for a note. An unmarked child with no note shows an empty line,
    /// so every tile in a row keeps the same height.
    private var detailLine: some View {
        HStack(spacing: 5) {
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
        .opacity(0.7)
        .lineLimit(1)
    }

    /// Late or left early, in the corner's padding so it takes no room from
    /// the name.
    @ViewBuilder
    private var cornerGlyph: some View {
        if let glyph = Self.cornerGlyph(for: row.status) {
            Image(systemName: glyph)
                .font(.caption2.weight(.bold))
                .foregroundStyle(nameStyle)
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    /// Phones have no detail line, so a note shows in the other corner.
    @ViewBuilder
    private var phoneNoteGlyph: some View {
        if usesShortName && !row.note.isEmpty {
            Image(systemName: "text.alignleft")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(nameStyle.opacity(0.7))
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if canMark {
            // The header carries what the phone tile has no room for: the
            // time the child was marked, or why they're away.
            Section(markSummary ?? "") {
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

    // MARK: - Style

    /// Present, late and left early all mean the child came in.
    private var isHere: Bool {
        switch row.status {
        case .present, .tardy, .leftEarly: return true
        case .absent, .unmarked: return false
        }
    }

    private static func cornerGlyph(for status: AttendanceStatus) -> String? {
        switch status {
        case .tardy: return "clock"
        case .leftEarly: return "arrow.right"
        case .present, .absent, .unmarked: return nil
        }
    }

    /// Black on the solid green in both appearances: system green is light
    /// enough in each that black reads better than white.
    private var nameStyle: Color {
        switch row.status {
        case .present, .tardy, .leftEarly: return .black
        // Dimmed, but readable: during Late these are the tiles she taps
        // when a child comes in.
        case .absent: return Color(.secondaryLabel)
        case .unmarked: return .primary
        }
    }

    private var fill: Color {
        if isHere { return .green }
        if row.status == .absent { return .clear }
        return Color(.secondarySystemGroupedBackground)
    }

    @ViewBuilder
    private var border: some View {
        if row.status == .absent {
            shape.strokeBorder(Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        } else if !isHere {
            shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        }
    }

    // MARK: - Accessibility

    /// "Present at 8:04 AM", "Absent, Sick", or nil while unmarked.
    private var markSummary: String? {
        guard row.status != .unmarked else { return nil }
        var text = row.status.displayName
        if row.status != .absent, let markedAt = row.markedAt {
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
