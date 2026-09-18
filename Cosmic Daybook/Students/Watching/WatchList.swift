// WatchList.swift
// The single rule that decides what "I'm keeping an eye on this child" means.
//
// The guide says it three ways: an observation flagged for follow-up, a todo
// whose title begins with "Watch", and an open goal from a meeting (focus
// item). Each has its own screen; none of them has a home per child. The
// WatchList is that home — a derived, never persisted merge of the three into
// one row shape per child.
//
// The rule is pure: it takes value inputs and an explicit day, so every
// boundary is testable without Core Data and without a live clock. The
// adapters that build those inputs from managed objects live in
// `WatchList+CoreData.swift`; the actions that clear a row live in
// `WatchListActions.swift`. Same split as `LessonsAndWorkTriage`.

import Foundation

// MARK: - Kind

/// Which of the three sources a row came from.
enum WatchItemKind: String, CaseIterable, Sendable {
    /// A `CDNote` with `needsFollowUp` set.
    case flaggedNote
    /// An open `CDTodoItem` whose title begins with "Watch" and names a child.
    case watchTodo
    /// An active `CDStudentFocusItem`.
    case goal

    var title: String {
        switch self {
        case .flaggedNote: "Flagged note"
        case .watchTodo: "Watch todo"
        case .goal: "Goal"
        }
    }

    var systemImage: String {
        switch self {
        case .flaggedNote: "flag.fill"
        case .watchTodo: "eye"
        case .goal: "target"
        }
    }
}

// MARK: - Row

/// One thing being watched for one child (or, for a whole-class note, for
/// everyone). A note that names three children yields three rows that share a
/// `sourceID`; clearing any of them clears the note for all three.
struct WatchItem: Identifiable, Equatable, Sendable {
    let kind: WatchItemKind
    /// `CDNote.id`, `CDTodoItem.id` or `CDStudentFocusItem.id`.
    let sourceID: UUID
    /// nil means the whole class (a flagged note with scope `.all`).
    let studentID: UUID?
    /// Note body, todo title or goal text — trimmed, capped at 200 characters.
    let text: String
    /// When the guide last touched it: a note's later of updated/created, a
    /// todo's or goal's creation. Missing dates sort last.
    let date: Date
    /// Todos only.
    let dueDate: Date?

    var id: String {
        "\(kind.rawValue):\(sourceID.uuidString):\(studentID?.uuidString ?? "class")"
    }
}

/// The rows for one child, or for the whole class.
struct WatchGroup: Identifiable, Equatable, Sendable {
    let studentID: UUID?
    let name: String
    let items: [WatchItem]

    var id: String { studentID?.uuidString ?? "class" }

    static let wholeClassName = "Whole class"
}

// MARK: - Inputs

/// One observation, as the values the rule needs. `studentIDs` nil is `.all`.
struct WatchNoteInput: Sendable, Equatable {
    var id: UUID
    var needsFollowUp: Bool
    var studentIDs: [UUID]?
    var body: String
    var createdAt: Date?
    var updatedAt: Date?

