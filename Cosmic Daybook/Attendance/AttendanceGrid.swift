import SwiftUI
import CoreData

/// What the roll's cards and tiles do. The expanded view saves after each.
struct AttendanceGridActions {
    /// A card's click: the next status in the cycle.
    let cycle: (AttendanceRow) -> Void
    /// A phone tile's tap: present during arrival, late after it closes.
    let tap: (AttendanceRow) -> Void
    let setStatus: (AttendanceStatus, AttendanceRow) -> Void
    let markAbsent: (AbsenceReason, AttendanceRow) -> Void
    let saveNote: (AttendanceRow, String?) -> Void
    /// Leaving Early…: the pickup time on the day on screen, or nil to remove it.
    let savePickup: (AttendanceRow, Date?) -> Void
    /// Back in Class: a child who left early has come back.
    let markBack: (AttendanceRow) -> Void
}

/// The day's roll: cards on the Mac and iPad, the Daybook Assistant's tiles
/// on the iPhone (tap anywhere on a child; long-press for everything else).
struct AttendanceGrid: View {
    let viewModel: AttendanceViewModel
    /// When false (e.g. the day is locked), cards render read-only and taps no longer mark.
    let isEditing: Bool
    let actions: AttendanceGridActions
    /// A sideways swipe across the iPhone tiles: true for the next school day.
    var onStepDay: ((Bool) -> Void)?

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var noteRow: AttendanceRow?
    /// The child whose pickup time is being set (Leaving Early…).
    @State private var pickupRow: AttendanceRow?

    // Layout constants
    private let horizontalPadding: CGFloat = UIConstants.AttendanceGrid.horizontalPadding
    private let verticalPadding: CGFloat = UIConstants.AttendanceGrid.verticalPadding
    private let cardSpacing: CGFloat = UIConstants.AttendanceGrid.cardSpacing
    private let minCardWidth: CGFloat = UIConstants.AttendanceGrid.minCardWidth
    private let maxCardWidth: CGFloat = UIConstants.AttendanceGrid.maxCardWidth
    private let minCardHeight: CGFloat = UIConstants.AttendanceGrid.minCardHeight

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
                        + "and the Daybook Assistant reminds them before it.",
                    onSave: { actions.savePickup(row, $0) }
                )
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
            markedBy: markedBy(row),
            menuStatuses: viewModel.menuStatuses,
            onTap: { actions.cycle(row) },
            onSetStatus: { actions.setStatus($0, row) },
            onMarkAbsent: { reason in
                actions.markAbsent(reason, row)
                // "Other" is only as good as the note that says what.
                if reason == .other { noteRow = row }
            },
            onNote: { noteRow = row },
            onPickup: pickupAction(row),
            onBack: backAction(row)
        )
    }

    // MARK: - iPad/macOS: Card grid

    private var gridLayout: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - (horizontalPadding * 2)
            let availableHeight = geometry.size.height - (verticalPadding * 2)
            let rows = viewModel.rows

            // Calculate optimal grid layout
            let layout = calculateLayout(
                studentCount: rows.count,
                availableWidth: availableWidth,
                availableHeight: availableHeight
            )

            let gridItem = GridItem(
                .fixed(layout.cardWidth),
                spacing: cardSpacing
            )
            let columns = Array(
                repeating: gridItem,
                count: layout.columns
            )

            // Use ScrollView only when content doesn't fit
            if layout.needsScrolling {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .center, spacing: cardSpacing) {
                        ForEach(rows) { row in
                            card(row)
                                .frame(height: layout.cardHeight)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                }
            } else {
                VStack(spacing: 0) {
                    LazyVGrid(columns: columns, alignment: .center, spacing: cardSpacing) {
                        ForEach(rows) { row in
                            card(row)
                                .frame(height: layout.cardHeight)
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityRotor("Students") {
            ForEach(viewModel.rows) { row in
                AccessibilityRotorEntry(row.name, id: row.id)
            }
        }
    }

    // Calculate the optimal grid layout to fill available space without scrolling
    // swiftlint:disable:next function_body_length
    private func calculateLayout(
        studentCount: Int,
        availableWidth: CGFloat,
        availableHeight: CGFloat
    ) -> GridLayout {
        guard studentCount > 0, availableWidth > 0, availableHeight > 0 else {
            return GridLayout(
                columns: 1,
                rows: 1,
                cardWidth: minCardWidth,
                cardHeight: minCardHeight,
                needsScrolling: false
            )
        }

        // Try different column counts and find the best fit
        var bestLayout: GridLayout?

        // Calculate max possible columns based on minimum card width
        let maxPossibleColumns = max(1, Int((availableWidth + cardSpacing) / (minCardWidth + cardSpacing)))

        for cols in 1...maxPossibleColumns {
            let rows = Int(ceil(Double(studentCount) / Double(cols)))

            // Calculate card dimensions for this configuration
            let totalHorizontalSpacing = cardSpacing * CGFloat(cols - 1)
            let cardWidth = (availableWidth - totalHorizontalSpacing) / CGFloat(cols)

            let totalVerticalSpacing = cardSpacing * CGFloat(rows - 1)
            let cardHeight = (availableHeight - totalVerticalSpacing) / CGFloat(rows)

            // Check if this configuration is valid
            let isValidWidth = cardWidth >= minCardWidth && cardWidth <= maxCardWidth
            let isValidHeight = cardHeight >= minCardHeight

            if isValidWidth && isValidHeight {
                let layout = GridLayout(
                    columns: cols,
                    rows: rows,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    needsScrolling: false
                )

                // Prefer layouts that use more columns (wider cards look better)
                // but also consider height efficiency
                if let best = bestLayout {
                    // Prefer layout with more balanced aspect ratio and better space usage
                    let currentAspect = layout.cardWidth / layout.cardHeight
                    let bestAspect = best.cardWidth / best.cardHeight
                    let idealAspect: CGFloat = 2.5 // Prefer wider cards

                    let currentScore = abs(currentAspect - idealAspect)
                    let bestScore = abs(bestAspect - idealAspect)

                    if currentScore < bestScore {
                        bestLayout = layout
                    }
                } else {
                    bestLayout = layout
                }
            }
        }

        // Fallback: if no valid layout found, use minimum sizes with scrolling
        if let bestLayout {
            return bestLayout
        }

        let cols = max(1, Int((availableWidth + cardSpacing) / (minCardWidth + cardSpacing)))
        let rows = Int(ceil(Double(studentCount) / Double(cols)))
        let totalHorizontalSpacing = cardSpacing * CGFloat(cols - 1)
        let cardWidth = min(
            maxCardWidth,
            max(minCardWidth, (availableWidth - totalHorizontalSpacing) / CGFloat(cols))
        )
        return GridLayout(
            columns: cols,
            rows: rows,
            cardWidth: cardWidth,
            cardHeight: minCardHeight,
            needsScrolling: true
        )
    }
}

/// Represents a calculated grid layout
private struct GridLayout {
    let columns: Int
    let rows: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let needsScrolling: Bool
}
