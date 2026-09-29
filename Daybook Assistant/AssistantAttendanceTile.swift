import SwiftUI

/// One child's tile in the attendance grid. The mark shows in the tile's
/// shape, not in color alone: a solid tile is a child who is here, an outlined
/// one isn't marked yet, a dashed one is absent, and a small corner glyph says
/// late or left early. Tap to mark (what a tap means depends on the phase and
/// the day); long-press for every status, Absent with its reason, and a note.
/// A child with a note shows it, in full, above that menu.
///
/// Phones show the shortest name that still tells children apart ("Ari", but
/// "Etty G" and "Etty R": this classroom has two Ettys and two Sarahs). On an
/// SE that is one line with nothing beside it, so even "Hadassah" keeps its
/// full size and a class of 22 fits three across on one screen; the time, an
/// absence reason and who made the mark move to the long-press menu's header.
/// A taller phone grows its tiles to fill the screen (`fittedPhoneHeight`),
/// and once they are `roomyHeight` tall the name gets bigger and the time or
/// reason comes back on a second line. Wider screens keep full names with that
/// detail line. At accessibility text sizes the grid goes to two columns and a
/// name may wrap.
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
    /// A phone tile's height, from `fittedPhoneHeight`; unused on wider
    /// screens.
    let height: CGFloat
    let onTap: () -> Void
    /// Who made the mark ("you", "Rivka", "your guide"), for the menu header.
    let markedBy: String?
    let onSetStatus: (AttendanceStatus) -> Void
    /// Absent with a reason (`.none` for no reason), in one step.
    let onMarkAbsent: (AbsenceReason) -> Void
    let onNote: () -> Void

    /// A phone tile's height on an SE, and the least on any phone: 8 rows of
    /// 22 children fit between the SE's top bar and the bottom bar on iOS 26
    /// with the status bar hidden.
    static let phoneHeight: CGFloat = 52
    /// The most a phone tile grows to, so a small class doesn't get slabs.
    static let tallestPhoneHeight: CGFloat = 84
    /// Tall enough for a bigger name and the detail line under it.
    static let roomyHeight: CGFloat = 70

    /// The phone tile height that fills `visibleHeight` with the class, in
    /// whole points, between `phoneHeight` (a longer class scrolls) and
    /// `tallestPhoneHeight`.
    static func fittedPhoneHeight(visibleHeight: CGFloat, columns: Int, count: Int, spacing: CGFloat) -> CGFloat {
        guard columns > 0, count > 0 else { return phoneHeight }
        let rows = (count + columns - 1) / columns
        let fitted = ((visibleHeight - spacing * CGFloat(rows - 1)) / CGFloat(rows)).rounded(.down)
        return min(max(fitted, phoneHeight), tallestPhoneHeight)
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Set by a tap that does nothing here (a present child during Late, any
    /// tap on a day ahead), so the tile can say why instead of ignoring it.
    @State private var showsHoldHint = false
    @State private var holdHintTaps = 0
    /// Bumped by her own taps and menu picks, so the tick answers her touch
    /// and never a mark arriving from another device or a change of day.
    @State private var markTaps = 0

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

    /// A phone tile with room for a bigger name and the detail line.
    private var isRoomy: Bool { usesShortName && !isLargeText && height >= Self.roomyHeight }

    /// One-line phone tiles: no detail line, so the hint and a note glyph
    /// take the name's line and a corner instead.
    private var isOneLine: Bool { usesShortName && !isRoomy }

    var body: some View {
        cardWithMenu
            .onTapGesture(perform: tap)
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

    /// The name (and, on wider screens and roomy phone tiles, the detail
    /// line) on the mark's shape.
    private var card: some View {
        VStack(alignment: .leading, spacing: isRoomy ? 2 : 4) {
            if isOneLine && showsHoldHint {
                Text(tapHint)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                // A short name stays on one line, shrinking rather than
                // wrapping: one taller tile makes its whole row taller.
                Text(usesShortName ? row.shortName : row.name)
                    .font(isRoomy ? .title3.weight(.medium) : .body.weight(.medium))
                    .lineLimit(usesShortName && !isLargeText ? 1 : 2)
                    .minimumScaleFactor(usesShortName ? 0.7 : 0.85)
                    .multilineTextAlignment(.leading)
            }

            // A roomy phone tile has a fixed height, so it needn't hold an
            // empty line to match its row: the name alone sits centered.
            if !isOneLine && !(isRoomy && !hasDetail) {
                detailLine
            }
        }
        .foregroundStyle(nameStyle)
        .frame(
            maxWidth: .infinity,
            minHeight: usesShortName ? height : 42,
            alignment: usesShortName ? .leading : .topLeading
        )
        .padding(.horizontal, usesShortName ? 12 : 14)
        .padding(.vertical, usesShortName ? 0 : 12)
        .background(fill, in: shape)
        .overlay { border }
        .overlay(alignment: .topTrailing) { cornerGlyph }
        .overlay(alignment: .bottomTrailing) { phoneNoteGlyph }
    }

    /// The long-press menu, with the note on top when there is one.
    @ViewBuilder
    private var cardWithMenu: some View {
        if row.note.isEmpty {
            card
                .contentShape(shape)
                .contextMenu { menu }
        } else {
            card
                .contentShape(shape)
                .contextMenu { menu } preview: { notePreview }
        }
    }

    /// The child's full name and the note, readable at a glance where the
    /// tile only shows that one exists.
    private var notePreview: some View {
        // Each line takes its full wrapped height: the preview otherwise
        // gets the tile's height and shows one line of the note.
        VStack(alignment: .leading, spacing: 6) {
            Text(row.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(row.note)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
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

    var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    /// Wider screens and roomy phone tiles: when the child arrived ("8:02 →
    /// 1:15" for Left Early), or for an absent child the reason, then a glyph
    /// for a note. A roomy tile starts it with the mark's glyph. On wider
    /// screens an unmarked child with no note shows an empty line, so every
    /// tile in a row keeps the same height.
    private var detailLine: some View {
        HStack(spacing: 5) {
            if showsHoldHint {
                Text(tapHint)
            } else {
                // A roomy phone tile leads with the mark's glyph, which the
                // one-line SE tile has no room for.
                if isRoomy, let glyph = Self.tileGlyph(for: row.status) {
                    Image(systemName: glyph)
                        .fontWeight(.semibold)
                }
                switch row.status {
                case .absent where row.absenceReason != .none:
                    Text(row.absenceReason.displayName)
                case .absent:
                    Text("Absent")
                case .unmarked:
                    // Holds a wider screen's row height; a roomy tile only
                    // gets here with a note, whose glyph starts the line.
                    if !isRoomy { Text(" ") }
                case .leftEarly:
                    Text(leftEarlyTimes ?? "Left early")
                        .monospacedDigit()
                default:
                    Text(row.markedAt.map(Self.clock) ?? (isRoomy ? row.status.displayName : " "))
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

    /// Whether the detail line has anything to say: on a roomy tile, any
    /// mark does (its glyph, at least).
    private var hasDetail: Bool {
        showsHoldHint || !row.note.isEmpty || row.status != .unmarked
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
    /// the name. A roomy tile has the glyph on its detail line instead.
    @ViewBuilder
    private var cornerGlyph: some View {
        if !isRoomy, let glyph = Self.cornerGlyph(for: row.status) {
            Image(systemName: glyph)
                .font(.caption2.weight(.bold))
                .foregroundStyle(nameStyle)
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    /// One-line tiles have no detail line, so a note shows in the other
    /// corner.
    @ViewBuilder
    private var phoneNoteGlyph: some View {
        if isOneLine && !row.note.isEmpty {
            Image(systemName: "text.alignleft")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(nameStyle.opacity(0.7))
                .padding(6)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Menu and accessibility

extension AssistantAttendanceTile {

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
