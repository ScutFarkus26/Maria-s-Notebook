// TodayLinkedTodos.swift
// Folding follow-up todos onto the work rows they are about.
//
// A todo can name one piece of work (`linkedWorkItemID`, the work's
// uuidString). When that work has a row on Today, the row carries the todo
// ("3 todos · Sep 18", red when overdue) and the Todos list leaves it out, so
// the same follow-up is not shown twice. A todo whose work is not on screen
// stays in the Todos list as usual.
//
// Pure: it takes value snapshots, the work ids Today is showing, and the day
// and calendar to judge "overdue" against, and touches no Core Data.

import Foundation

nonisolated struct TodayLinkedTodos: Equatable, Sendable {

    /// The few fields of an open todo the folding needs.
    nonisolated struct Todo: Equatable, Sendable {
        let id: UUID
        let linkedWorkItemID: String?
        let dueDate: Date?
        let isCompleted: Bool

        init(id: UUID, linkedWorkItemID: String?, dueDate: Date?, isCompleted: Bool = false) {
            self.id = id
            self.linkedWorkItemID = linkedWorkItemID
            self.dueDate = dueDate
            self.isCompleted = isCompleted
        }

        /// The linked work's id, when the stored string is one.
        var linkedWorkID: UUID? {
            linkedWorkItemID.flatMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) }
        }
    }

    /// What one work row shows for its linked todos.
    nonisolated struct WorkTodos: Equatable, Sendable {
        let workID: UUID
        /// Earliest due first; undated todos last, in the order given.
        let todoIDs: [UUID]
        /// The soonest due date among them, if any is dated.
        let earliestDueDate: Date?
        /// The soonest due date is before the reference day.
        let isOverdue: Bool
        /// "1 todo", "3 todos · Sep 18".
        let summary: String

        var count: Int { todoIDs.count }
    }

    /// Linked open todos per on-screen work id.
    let byWork: [UUID: WorkTodos]
    /// Todos the Todos list should leave out because their work row shows them.
    let hiddenTodoIDs: Set<UUID>

    static let empty = TodayLinkedTodos(byWork: [:], hiddenTodoIDs: [])

    /// - Parameters:
    ///   - todos: the todos Today loaded; completed ones are ignored.
    ///   - workIDsOnScreen: every work id with a row on Today.
    ///   - referenceDay: the day being shown; a due date before its start is overdue.
    ///   - calendar: the calendar (and its time zone and locale) for the day and the summary date.
    static func build(
        todos: [Todo],
        workIDsOnScreen: Set<UUID>,
        referenceDay: Date,
        calendar: Calendar
    ) -> TodayLinkedTodos {
        guard !workIDsOnScreen.isEmpty else { return .empty }

        var grouped: [UUID: [Todo]] = [:]
        for todo in todos where !todo.isCompleted {
            guard let workID = todo.linkedWorkID, workIDsOnScreen.contains(workID) else { continue }
            grouped[workID, default: []].append(todo)
        }

        let startOfDay = calendar.startOfDay(for: referenceDay)
        var byWork: [UUID: WorkTodos] = [:]
        var hidden: Set<UUID> = []
        for (workID, linked) in grouped {
            let ordered = sortedByDue(linked)
            let earliest = ordered.first?.dueDate
            let overdue = earliest.map { $0 < startOfDay } ?? false
            byWork[workID] = WorkTodos(
                workID: workID,
                todoIDs: ordered.map(\.id),
                earliestDueDate: earliest,
                isOverdue: overdue,
                summary: summary(count: ordered.count, earliestDue: earliest, calendar: calendar)
            )
            hidden.formUnion(ordered.map(\.id))
        }
        return TodayLinkedTodos(byWork: byWork, hiddenTodoIDs: hidden)
    }

    /// What one row shows when it stands for several works — a group
    /// lesson's children on one Gone quiet row: their linked todos together,
    /// the soonest due date among them, or nil when none has any.
    func rowTodos(for workIDs: [UUID], calendar: Calendar) -> WorkTodos? {
        let parts = workIDs.compactMap { byWork[$0] }
        guard let first = parts.first else { return nil }
        guard parts.count > 1 else { return first }
        let earliest = parts.compactMap(\.earliestDueDate).min()
        let todoIDs = parts.flatMap(\.todoIDs)
        return WorkTodos(
            workID: first.workID,
            todoIDs: todoIDs,
            earliestDueDate: earliest,
            // The soonest date decides, so any overdue part makes the row overdue.
            isOverdue: parts.contains(where: \.isOverdue),
            summary: Self.summary(count: todoIDs.count, earliestDue: earliest, calendar: calendar)
        )
    }

    /// "1 todo", "3 todos", "3 todos · Sep 18".
    static func summary(count: Int, earliestDue: Date?, calendar: Calendar) -> String {
        let noun = count == 1 ? "1 todo" : "\(count) todos"
        guard let earliestDue else { return noun }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        // A calendar made with `Calendar(identifier:)` — `AppCalendar.shared`,
        // which Today runs on — carries the empty root locale, not nil, and
        // that prints "M09 18". Only a real locale on the calendar wins.
        if let locale = calendar.locale, !locale.identifier.isEmpty {
            style.locale = locale
        } else {
            style.locale = .current
        }
        return "\(noun) · \(earliestDue.formatted(style))"
    }

    /// Stable: todos with the same due date (or none) keep the order given.
    private static func sortedByDue(_ todos: [Todo]) -> [Todo] {
        todos.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.dueDate ?? .distantFuture
                let right = rhs.element.dueDate ?? .distantFuture
                if left != right { return left < right }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
