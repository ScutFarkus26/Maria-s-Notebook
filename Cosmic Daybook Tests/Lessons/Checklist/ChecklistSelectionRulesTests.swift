import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The checklist's cell card, keys and selection without a mode (plan, Phase 4), as pure
/// rules: the selection reach, the cursor, the ready set, the key map, the row layout a
/// drag reads, the card's words and steps, and the lesson column that fits a full class at
/// 1180 pt. The view model over a store is in `ChecklistCardAndSelectionTests`.
@Suite("Checklist selection rules")
@MainActor
struct ChecklistSelectionRulesTests {

    private let lessons = (0..<4).map { _ in UUID() }
    private let students = (0..<5).map { _ in UUID() }

    private func cell(_ student: Int, _ lesson: Int) -> CellIdentifier {
        CellIdentifier(studentID: students[student], lessonID: lessons[lesson])
    }

    // MARK: - Selection rules

    @Test("Shift-click reaches along the row, either way, in column order")
    func rangeAlongRow() {
        let along = ChecklistSelection.range(
            from: cell(3, 1), to: cell(1, 1), lessonOrder: lessons, studentOrder: students
        )
        #expect(along == [cell(1, 1), cell(2, 1), cell(3, 1)])
    }

    @Test("Shift-click reaches down the column in row order")
    func rangeDownColumn() {
        let down = ChecklistSelection.range(
            from: cell(2, 0), to: cell(2, 3), lessonOrder: lessons, studentOrder: students
        )
        #expect(down == [cell(2, 0), cell(2, 1), cell(2, 2), cell(2, 3)])
    }

