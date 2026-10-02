import SwiftUI

// MARK: - THE SMART CELL

/// Every input is a plain value and the handlers compare equal across renders, so the grid
/// wraps the cell in `.equatable()` and a matrix update redraws only the cells whose state
/// actually changed. A click sends `.click` (the grid reads ⌘ / Shift and opens the card or
/// changes the selection); the card is this cell's popover while `isCardOpen`.
struct ClassChecklistSmartCell: View, Equatable {
    let cell: CellIdentifier
    let state: StudentChecklistRowState?
    let isSelected: Bool
    let isSelectionMode: Bool
    /// The keyboard cursor is on this cell (drawn only while the grid has focus).
    var isCursor: Bool = false
    var isCardOpen: Bool = false
    /// Mac and iPad: hover, the card as a popover, and (Mac) drag to select.
    var isRegular: Bool = false
    var studentName: String = ""
    var lessonName: String = ""
    /// The lesson before this one in its sequence, named in the "Not yet" reason.
    var precedingLessonName: String?
    /// Under the Ready lens a ready cell gets a tinted tile and a blue ring; every
    /// other mark fades.
    var lens: ChecklistLens = .allMarks
    let onAction: ChecklistCellActionHandler
    var onDrag: ChecklistCellDragHandler?

    @Environment(ChecklistHoverState.self) private var hover: ChecklistHoverState?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cell == rhs.cell && lhs.state == rhs.state && lhs.isSelected == rhs.isSelected
            && lhs.isSelectionMode == rhs.isSelectionMode && lhs.isCursor == rhs.isCursor
            && lhs.isCardOpen == rhs.isCardOpen && lhs.isRegular == rhs.isRegular
            && lhs.studentName == rhs.studentName && lhs.lessonName == rhs.lessonName
            && lhs.precedingLessonName == rhs.precedingLessonName && lhs.lens == rhs.lens
    }

    private func onSelect() { onAction(.toggleSelection, cell) }

    var body: some View {
        let isScheduled = state?.isScheduled ?? false
        let blockingReason = state?.blockingReason ?? .none

        cellContent
            .overlay(selectionStroke)
            .onTapGesture { onAction(.click, cell) }
            .modifier(ChecklistCellPointer(isEnabled: isRegular, cell: cell, hover: hover, onDrag: onDrag))
            .popover(isPresented: cardBinding) {
                ChecklistCellCard(cell: cell, isRegular: isRegular, onAction: onAction)
            }
            .contextMenu { cellContextMenu(blockingReason: blockingReason, isScheduled: isScheduled) }
            .help(ChecklistCellDescription.helpText(
                studentName: studentName, lessonName: lessonName,
                state: state, precedingLessonName: precedingLessonName
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(studentName), \(lessonName)")
            .accessibilityValue(ChecklistCellDescription.accessibilityValue(
                state: state, precedingLessonName: precedingLessonName
            ))
            .accessibilityHint(ChecklistCellDescription.accessibilityHint(isSelectionMode: isSelectionMode))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The card shows while the view model says so; closing the popover tells it.
    private var cardBinding: Binding<Bool> {
        let isOpen = isCardOpen
        let cell = cell
        let onAction = onAction
        return Binding(
            get: { isOpen },
            set: { newValue in
                if !newValue && isOpen { onAction(.closeCard, cell) }
            }
        )
    }

    // MARK: - Cell Content

    /// One mark, centered. The blocking reason is in the hover text and VoiceOver value,
    /// not a badge; a stale cell gets the mark's check-in dot, not a tint.
    private var cellContent: some View {
        let status = state?.displayStatus ?? .ready
        // Ready as the lens counts it: a cell with a state that reads Ready.
        let isLifted = lens == .ready && state?.displayStatus == .ready
        return ZStack {
            if isLifted {
                ChecklistGridMetrics.readyTile
            }

            if isSelected {
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.faint))
            }

            Color.clear.contentShape(Rectangle())

            ChecklistMark(
                status: status,
                needsCheckIn: state?.needsCheckIn ?? false,
                emphasizesReady: isLifted
            )
            .opacity(lens == .ready && !isLifted ? ChecklistLens.fadedOpacity : 1)
        }
    }

    /// Selection is an ink outline, never accent blue: blue is the ladder's "started". The
    /// keyboard cursor (and the cell whose card is open) gets the accent's focus ring.
    @ViewBuilder
    private var selectionStroke: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                .stroke(Color.primary, lineWidth: 2)
                .padding(2)
        } else if isCursor || isCardOpen {
            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                .stroke(Color.accentColor, lineWidth: 2)
                .padding(2)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func cellContextMenu(blockingReason: BlockingReason, isScheduled: Bool) -> some View {
        if let reason = ChecklistCellDescription.reasonText(
            blockingReason, precedingLessonName: precedingLessonName
        ) {
            Label("Not yet: \(reason)", systemImage: blockingReason.iconName)
            Divider()
        }
        Button {
            #if os(iOS)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            #endif
            onSelect()
        } label: {
            Label(isSelected ? "Deselect" : "Select", systemImage: "checkmark.circle")
        }
        Divider()
        Button { onAction(.toggleScheduled, cell) } label: {
            Label(isScheduled ? "Remove Plan" : "Add to Inbox", systemImage: "tray")
        }
        Button { onAction(.togglePresented, cell) } label: { Label("Mark Presented", systemImage: "checkmark") }
        Button { onAction(.togglePreviouslyPresented, cell) } label: {
            Label("Previously Presented", systemImage: "clock.badge.checkmark")
        }
        Button { onAction(.markComplete, cell) } label: {
            Label("Mark Mastered", systemImage: "checkmark.circle.fill")
        }
        Divider()
        Button(role: .destructive) { onAction(.clearStatus, cell) } label: {
            Label("Clear All Status", systemImage: "xmark.circle")
        }
    }
}

// MARK: - Pointer

/// Mac and iPad: the pointer's row and column follow it into the cell; on the Mac a
/// drag that starts here selects along the row or down the column. Touch drags on the
/// iPad scroll the grid, so the iPad selects with ⌘- and Shift-click instead.
private struct ChecklistCellPointer: ViewModifier {
    let isEnabled: Bool
    let cell: CellIdentifier
    let hover: ChecklistHoverState?
    let onDrag: ChecklistCellDragHandler?

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onHover { inside in
                    if inside {
                        hover?.enter(cell)
                    } else {
                        hover?.leave(lessonID: cell.lessonID, studentID: cell.studentID)
                    }
                }
                #if os(macOS)
                .gesture(dragToSelect)
                #endif
        } else {
            content
        }
    }

    #if os(macOS)
    private var dragToSelect: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in onDrag?.changed(cell, value.startLocation, value.translation) }
            .onEnded { _ in onDrag?.ended(cell) }
    }
    #endif
}

// MARK: - Cell Identifier for Multi-Selection

struct CellIdentifier: Hashable {
    let studentID: UUID
    let lessonID: UUID
}
