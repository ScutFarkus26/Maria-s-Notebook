// ScheduleScopeDialog.swift
// Only This Day or This Day and After: what the Schedules page asks before
// it changes or deletes a block that repeats every week, the way Calendar
// asks about a repeating event. Earlier weeks always stay as they were.

import SwiftUI

/// A change or a delete waiting on its answer.
struct ScheduleScopeQuestion: Identifiable, Equatable {
    enum Action: Equatable {
        case change
        case delete
    }

    let action: Action
    let blockID: UUID
    /// The day the block was changed or deleted on.
    let day: Date

    var id: String { "\(action)-\(blockID.uuidString)" }

    var message: String {
        let day = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        switch action {
        case .change:
            return "Change it on \(day) only, or on that day and every week after? Earlier weeks stay as they were."
        case .delete:
            return "Take it off \(day) only, or from that day on? Earlier weeks stay as they were."
        }
    }
}

extension View {
    /// Asks `question` when it is set, and hands back the answer.
    func scheduleScopeDialog(
        _ question: Binding<ScheduleScopeQuestion?>,
        onAnswer: @escaping (ScheduleScopeQuestion, TimetableService.EditScope) -> Void
    ) -> some View {
        confirmationDialog(
            "This block repeats every week",
            isPresented: Binding(
                get: { question.wrappedValue != nil },
                set: { if !$0 { question.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: question.wrappedValue
        ) { asked in
            let role: ButtonRole? = asked.action == .delete ? .destructive : nil
            Button("Only This Day", role: role) { onAnswer(asked, .onlyThisDay) }
            Button("This Day and After", role: role) { onAnswer(asked, .thisDayAndAfter) }
            Button("Cancel", role: .cancel) {}
        } message: { asked in
            Text(asked.message)
        }
    }
}
