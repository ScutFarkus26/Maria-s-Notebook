// TodayViewNextCard.swift
// The Next card: the first lesson on the plan not yet given, drawn
// highlighted in place with a Present button (⌘↩).
//
// It does what the old Right Now hero's "Next up" play button did — opens the
// lesson — and replaced that hero on every platform. With no lesson pending it
// falls back to the first due check-in, which lives in the todo list rather
// than on the plan, so that one is drawn as a card of its own at the top of
// the Lessons section.

import SwiftUI

extension TodayView {

    // MARK: - Next agenda item

    /// The first lesson on the plan not yet given. With none, the first due
    /// check-in stands in — due check-ins moved off the agenda into the todo
    /// list, and the old Right Now hero kept proposing one after the move.
    var nextAgendaItem: AgendaItem? {
        let lesson = viewModel.agendaItems.first { item in
            if case .lesson(let sl) = item { return !sl.isPresented }
            return false
        }
        return lesson ?? viewModel.followUpCheckIns.first.map {
            .scheduledWork(ScheduledWorkItem(work: $0.work, checkIn: $0.checkIn))
        }
    }

    /// ⌘↩ belongs to the attendance grid's Close Arrival while the grid is
    /// open; the Next card takes it back when the grid closes.
    var nextCardShortcut: KeyboardShortcut? {
        isAttendanceExpanded ? nil : KeyboardShortcut(.return, modifiers: .command)
    }

    func startNextAgendaItem(_ item: AgendaItem) {
        switch item {
        case .lesson(let sl):
            selectedLessonAssignment = sl
        case .scheduledWork(let item):
            selectedWorkID = item.work.id
        case .followUp(let item):
            selectedWorkID = item.work.id
        case .groupedScheduledWork(let items):
            if let id = items.first?.work.id { selectedWorkID = id }
        case .groupedFollowUp(let items):
            if let id = items.first?.work.id { selectedWorkID = id }
        }
    }

    // MARK: - Check-in fallback card

    /// The fallback Next card for a due check-in, which is not a row on the
    /// plan.
    @ViewBuilder
    var nextCheckInCard: some View {
        if let next = nextAgendaItem, case .scheduledWork = next {
            HStack(spacing: 10) {
                Image(systemName: nextUpIcon(for: next))
                    .font(.system(size: 12))
                    .foregroundStyle(nextUpColor(for: next))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(nextUpDescription(for: next))
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .lineLimit(2)
                }
                Spacer()
                TodayNextButton(title: "Open", shortcut: nextCardShortcut) {
                    startNextAgendaItem(next)
                }
            }
            .todayNextHighlight(true)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        }
    }

    // MARK: - Describing an item

    func nextUpDescription(for item: AgendaItem) -> String {
        switch item {
        case .lesson(let sl):
            let lessonName = nameForLesson(sl.resolvedLessonID)
            let students = studentNamesForIDs(sl.resolvedStudentIDs)
            if students.isEmpty { return lessonName }
            return "\(lessonName) — \(students)"
        case .scheduledWork(let item):
            let lesson = resolveLessonName(for: item.work)
            let student = resolveStudentName(for: item.work)
            return "Check \(lesson) — \(student)"
        case .followUp(let item):
            let lesson = resolveLessonName(for: item.work)
            let student = resolveStudentName(for: item.work)
            return "Follow up: \(lesson) — \(student)"
        case .groupedScheduledWork(let items):
            let lesson = items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson"
            return "Check \(lesson) — \(items.count) students"
        case .groupedFollowUp(let items):
            let lesson = items.first.map { resolveLessonName(for: $0.work) } ?? "Lesson"
            return "Follow up: \(lesson) — \(items.count) students"
        }
    }

    func nextUpIcon(for item: AgendaItem) -> String {
        switch item {
        case .lesson: return "book.fill"
        case .scheduledWork, .groupedScheduledWork: return "clock.fill"
        case .followUp, .groupedFollowUp: return "arrow.uturn.left.circle.fill"
        }
    }

    func nextUpColor(for item: AgendaItem) -> Color {
        switch item {
        case .lesson: return .blue
        case .scheduledWork, .groupedScheduledWork: return .orange
        case .followUp, .groupedFollowUp: return .purple
        }
    }
}

// MARK: - Pieces

/// The Next card's one action, with ⌘↩ when nothing else on screen owns it.
struct TodayNextButton: View {
    let title: String
    let shortcut: KeyboardShortcut?
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(shortcut)
            .help(shortcut == nil ? title : "\(title) (⌘↩)")
    }
}

/// The accent border and tint that mark the Next card.
private struct TodayNextHighlight: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content
                .padding(10)
                .surface(
                    UIConstants.CornerRadius.control,
                    fill: Color.accentColor.opacity(UIConstants.OpacityConstants.subtle),
                    stroke: Color.accentColor.opacity(UIConstants.OpacityConstants.prominent),
                    lineWidth: 1.5,
                    style: .continuous
                )
        } else {
            content
        }
    }
}

extension View {
    func todayNextHighlight(_ isOn: Bool) -> some View {
        modifier(TodayNextHighlight(isOn: isOn))
    }
}
