import SwiftUI

/// One child's tile in the attendance grid. The mark shows in the tile's
/// shape, not in color alone: a solid tile is a child who is here, an outlined
/// one isn't marked yet, a dashed one is absent, and a small corner glyph says
/// late or left early. Tap to mark (what a tap means depends on the phase and
/// the day); long-press for every status, Absent with its reason, and a note.
///
/// Phones show one line: the shortest name that still tells children apart
/// ("Ari", but "Etty G" and "Etty R": this classroom has two Ettys and two
/// Sarahs), with nothing beside it, so even "Hadassah" keeps its full size and
/// a class of 22 fits three across on one SE screen. The time, an absence
/// reason and who made the mark move to the long-press menu's header. Wider
/// screens keep full names with that detail on a second line. At
/// accessibility text sizes the grid goes to two columns and a name may wrap.
struct AssistantAttendanceTile: View {
    let row: AssistantAttendanceViewModel.Row
    /// What a tap would set, or nil when a tap does nothing here.
    let tapTarget: AttendanceStatus?
    /// Why a tap does nothing, shown briefly on the tile.
    let tapHint: String
    /// The statuses the long-press menu offers.
    let menuStatuses: [AttendanceStatus]
    let canMark: Bool
    let usesShortName: Bool
    let onTap: () -> Void
    /// Who made the mark ("you", "Rivka", "your guide"), for the menu header.
    let markedBy: String?
    let onSetStatus: (AttendanceStatus) -> Void
    /// Absent with a reason (`.none` for no reason), in one step.
    let onMarkAbsent: (AbsenceReason) -> Void
    let onNote: () -> Void