    init(
        id: UUID,
        needsFollowUp: Bool,
        studentIDs: [UUID]?,
        body: String,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.needsFollowUp = needsFollowUp
        self.studentIDs = studentIDs
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One todo, as the values the rule needs.
struct WatchTodoInput: Sendable, Equatable {
    var id: UUID
    var title: String
    var studentIDs: [UUID]
    var isCompleted: Bool
    var isSomeday: Bool
    var createdAt: Date?
    var dueDate: Date?

    init(
        id: UUID,
        title: String,
        studentIDs: [UUID],
        isCompleted: Bool = false,
        isSomeday: Bool = false,
        createdAt: Date? = nil,
        dueDate: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.studentIDs = studentIDs
        self.isCompleted = isCompleted
        self.isSomeday = isSomeday
        self.createdAt = createdAt
        self.dueDate = dueDate
    }
}

/// One focus item, as the values the rule needs.
struct WatchGoalInput: Sendable, Equatable {
    var id: UUID
    var studentID: UUID?
    var text: String
    var isActive: Bool
    var createdAt: Date?
    var sortOrder: Int

    init(
        id: UUID,
        studentID: UUID?,
        text: String,
        isActive: Bool = true,
        createdAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.studentID = studentID
        self.text = text
        self.isActive = isActive
        self.createdAt = createdAt
        self.sortOrder = sortOrder
    }
}

// MARK: - The rule

enum WatchListBuilder {

    /// The longest text a row carries.
    static let textLimit = 200

    /// True for "Watch Etty on the stamp game", "watch:", "Watching Ora" —
    /// anything whose trimmed title starts with the word, in any case. Not
    /// "Rewatch" and not "Water the plants".
    static func isWatchTodo(title: String) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("watch")
    }

    /// Merges the three sources into rows, one per child, sorted by date
    /// (newest first), then kind, then text, so the order is deterministic.
    static func build(
        notes: [WatchNoteInput],
        todos: [WatchTodoInput],
        goals: [WatchGoalInput]
    ) -> [WatchItem] {
        var items: [WatchItem] = []

        for note in notes where note.needsFollowUp {
            let date = max(note.updatedAt ?? .distantPast, note.createdAt ?? .distantPast)
            let text = trimmed(note.body)
            if let studentIDs = note.studentIDs {
                for studentID in studentIDs {
                    items.append(WatchItem(
                        kind: .flaggedNote, sourceID: note.id, studentID: studentID,
                        text: text, date: date, dueDate: nil
                    ))
                }
            } else {
                items.append(WatchItem(
                    kind: .flaggedNote, sourceID: note.id, studentID: nil,
                    text: text, date: date, dueDate: nil
                ))
            }
        }

        // A "Watch" todo with no child on it is not about anyone in
        // particular; it stays in the todo list and nowhere else.
        for todo in todos
        where !todo.isCompleted && !todo.isSomeday && isWatchTodo(title: todo.title) {
            let text = trimmed(todo.title)
            for studentID in todo.studentIDs {
                items.append(WatchItem(
                    kind: .watchTodo, sourceID: todo.id, studentID: studentID,
                    text: text, date: todo.createdAt ?? .distantPast, dueDate: todo.dueDate
                ))
            }
        }

        for goal in goals where goal.isActive {
            items.append(WatchItem(
                kind: .goal, sourceID: goal.id, studentID: goal.studentID,
                text: trimmed(goal.text), date: goal.createdAt ?? .distantPast, dueDate: nil
            ))
        }

        return items.sorted(by: precedes)
    }

    /// That child's rows only. Whole-class rows are not hers.
    static func items(for studentID: UUID, in items: [WatchItem]) -> [WatchItem] {
        items.filter { $0.studentID == studentID }
    }

    /// Drops rows for children no longer on the roster; keeps whole-class rows.
    static func restricted(toRoster roster: Set<UUID>, _ items: [WatchItem]) -> [WatchItem] {
        items.filter { item in
            guard let studentID = item.studentID else { return true }
            return roster.contains(studentID)
        }
    }

    /// The calendar week that holds `day`, as a half-open interval.
    static func week(containing day: Date, calendar: Calendar = AppCalendar.shared) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: day)
            ?? DateInterval(start: calendar.startOfDay(for: day), duration: 7 * 24 * 60 * 60)
    }

    /// Rows the guide raised inside `week`: the `date` is what counts, never a
    /// due date. A Watch todo written last month but due this week is already
    /// in the todo list; this list is about what was raised.
    static func touched(in week: DateInterval, _ items: [WatchItem]) -> [WatchItem] {
        items.filter { $0.date >= week.start && $0.date < week.end }
    }

    /// Rows bundled per child, children by name, the whole class last. Rows
    /// inside a group keep the order they arrived in.
    static func grouped(_ items: [WatchItem], nameFor: (UUID) -> String) -> [WatchGroup] {
        var order: [UUID?] = []
        var byStudent: [UUID?: [WatchItem]] = [:]
        for item in items {
            if byStudent[item.studentID] == nil { order.append(item.studentID) }
            byStudent[item.studentID, default: []].append(item)
        }
        let groups = order.map { studentID -> WatchGroup in
            WatchGroup(
                studentID: studentID,
                name: studentID.map(nameFor) ?? WatchGroup.wholeClassName,
                items: byStudent[studentID] ?? []
            )
        }
        return groups.sorted { lhs, rhs in
            switch (lhs.studentID, rhs.studentID) {
            case (nil, nil): return false
            case (nil, _): return false
            case (_, nil): return true
            default:
                if lhs.name != rhs.name {
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        }
    }

    // MARK: Helpers

    private static func trimmed(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(textLimit))
    }

    private static func precedes(_ lhs: WatchItem, _ rhs: WatchItem) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        if lhs.text != rhs.text { return lhs.text < rhs.text }
        return lhs.id < rhs.id
    }
}