    @Test("A cell in neither the row nor the column, or one off screen, is just itself")
    func rangeElsewhere() {
        #expect(ChecklistSelection.range(
            from: cell(0, 0), to: cell(2, 2), lessonOrder: lessons, studentOrder: students
        ) == [cell(2, 2)])
        let hidden = CellIdentifier(studentID: UUID(), lessonID: lessons[1])
        #expect(ChecklistSelection.range(
            from: hidden, to: cell(2, 1), lessonOrder: lessons, studentOrder: students
        ) == [cell(2, 1)])
    }

    @Test("⌘-click toggles one cell")
    func toggling() {
        let once = ChecklistSelection.toggling(cell(0, 0), in: [cell(1, 1)])
        #expect(once == [cell(0, 0), cell(1, 1)])
        #expect(ChecklistSelection.toggling(cell(0, 0), in: once) == [cell(1, 1)])
    }

    @Test("The cursor steps, stops at the edges, and starts on the first cell")
    func cursorMoves() {
        let move = { (from: CellIdentifier?, dx: Int, dy: Int) in
            ChecklistSelection.moving(from, dx: dx, dy: dy, lessonOrder: lessons, studentOrder: students)
        }
        #expect(move(nil, 1, 0) == cell(0, 0))
        #expect(move(cell(2, 1), 1, 0) == cell(3, 1))
        #expect(move(cell(2, 1), 0, 1) == cell(2, 2))
        #expect(move(cell(0, 0), -1, -1) == cell(0, 0))
        #expect(move(cell(4, 3), 1, 1) == cell(4, 3))
        let gone = CellIdentifier(studentID: UUID(), lessonID: lessons[2])
        #expect(move(gone, 1, 0) == cell(0, 0))
        #expect(ChecklistSelection.moving(nil, dx: 0, dy: 0, lessonOrder: [], studentOrder: students) == nil)
    }

    private func state(
        _ lesson: Int, presented: Bool = false, scheduled: Bool = false, blocking: BlockingReason = .none
    ) -> StudentChecklistRowState {
        StudentChecklistRowState(
            lessonID: lessons[lesson], plannedItemID: nil, presentationLogID: nil, contractID: nil,
            isScheduled: scheduled, isPresented: presented, isActive: false, isComplete: false,
            lastActivityDate: nil, isStale: false, blockingReason: blocking
        )
    }

    @Test("Ready means not presented, not planned and nothing holding it back, in column order")
    func readySet() {
        let matrix: [UUID: [UUID: StudentChecklistRowState]] = [
            students[0]: [lessons[0]: state(0)],
            students[1]: [lessons[0]: state(0, presented: true)],
            students[2]: [lessons[0]: state(0, scheduled: true)],
            students[3]: [lessons[0]: state(0, blocking: .prerequisiteNotPresented)],
            students[4]: [lessons[0]: state(0)]
        ]
        let ready = ChecklistSelection.readyStudents(for: lessons[0], studentOrder: students, matrix: matrix)
        #expect(ready == [students[0], students[4]])
        let others = ChecklistSelection.readyStudents(
            for: lessons[0], studentOrder: students, matrix: matrix, excluding: students[0]
        )
        #expect(others == [students[4]])
        #expect(ChecklistSelection.readyStudents(for: lessons[1], studentOrder: students, matrix: matrix).isEmpty)
    }

    // MARK: - Keys

    @Test("Plain keys map to the grid's commands; ⌘, ⌃ and ⌥ pass through")
    func keyMap() {
        let command = { (key: KeyEquivalent, characters: String, modifiers: EventModifiers) in
            ChecklistKeyCommand.command(key: key, characters: characters, modifiers: modifiers)
        }
        #expect(command(.leftArrow, "", []) == .move(dx: -1, dy: 0))
        #expect(command(.downArrow, "", []) == .move(dx: 0, dy: 1))
        #expect(command(.return, "\r", []) == .openCard)
        #expect(command(.space, " ", []) == .openCard)
        #expect(command(.delete, "", []) == .clear)
        #expect(command(.deleteForward, "", []) == .clear)
        #expect(command(.escape, "", []) == .dismiss)
        #expect(command(KeyEquivalent("p"), "p", []) == .presented)
        #expect(command(KeyEquivalent("P"), "P", .shift) == .presented)
        #expect(command(KeyEquivalent("m"), "m", []) == .mastered)
        #expect(command(KeyEquivalent("i"), "i", []) == .toggleInbox)
        #expect(command(KeyEquivalent("p"), "p", .command) == nil)
        #expect(command(.downArrow, "", .option) == nil)
        #expect(command(KeyEquivalent("x"), "x", []) == nil)
    }

    @Test("Keys act on the cursor's cell with the card's own actions")
    func keyActions() {
        #expect(ChecklistKeyCommand.presented.cellAction == .markPresented)
        #expect(ChecklistKeyCommand.mastered.cellAction == .markComplete)
        #expect(ChecklistKeyCommand.toggleInbox.cellAction == .toggleScheduled)
        #expect(ChecklistKeyCommand.clear.cellAction == .clearStatus)
        #expect(ChecklistKeyCommand.openCard.cellAction == nil)
        #expect(ChecklistKeyCommand.move(dx: 1, dy: 0).cellAction == nil)
    }

    // MARK: - Lesson column

    @Test("A full class of 22 and the Class column fit an 1180-pt iPad window")
    func lessonColumnFits1180() {
        let fitted = ChecklistGridMetrics.regular.fitted(toWidth: 1180, studentCount: 22)
        #expect(fitted.lessonColumnWidth == 228)
        #expect(fitted.rowWidth(studentCount: 22) <= 1180)
        #expect(fitted.studentColumnWidth == ChecklistGridMetrics.regular.studentColumnWidth)
        #expect(fitted.classColumnWidth == ChecklistGridMetrics.regular.classColumnWidth)
    }

    @Test("The lesson column keeps 268 pt when there's room, never goes under 200, and the iPhone's is fixed")
    func lessonColumnBounds() {
        #expect(ChecklistGridMetrics.regular.fitted(toWidth: 1600, studentCount: 22).lessonColumnWidth == 268)
        #expect(ChecklistGridMetrics.regular.fitted(toWidth: 900, studentCount: 22).lessonColumnWidth == 200)
        #expect(ChecklistGridMetrics.regular.fitted(toWidth: 0, studentCount: 22) == .regular)
        #expect(ChecklistGridMetrics.compact.fitted(toWidth: 400, studentCount: 22) == .compact)
    }

    // MARK: - Row layout

    @Test("A drag down a column finds rows past bands and captions")
    func rowLayout() {
        let layout = ChecklistRowLayout(slots: [
            .init(lessonID: nil, height: 30),          // band 0–30
            .init(lessonID: lessons[0], height: 30),   // 30–60
            .init(lessonID: lessons[1], height: 30),   // 60–90
            .init(lessonID: nil, height: 30),          // band 90–120
            .init(lessonID: nil, height: 24),          // caption 120–144
            .init(lessonID: lessons[2], height: 30)    // 144–174
        ])
        #expect(layout.lessonIDs == [lessons[0], lessons[1], lessons[2]])
        #expect(layout.top(of: lessons[2]) == 144)
        #expect(layout.top(of: lessons[3]) == nil)
        #expect(layout.lesson(atY: 75, towardTop: false) == lessons[1])
        #expect(layout.lesson(atY: 100, towardTop: true) == lessons[1])
        #expect(layout.lesson(atY: 100, towardTop: false) == lessons[2])
        #expect(layout.lesson(atY: -40, towardTop: false) == lessons[0])
        #expect(layout.lesson(atY: 900, towardTop: true) == lessons[2])
        #expect(ChecklistRowLayout().lesson(atY: 10, towardTop: true) == nil)
    }

    // MARK: - Card words and steps

    @Test("A step is done once the child is on its rung or above; each runs its own action")
    func ladderSteps() {
        #expect(ChecklistLadderStep.presented.isReached(by: .practicing))
        #expect(ChecklistLadderStep.presented.isReached(by: .presented))
        #expect(!ChecklistLadderStep.mastered.isReached(by: .reviewing))
        #expect(!ChecklistLadderStep.planned.isReached(by: .ready))
        #expect(!ChecklistLadderStep.planned.isReached(by: .notReady))
        #expect(ChecklistLadderStep.allCases.map(\.action)
                == [.toggleScheduled, .markPresented, .markPracticing, .markReviewing, .markComplete])
    }

    @Test("Present names the others ready")
    func presentLabel() {
        #expect(ChecklistCellCardText.presentLabel(othersReady: 0) == "Present…")
        #expect(ChecklistCellCardText.presentLabel(othersReady: 1) == "Present with 1 other ready…")
        #expect(ChecklistCellCardText.presentLabel(othersReady: 4) == "Present with 4 others ready…")
    }

    @Test("The status line says where the child stands, with the reason or the date")
    func statusLine() {
        let day = Date(timeIntervalSince1970: 1_780_000_000)
        let text = { (state: StudentChecklistRowState?, record: ChecklistCardRecord) in
            ChecklistCellCardText.status(
                state: state, record: record, precedingLessonName: "Subtraction: Dynamic", dateText: { _ in "Feb 12" }
            )
        }
        #expect(text(state(0), .init()) == .init(
            title: "Ready.", detail: "Nothing holds it back; not presented or planned yet."
        ))
        #expect(text(state(0, blocking: .prerequisiteNotPresented), .init()) == .init(
            title: "Not yet.", detail: "Subtraction: Dynamic not presented."
        ))
        #expect(text(state(0, scheduled: true), .init()).detail == "In the Inbox.")
        #expect(text(state(0, scheduled: true), .init(plannedFor: day)).detail == "Planned for Feb 12.")
        #expect(text(state(0, presented: true), .init(presentedOn: day)) == .init(
            title: "Presented.", detail: "On Feb 12."
        ))
        #expect(text(state(0, presented: true), .init()).detail == "No date recorded.")
    }

    @Test("The subtitle names the child, the lesson's section (or sequence) and her age")
    func subtitle() {
        let subtitle = ChecklistCellCardText.subtitle
        #expect(subtitle("Maya S", "Stamp Game", "Preliminary", 9) == "Maya S · Stamp Game · age 9")
        #expect(subtitle("Maya S", " ", "Preliminary", nil) == "Maya S · Preliminary")
        #expect(subtitle("Maya S", "", "", 0) == "Maya S")
    }
}
