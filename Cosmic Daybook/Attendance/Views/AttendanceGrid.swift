import SwiftUI
import CoreData

/// What the roll's cards and tiles do. The expanded view saves after each.
struct AttendanceGridActions {
    /// A tile's tap or a card's click: present during arrival, late after
    /// it closes.
    let tap: (AttendanceRow) -> Void
    let setStatus: (AttendanceStatus, AttendanceRow) -> Void
    let markAbsent: (AbsenceReason, AttendanceRow) -> Void
    let saveNote: (AttendanceRow, String?) -> Void
    /// Leaving Early…: the pickup time on the day on screen, or nil to remove it.
    let savePickup: (AttendanceRow, Date?) -> Void
    /// Back in Class: a child who left early has come back.
    let markBack: (AttendanceRow) -> Void
}

/// The day's roll: tiles in the Daybook Assistant's language on every
/// device. The iPhone draws the Assistant's own (`AttendanceTileGrid`); the
/// Mac and iPad draw `AttendanceCard`, in one block per level when Group by
/// Level is on (and the class has more than one), with the keyboard's
/// selection: arrow keys move it, Space marks as a click does, Delete clears
/// the mark, Escape lets go, and typing a name jumps to that child.
struct AttendanceGrid: View {
    let viewModel: AttendanceViewModel
    /// When false (e.g. the day is locked), cards render read-only and taps no longer mark.
    let isEditing: Bool
    let actions: AttendanceGridActions
    /// A sideways swipe across the iPhone tiles: true for the next school day.
    var onStepDay: ((Bool) -> Void)?

    /// Group by Level, from the View menu; synced across the guide's devices.
    static let groupsByLevelKey = "Attendance.groupsByLevel"
    @SyncedAppStorage(AttendanceGrid.groupsByLevelKey) private var groupsByLevel = true

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var noteRow: AttendanceRow?
    /// The child whose pickup time is being set (Leaving Early…).
    @State private var pickupRow: AttendanceRow?
    /// The child whose attendance history is open.
    @State private var historyRow: AttendanceRow?
    /// The keyboard's selection, by student id.
    @State private var selectedID: UUID?
    @FocusState private var isFocused: Bool
    /// How many tiles fit across, for the up and down arrows.
    @State private var columnCount = 1
    /// Type-to-jump: what's been typed, and when the last key came.
    @State private var typed = ""
    @State private var typedAt = Date.distantPast

    static let minimumTileWidth: CGFloat = 132
    static let spacing: CGFloat = 8

    var body: some View {
        layout
            .sheet(item: $noteRow) { row in
                AttendanceNoteSheet(
                    studentName: row.student.shortName,
                    initialText: row.note,
                    sharedWith: "Anyone you share your classroom with sees this note.",
                    onSave: { actions.saveNote(row, $0) }
                )
            }
            .sheet(item: $pickupRow) { row in
                AttendancePickupSheet(
                    studentName: row.student.shortName,
                    day: viewModel.selectedDate,
                    current: row.leavesAt,
                    suggested: AttendanceRules.suggestedPickup(for: row, on: viewModel.selectedDate),
                    sharedWith: "Anyone you share your classroom with sees this too, "
                        + "and Daybook Assistant reminds them before it.",
                    onSave: { actions.savePickup(row, $0) }
                )
            }
            .sheet(item: $historyRow) { row in
                AttendanceStudentHistorySheet(studentID: row.id)
            }
    }

    /// Leaving Early… for `row`, when this day and its mark allow a pickup time.
    private func pickupAction(_ row: AttendanceRow) -> (() -> Void)? {
        guard isEditing, AttendanceRules.allowsPickup(for: row, on: viewModel.selectedDate) else { return nil }
        return { pickupRow = row }
    }

    /// Back in Class for `row`, when it's marked Left Early.
    private func backAction(_ row: AttendanceRow) -> (() -> Void)? {
        guard isEditing, AttendanceRules.allowsBack(for: row) else { return nil }
        return { actions.markBack(row) }
    }

    @ViewBuilder
    private var layout: some View {
#if os(iOS)
        if hSizeClass == .compact {
            AttendanceTileGrid(
                viewModel: viewModel,
                isEditing: isEditing,
                actions: actions,
                markedBy: markedBy,
                onNote: { noteRow = $0 },
                onPickup: pickupAction,
                onBack: backAction,
                onStepDay: onStepDay
            )
        } else {
            gridLayout
        }
#else
        gridLayout
#endif
    }

    /// Who made a mark, when it wasn't you: an assistant's name. The guide's
    /// own marks carry none.
    private func markedBy(_ row: AttendanceRow) -> String? {
        let name = AttendanceRules.markerName(
            for: row,
            myRecordName: ClassroomIdentity.currentUserRecordName,
            myName: ClassroomIdentity.displayName,
            guideName: "you"
        )
        return name == "you" ? nil : name
    }

