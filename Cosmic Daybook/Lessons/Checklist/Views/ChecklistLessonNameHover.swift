//
//  ChecklistLessonNameHover.swift
//  Cosmic Daybook
//
//  The lesson name cell while the pointer is on its row (Mac and iPad): the name
//  turns semibold on the row's tint, and a "Select 5 ready" button selects the
//  children the lesson can be given to now. Each piece reads the hover state
//  itself, so the grid's body never does. Under the Ready lens a name greys when
//  no one is ready for its lesson.
//

import SwiftUI

/// The lesson's name, semibold while its row is hovered.
struct ChecklistLessonNameText: View {
    let lessonID: UUID?
    let text: String
    let font: Font
    let lineLimit: Int
    /// The Ready lens: no one is ready for this row.
    var isDimmed: Bool = false
    @Environment(ChecklistHoverState.self) private var hover: ChecklistHoverState?

    var body: some View {
        let isHovered = lessonID != nil && hover?.lessonID == lessonID
        Text(text)
            .font(font)
            .fontWeight(isHovered ? .semibold : nil)
            .foregroundStyle(isDimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.foreground))
            .lineLimit(lineLimit)
            .truncationMode(.tail)
    }
}

/// The row's tint behind its name, while hovered.
struct ChecklistNameHoverTint: View {
    let lessonID: UUID?
    @Environment(ChecklistHoverState.self) private var hover: ChecklistHoverState?

    var body: some View {
        if let lessonID, hover?.lessonID == lessonID {
            ChecklistGridMetrics.hoverFill
        }
    }
}

/// "Select 5 ready" at the end of a hovered lesson's name. Hidden when no one is ready.
struct ChecklistSelectReadyButton: View {
    let lessonID: UUID?
    let studentOrder: [UUID]
    let onSelect: (UUID) -> Void
    @Environment(ChecklistHoverState.self) private var hover: ChecklistHoverState?
    @Environment(ClassAreaChecklistViewModel.self) private var viewModel: ClassAreaChecklistViewModel?

    var body: some View {
        if let lessonID, hover?.lessonID == lessonID, let viewModel {
            let count = viewModel.readyStudentIDs(for: lessonID, studentOrder: studentOrder).count
            if count > 0 {
                Button {
                    onSelect(lessonID)
                } label: {
                    Text("Select \(count) ready")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ChecklistGridMetrics.surface)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Color.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Select the children ready for this lesson")
                .accessibilityLabel("Select \(count) ready children")
            }
        }
    }
}

/// The pointer on a lesson's name: its row is hovered, no column.
struct ChecklistNameHoverTracking: ViewModifier {
    let isEnabled: Bool
    let lessonID: UUID?
    let hover: ChecklistHoverState

    func body(content: Content) -> some View {
        if isEnabled, let lessonID {
            content.onHover { inside in
                if inside {
                    hover.enterRow(lessonID)
                } else {
                    hover.leave(lessonID: lessonID, studentID: nil)
                }
            }
        } else {
            content
        }
    }
}