    /// A phone tile's height: 8 rows of 22 children fit between the SE's
    /// top bar and the bottom bar on iOS 26 with the status bar hidden.
    static let phoneHeight: CGFloat = 52

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Set by a tap that does nothing here (a present child during Late, any
    /// tap on a day ahead), so the tile can say why instead of ignoring it.
    @State private var showsHoldHint = false
    @State private var holdHintTaps = 0
    /// Bumped by her own taps and menu picks, so the tick answers her touch
    /// and never a mark arriving from another device or a change of day.
    @State private var markTaps = 0

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        card
            .contentShape(shape)
            .onTapGesture(perform: tap)
            .contextMenu { menu }
            .animation(.smooth(duration: 0.25), value: row.status)
            .animation(.smooth(duration: 0.2), value: showsHoldHint)
            .sensoryFeedback(.selection, trigger: markTaps)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: holdHintTaps)
            .task(id: holdHintTaps) {
                guard showsHoldHint, (try? await Task.sleep(for: .seconds(2.5))) != nil else { return }
                showsHoldHint = false
            }
            .onChange(of: row.status) { showsHoldHint = false }
            .modifier(TileAccessibility(
                label: "\(row.name), \(markSummary ?? row.status.displayName)",
                note: row.note,
                hint: canMark ? voiceOverHint : "",
                onTap: { if canMark { onTap() } },
                onNote: onNote
            ))
    }

    /// The name (and, on wider screens, the detail line) on the mark's shape.
    private var card: some View {
        VStack(alignment: .leading, spacing: 4) {
            if usesShortName && showsHoldHint {
                Text(tapHint)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                // A short name stays on one line, shrinking rather than
                // wrapping: one taller tile makes its whole row taller.
                Text(usesShortName ? row.shortName : row.name)
                    .font(.body.weight(.medium))
                    .lineLimit(usesShortName && !isLargeText ? 1 : 2)
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
    }

    private func tap() {
        guard canMark else { return }
        if tapTarget == nil {
            showsHoldHint = true
            holdHintTaps += 1
        } else {
            markTaps += 1
            onTap()
        }
    }

    // MARK: - Pieces

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    /// Wider screens only: when the child arrived ("8:02 → 1:15" for Left
    /// Early), or for an absent child the reason, then a glyph for a note. An
    /// unmarked child with no note shows an empty line, so every tile in a row
    /// keeps the same height.
    private var detailLine: some View {
        HStack(spacing: 5) {
            if showsHoldHint {
                Text(tapHint)
            } else {
                switch row.status {
                case .absent where row.absenceReason != .none:
                    Text(row.absenceReason.displayName)
                case .absent:
                    Text("Absent")
                case .unmarked:
                    Text(" ")
                case .leftEarly:
                    Text(leftEarlyTimes ?? "Left early")
                        .monospacedDigit()
                default:
                    Text(row.markedAt.map(Self.clock) ?? " ")
                        .monospacedDigit()
                }
                if !row.note.isEmpty {
                    Image(systemName: "text.alignleft")
                }
            }
        }
        .font(.caption)
        .opacity(0.7)
        .lineLimit(isLargeText ? 2 : 1)
        .minimumScaleFactor(0.8)
    }

    /// "8:02 → 1:15", "left 1:15", or nil when neither time is known.
    private var leftEarlyTimes: String? {
        switch (row.markedAt, row.leftAt) {
        case let (arrived?, left?): return "\(Self.clock(arrived)) → \(Self.clock(left))"
        case let (nil, left?): return "left \(Self.clock(left))"
        default: return nil
        }
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

    // MARK: - Menu

    /// The header carries what the phone tile has no room for ("Present at
    /// 8:02 · by you", "Absent, Sick · by your guide"). Then Present, Tardy and
    /// Left Early; Absent with its reasons in one step; clearing; the note.
    /// The current choice wears a checkmark in place of its glyph. Ahead of
    /// the day only Absent and clearing are offered.
    @ViewBuilder
    private var menu: some View {
        if canMark {
            Section {
                ForEach(menuStatuses.filter { $0 != .absent && $0 != .unmarked }, id: \.self) { status in
                    Button {
                        markTaps += 1
                        onSetStatus(status)
                    } label: {
                        Label(status.displayName, systemImage: status == row.status ? "checkmark" : Self.glyph(status))
                    }
                }
                if menuStatuses.contains(.absent) {
                    absentMenu
                }
            } header: {
                if let menuHeader { Text(menuHeader) }
            }
            if row.status != .unmarked, menuStatuses.contains(.unmarked) {
                Button("Clear Mark", systemImage: "circle.dashed") {
                    markTaps += 1
                    onSetStatus(.unmarked)
                }
            }
            Button(row.note.isEmpty ? "Add Note" : "Edit Note", systemImage: "text.alignleft", action: onNote)
        }
    }

    private var menuHeader: String? {
        guard let markSummary else { return nil }
        return markedBy.map { "\(markSummary) · by \($0)" } ?? markSummary
    }

    /// Absent, then why. "Other…" goes on to the note, which says what.
    private var absentMenu: some View {
        Menu {
            absentChoice(.none, title: "No Reason", systemImage: "xmark")
            ForEach(AbsenceReason.given, id: \.self) { reason in
                absentChoice(
                    reason,
                    title: reason == .other ? "Other…" : reason.displayName,
                    systemImage: reason.icon
                )
            }
        } label: {
            Label("Absent", systemImage: row.status == .absent ? "checkmark" : "xmark")
        }
    }

    private func absentChoice(_ reason: AbsenceReason, title: String, systemImage: String) -> some View {
        let isCurrent = row.status == .absent && row.absenceReason == reason
        return Button {
            markTaps += 1
            onMarkAbsent(reason)
        } label: {
            Label(title, systemImage: isCurrent ? "checkmark" : systemImage)
        }
    }

    // MARK: - Accessibility

    /// "Present at 8:04", "Left Early 8:02 → 1:15", "Absent, Sick", or nil
    /// while unmarked. Marks made on another day carry no time.
    private var markSummary: String? {
        guard row.status != .unmarked else { return nil }
        var text = row.status.displayName
        switch row.status {
        case .absent where row.absenceReason != .none:
            text += ", \(row.absenceReason.displayName)"
        case .leftEarly:
            if let arrived = row.markedAt, let left = row.leftAt {
                text += " \(Self.clock(arrived)) → \(Self.clock(left))"
            } else if let left = row.leftAt {
                text += " at \(Self.clock(left))"
            }
        case .present, .tardy:
            if let markedAt = row.markedAt { text += " at \(Self.clock(markedAt))" }
        default:
            break
        }
        return text
    }

    private var voiceOverHint: String {
        switch tapTarget {
        case .present: return "Double tap to mark present"
        case .tardy: return "Double tap to mark tardy"
        case .absent: return "Double tap to mark absent again"
        case .unmarked: return "Double tap to clear the mark"
        default: return "\(tapHint). Touch and hold to change the mark"
        }
    }
}

// MARK: - Style and times

extension AssistantAttendanceTile {

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

    /// A status's glyph in the long-press menu.
    static func glyph(_ status: AttendanceStatus) -> String {
        switch status {
        case .unmarked: return "circle.dashed"
        // Not a checkmark: that marks the current choice in the menu.
        case .present: return "figure.walk.arrival"
        case .absent: return "xmark"
        case .tardy: return "clock"
        case .leftEarly: return "arrow.right"
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

    // MARK: - Times

    /// "8:02", not "8:02 AM": it's always the school day, and the header and
    /// the detail line need the width for an arrival and a departure.
    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    /// The locale's own hour-and-minute pattern ("h:mm a", "HH:mm") without
    /// its AM/PM marker. (`hour(.defaultDigits(amPM: .omitted))` pads the
    /// hour to "08:02" on iOS 26.)
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current) ?? "h:mm"
        formatter.dateFormat = pattern.replacingOccurrences(of: "a", with: "").trimmingCharacters(in: .whitespaces)
        return formatter
    }()
}

/// One VoiceOver element per tile: its label, the note as its value, a tap
/// that marks, and a Note action.
private struct TileAccessibility: ViewModifier {
    let label: String
    let note: String
    let hint: String
    let onTap: () -> Void
    let onNote: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(note)
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "Note", onNote)
    }
}