    private func card(_ row: AttendanceRow) -> some View {
        AttendanceCard(
            row: row,
            isEditing: isEditing,
            isFuture: viewModel.isFuture,
            isSelected: isFocused && selectedID == row.id,
            markedBy: markedBy(row),
            menuStatuses: viewModel.menuStatuses,
            onTap: {
                selectedID = row.id
                isFocused = true
                actions.tap(row)
            },
            onSetStatus: { actions.setStatus($0, row) },
            onMarkAbsent: { reason in
                actions.markAbsent(reason, row)
                // "Other" is only as good as the note that says what.
                if reason == .other { noteRow = row }
            },
            onNote: { noteRow = row },
            onHistory: { historyRow = row },
            onPickup: pickupAction(row),
            onBack: backAction(row)
        )
    }

    // MARK: - Mac and iPad: tiles by level

    /// One block of tiles, with its level when the roll is grouped.
    private struct Block: Identifiable {
        let level: AttendanceEmailLevel?
        let rows: [AttendanceRow]
        var id: String { level?.rawValue ?? "all" }
    }

    private var blocks: [Block] {
        let rows = viewModel.rows
        guard groupsByLevel else { return [Block(level: nil, rows: rows)] }
        let groups = AttendanceLevelGroups.grouped(rows, level: \.level)
        guard groups.count > 1 else { return [Block(level: nil, rows: rows)] }
        return groups.map { Block(level: $0.level, rows: $0.items) }
    }

    private var gridLayout: some View {
        let blocks = blocks
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(blocks) { block in
                    VStack(alignment: .leading, spacing: Self.spacing) {
                        if let level = block.level {
                            AttendanceLevelHeading(level: level, rows: block.rows, isFuture: viewModel.isFuture)
                        }
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: Self.minimumTileWidth), spacing: Self.spacing)],
                            spacing: Self.spacing
                        ) {
                            ForEach(block.rows) { row in
                                card(row).id(row.id)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, AppTheme.Spacing.small)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                columnCount = max(1, Int((width + Self.spacing) / (Self.minimumTileWidth + Self.spacing)))
            }
        }
        .scrollIndicators(.automatic)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            move(press.key, in: blocks)
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            guard isEditing, let row = selectedRow else { return .ignored }
            actions.tap(row)
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward]) { _ in
            guard isEditing, let row = selectedRow, row.status != .unmarked else { return .ignored }
            actions.setStatus(.unmarked, row)
            return .handled
        }
        .onKeyPress(.escape) {
            guard selectedID != nil else { return .ignored }
            selectedID = nil
            return .handled
        }
        .onKeyPress(characters: .letters, phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
            return jump(typing: press.characters)
        }
        .onChange(of: viewModel.selectedDate) { selectedID = nil }
        .accessibilityRotor("Students") {
            ForEach(viewModel.rows) { row in
                AccessibilityRotorEntry(row.name, id: row.id)
            }
        }
    }

    // MARK: - Keyboard

    private var selectedRow: AttendanceRow? {
        selectedID.flatMap { id in viewModel.rows.first { $0.id == id } }
    }

    /// Arrow keys: left and right through the roll in order, up and down a
    /// line, keeping the column, across the level blocks.
    private func move(_ key: KeyEquivalent, in blocks: [Block]) -> KeyPress.Result {
        let lines = blocks.flatMap { block in
            stride(from: 0, to: block.rows.count, by: columnCount).map {
                block.rows[$0..<min($0 + columnCount, block.rows.count)].map(\.id)
            }
        }
        let order = lines.flatMap(\.self)
        guard let first = order.first else { return .ignored }
        guard let current = selectedID,
              let lineIndex = lines.firstIndex(where: { $0.contains(current) }),
              let column = lines[lineIndex].firstIndex(of: current),
              let position = order.firstIndex(of: current) else {
            selectedID = first
            return .handled
        }
        switch key {
        case .leftArrow: selectedID = order[max(position - 1, 0)]
        case .rightArrow: selectedID = order[min(position + 1, order.count - 1)]
        case .upArrow where lineIndex > 0:
            selectedID = lines[lineIndex - 1][min(column, lines[lineIndex - 1].count - 1)]
        case .downArrow where lineIndex < lines.count - 1:
            selectedID = lines[lineIndex + 1][min(column, lines[lineIndex + 1].count - 1)]
        default: break
        }
        return .handled
    }

    /// Type-to-jump, as in a Finder list: letters typed within a second of
    /// each other build a name, and the first child whose name starts with
    /// it is selected.
    private func jump(typing characters: String) -> KeyPress.Result {
        let now = Date()
        typed = now.timeIntervalSince(typedAt) < 1 ? typed + characters : characters
        typedAt = now
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
        guard let match = viewModel.rows.first(where: {
            $0.student.shortName.range(of: typed, options: options) != nil
                || $0.name.range(of: typed, options: options) != nil
        }) else { return .handled }
        selectedID = match.id
        return .handled
    }
}

/// A level block's heading on the Mac and iPad: "Upper Elementary" and how
/// many of them are in the room ("12 of 16 here"), or just how many on a day
/// ahead.
private struct AttendanceLevelHeading: View {
    let level: AttendanceEmailLevel
    let rows: [AttendanceRow]
    let isFuture: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(level.title)
                .font(.subheadline.weight(.semibold))
            Text(isFuture ? "\(rows.count)" : "\(rows.count(where: \.isInRoom)) of \(rows.count) here")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
