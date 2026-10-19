//
//  ChecklistCellCard.swift
//  Cosmic Daybook
//
//  What a click on a checklist cell opens: the lesson, the child, where she stands
//  and why (amber for "Ready, check first", with the reason), the lesson before it
//  as the guide wants to see it first (when given, open work, last check-in,
//  mastered or not), the ladder's five steps to move her up, Present (with the other children
//  ready for it), the Inbox, Assign work, Clear, and links to the lesson and the
//  child. A popover on the Mac and iPad, a sheet on the iPhone. Every button sends
//  its action through the grid's one handler, as the cell's own menu does.
//

import SwiftUI

struct ChecklistCellCard: View {
    let cell: CellIdentifier
    let isRegular: Bool
    let onAction: ChecklistCellActionHandler

    @Environment(ClassAreaChecklistViewModel.self) private var viewModel

    static let width: CGFloat = 420

    private var state: StudentChecklistRowState? { viewModel.matrixStates[cell.studentID]?[cell.lessonID] }
    private var student: CDStudent? { viewModel.rosterStudents.first { $0.id == cell.studentID } }
    private var lesson: CDLesson? { viewModel.lessons.first { $0.id == cell.lessonID } }
    private var status: ChecklistDisplayStatus { state?.displayStatus ?? .ready }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            statusLine
            if let previous = viewModel.cardCell == cell ? viewModel.cardPrevious : nil,
               status < .presented {
                previousBox(previous)
            }
            steps
            actions
            Divider()
            footer
        }
        .padding(16)
        .frame(width: isRegular ? Self.width : nil, alignment: .leading)
        .frame(maxWidth: isRegular ? nil : .infinity, alignment: .leading)
        .modifier(ChecklistCardKeys(isEnabled: isRegular, cell: cell, onAction: onAction))
        // A solid card, as drawn: the popover's glass let the grid's names and marks
        // show through behind the text. The grid's own surface, so dark mode follows.
        .background(ChecklistGridMetrics.surface)
        .presentationBackground(ChecklistGridMetrics.surface)
        .presentationDetents([.medium, .large])
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(student?.shortName ?? ""), \(lesson?.name ?? "")")
    }

    // MARK: - Pieces

    private var heading: some View {
        let ageYears = student?.birthday.flatMap { Calendar.current.dateComponents([.year], from: $0, to: Date()).year }
        return VStack(alignment: .leading, spacing: 2) {
            Text(lesson?.name ?? "Lesson")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(ChecklistCellCardText.subtitle(
                studentName: student?.shortName ?? "",
                section: lesson?.section ?? "",
                sequence: lesson?.sequence ?? "",
                ageYears: ageYears
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var statusLine: some View {
        let text = ChecklistCellCardText.status(
            state: state,
            // The record is read for the open card; a card on its way out shows no dates.
            record: viewModel.cardCell == cell ? viewModel.cardRecord : ChecklistCardRecord(),
            precedingLessonName: viewModel.precedingLessonNames[cell.lessonID]
        )
        // Amber always means look before you act.
        let checkFirst = ChecklistCellDescription.checkFirstText(state) != nil
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            ChecklistMark(
                status: status, needsCheckIn: state?.needsCheckIn ?? false, checkFirst: checkFirst, size: 16
            )
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text("\(Text(text.title).bold()) \(text.detail)")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            checkFirst
                ? ChecklistGridMetrics.checkFirstTile
                : Color.primary.opacity(UIConstants.OpacityConstants.faint),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .accessibilityElement(children: .combine)
    }

    /// PREVIOUS LESSON: its mark, its name and when she was given it, then open work,
    /// the last check-in and whether it is mastered.
    private func previousBox(_ previous: ChecklistCardPrevious) -> some View {
        let mark = viewModel.matrixStates[cell.studentID]?[previous.lessonID]?.displayStatus
            ?? (previous.status.mastered ? .mastered : .presented)
        return VStack(alignment: .leading, spacing: 6) {
            Text("PREVIOUS LESSON")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ChecklistMark(status: mark, size: 14)
                Text(previous.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("· \(previous.givenText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                ForEach(previous.rows, id: \.label) { row in
                    GridRow {
                        Text(row.label).foregroundStyle(.secondary)
                        Text(row.value)
                    }
                }
            }
            .font(.footnote)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(UIConstants.OpacityConstants.hint), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var steps: some View {
        HStack(spacing: 6) {
            ForEach(ChecklistLadderStep.allCases) { step in
                let isReached = step.isReached(by: status)
                Button {
                    onAction(step.action, cell)
                } label: {
                    VStack(spacing: 6) {
                        ChecklistMark(status: step.status, size: 16)
                        Text(step.label)
                            .font(.caption)
                            .fontWeight(step.status == status ? .semibold : .regular)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        Color.primary.opacity(isReached ? 0.1 : UIConstants.OpacityConstants.hint),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isReached)
                .help(isReached ? "Already \(step.label.lowercased())" : "Mark \(step.label.lowercased())")
                .accessibilityLabel(step.label)
                .accessibilityValue(isReached ? "Done" : "")
            }
        }
    }

    private var actions: some View {
        let others = viewModel.readyStudentIDs(
            for: cell.lessonID, studentOrder: viewModel.students.compactMap(\.id), excluding: cell.studentID
        ).count
        let present = Button(ChecklistCellCardText.presentLabel(othersReady: others)) {
            onAction(.present, cell)
        }
        .buttonStyle(.borderedProminent)
        .help(others > 0 ? "Present to this child and the others ready for it" : "Present this lesson")
        let inbox = Button(inboxLabel) { onAction(.toggleScheduled, cell) }
            .buttonStyle(.bordered)
        let work = Button("Assign Work…") { onAction(.assignWork, cell) }
            .buttonStyle(.bordered)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { present; inbox; work }
            VStack(alignment: .leading, spacing: 8) {
                present
                HStack(spacing: 8) { inbox; work }
            }
        }
        .controlSize(.small)
    }

    private var inboxLabel: String {
        guard state?.isScheduled == true else { return "Add to Inbox" }
        return state?.isInboxPlan == true ? "Remove from Inbox" : "Remove Plan"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRegular {
                ChecklistKeyHints()
            }
            HStack(spacing: 6) {
                Button("Open Lesson") { onAction(.openLesson, cell) }
                Text("·").foregroundStyle(.secondary)
                Button("Open \(student?.shortName ?? "Student")") { onAction(.openStudent, cell) }
                Spacer(minLength: 8)
                Button("Clear", role: .destructive) { onAction(.clearStatus, cell) }
                    .disabled(status == .ready || status == .notReady)
                    .help("Take everything off this cell: plans, presentations, work and the mark. Notes stay.")
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .lineLimit(1)
        }
    }
}

/// "P presented · M mastered · I Inbox · ⌫ clear", as small key caps.
private struct ChecklistKeyHints: View {
    var body: some View {
        HStack(spacing: 5) {
            hint("P", "presented")
            hint("M", "mastered")
            hint("I", "Inbox")
            hint("⌫", "clear")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func hint(_ key: String, _ meaning: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.caption2.weight(.medium))
                .frame(minWidth: 16, minHeight: 16)
                .padding(.horizontal, 2)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary, lineWidth: 0.5))
            Text(meaning)
        }
    }
}

/// The checklist's plain keys inside the card, which takes key focus while it is open:
/// P, M, I and Delete act on the card's cell; Escape closes it.
private struct ChecklistCardKeys: ViewModifier {
    let isEnabled: Bool
    let cell: CellIdentifier
    let onAction: ChecklistCellActionHandler
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .focusable()
                .focusEffectDisabled()
                .focused($isFocused)
                .onAppear { isFocused = true }
                .onKeyPress(phases: .down) { press in
                    guard let command = ChecklistKeyCommand.command(
                        key: press.key, characters: press.characters, modifiers: press.modifiers
                    ) else { return .ignored }
                    if let action = command.cellAction {
                        onAction(action, cell)
                        return .handled
                    }
                    guard command == .dismiss else { return .ignored }
                    onAction(.closeCard, cell)
                    return .handled
                }
        } else {
            content
        }
    }
}
