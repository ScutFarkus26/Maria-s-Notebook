//
//  ChecklistHover.swift
//  Cosmic Daybook
//
//  Where the pointer is on the checklist (Mac, and an iPad with a pointer): its row
//  and column are tinted and the lesson's name and the child's name stand out. The
//  state lives in its own small object, read only by the tints and the two names,
//  so moving the pointer redraws those and never the cells.
//

import SwiftUI

@Observable
final class ChecklistHoverState {
    private(set) var lessonID: UUID?
    private(set) var studentID: UUID?

    /// The pointer entered a cell.
    func enter(_ cell: CellIdentifier) {
        if lessonID != cell.lessonID { lessonID = cell.lessonID }
        if studentID != cell.studentID { studentID = cell.studentID }
    }

    /// The pointer entered a lesson's name: its row, no column.
    func enterRow(_ lessonID: UUID) {
        if self.lessonID != lessonID { self.lessonID = lessonID }
        if studentID != nil { studentID = nil }
    }

    /// The pointer left a cell or a name. Ignored when it has already entered another.
    func leave(lessonID: UUID, studentID: UUID?) {
        guard self.lessonID == lessonID, self.studentID == studentID else { return }
        self.lessonID = nil
        self.studentID = nil
    }
}

/// The hovered row's tint and the hovered cell's outline, drawn behind one row's cells.
struct ChecklistRowHoverFill: View {
    let lessonID: UUID?
    let columnIDs: [UUID]
    let metrics: ChecklistGridMetrics
    @Environment(ChecklistHoverState.self) private var hover: ChecklistHoverState?

    var body: some View {
        if let hover, let lessonID, hover.lessonID == lessonID {
            ZStack(alignment: .topLeading) {
                ChecklistGridMetrics.hoverFill
                if let studentID = hover.studentID, let index = columnIDs.firstIndex(of: studentID) {
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                        .fill(ChecklistGridMetrics.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                        .padding(1)
                        .frame(width: metrics.studentColumnWidth, height: metrics.rowHeight)
                        .offset(x: metrics.lessonColumnWidth + CGFloat(index) * metrics.studentColumnWidth)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// The hovered column's tint, drawn behind the whole grid's rows. The bands, captions,
/// sticky names and pinned header are opaque and cover it.
struct ChecklistColumnHoverStripe: View {
    let columnIDs: [UUID]
    let metrics: ChecklistGridMetrics
    @Environment(ChecklistHoverState.self) private var hover: ChecklistHoverState?

    var body: some View {
        if let studentID = hover?.studentID, let index = columnIDs.firstIndex(of: studentID) {
            ChecklistGridMetrics.hoverFill
                .frame(width: metrics.studentColumnWidth)
                .frame(maxHeight: .infinity)
                .offset(x: metrics.lessonColumnWidth + CGFloat(index) * metrics.studentColumnWidth)
                .allowsHitTesting(false)
        }
    }
}

/// A column's name in the header, bold and tinted while the pointer is in its column.
struct ChecklistHeaderName: View {
    let studentID: UUID?
    let name: String
    @Environment(ChecklistHoverState.self) private var hover: ChecklistHoverState?

    var body: some View {
        let isHovered = studentID != nil && hover?.studentID == studentID
        Text(name)
            .font(.caption.weight(isHovered ? .bold : .regular))
            .foregroundStyle(isHovered ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
    }
}

/// A lesson row's chrome on the Mac and iPad: the pointer's tint behind it and the
/// bottom hairline. The iPhone's cells draw their own borders.
struct ChecklistRowChrome: ViewModifier {
    let lessonID: UUID?
    let columnIDs: [UUID]
    let metrics: ChecklistGridMetrics

    func body(content: Content) -> some View {
        if metrics.isRegular {
            content
                .background(alignment: .topLeading) {
                    ChecklistRowHoverFill(lessonID: lessonID, columnIDs: columnIDs, metrics: metrics)
                }
                .overlay(alignment: .bottom) {
                    ChecklistGridMetrics.hairline
                        .frame(height: 0.5)
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}
