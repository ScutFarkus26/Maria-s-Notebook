//
//  MCPNotebookTools+ReadyForNext.swift
//  Cosmic Daybook
//
//  The record-side queue: who is waiting on a next lesson.
//
//  `students_pending` reads the plan — one lesson in, every child still due
//  for it out. This reads the record from the other end: the confirmations
//  the guide made at capture and the mastery marks she has entered, turned
//  into the lessons those marks point at. It is the "who is ready for what"
//  list the notebook has never had, and the answer arrives already shaped for
//  `schedule_presentation`, since forming the group is what the guide is
//  about to do.
//
//  It proposes and never writes — the closing call is text for her to send,
//  not something this tool does on her behalf.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Tool

    static func studentsReadyTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "students_ready",
            title: "Students Ready for a Next Lesson",
            description: "Reads confirmation and mastery off the presentation record and proposes "
                + "what comes next: every enrolled child confirmed ready at capture, or marked "
                + "mastered, on a lesson whose successor in the same sub-area is neither on her "
                + "record nor already planned or scheduled for her. Grouped by child or by lesson; "
                + "the by-lesson form closes each group with the exact schedule_presentation call "
                + "for its ready children on the next school day. A sub-area that requires practice "
                + "holds a child at almost-ready while her own work on the lesson she just had is "
                + "still open. Never writes.",
            inputSchema: readyForNextSchema,
            annotations: .readOnly,
            handler: { arguments in
                try describeStudentsReady(arguments: arguments, in: context())
            }
        )
    }

    private static var readyForNextSchema: JSONValue {
        [
            "type": "object",
            "properties": [
                "group_by": [
                    "type": "string",
                    "enum": ["student", "lesson"],
                    "description": .string(
                        "\"student\" (default) lists each child and the lessons she is ready for; "
                            + "\"lesson\" lists each lesson and the children ready for it, with the "
                            + "schedule_presentation call to form the group"
                    )
                ],
                "student": [
                    "type": "string",
                    "description": "Only this child: a student id from list_students, or her name"
                ],
                "area": [
                    "type": "string",
                    "description": "Only lessons whose area matches, e.g. \"Math\""
                ],
                "basis": [
                    "type": "string",
                    "enum": ["either", "confirmed", "mastered"],
                    "description": .string(
                        "Which mark puts a child in the queue: \"either\" (default), only the "
                            + "guide's capture-time confirmation, or only a mastery mark"
                    )
                ],
                "include_almost_ready": [
                    "type": "boolean",
                    "description": "Include children held by an open practice gate (default true)"
                ]
            ]
        ]
    }

    // MARK: - Query

    /// One queue entry with its records resolved.
    private struct ReadyRow {
        let item: ReadyForNextItem
        let student: CDStudent
        let lesson: CDLesson
        let next: CDLesson
    }

    private static func describeStudentsReady(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        var students = DataQueryService(context: modelContext)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: true)
            .filter { $0.id != nil }
        if let reference = nonEmpty(arguments["student"]?.stringValue) {
            let wanted = try resolveStudentReference(reference, in: modelContext)
            students = students.filter { $0.id == wanted.id }
            guard !students.isEmpty else {
                return "\(wanted.fullName) is not on the enrolled roster, so she is not in the queue."
            }
        }
        guard !students.isEmpty else { return "No students are enrolled." }

        let studentsByID = Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString, student) } },
            uniquingKeysWith: { first, _ in first }
        )
        let lessons = modelContext.safeFetch(CDFetchRequest(CDLesson.self))
        let lessonsByID = Dictionary(
            lessons.compactMap { lesson in lesson.id.map { ($0.uuidString, lesson) } },
            uniquingKeysWith: { first, _ in first }
        )
        let index = PresentationRecordIndex(students: Set(studentsByID.keys), in: modelContext)
        let items = ReadyForNextEngine.items(
            studentIDs: Array(studentsByID.keys), lessons: lessons, index: index, in: modelContext
        )

        let rows = items.compactMap { item -> ReadyRow? in
            guard let student = studentsByID[item.studentID],
                  let lesson = lessonsByID[item.lessonID],
                  let next = lessonsByID[item.nextLessonID] else { return nil }
            return ReadyRow(item: item, student: student, lesson: lesson, next: next)
        }
        .filter { keeps($0, arguments: arguments) }
        guard !rows.isEmpty else {
            return "Nobody is waiting on a next lesson: every confirmed or mastered lesson's "
                + "successor is given or planned."
        }
        return arguments["group_by"]?.stringValue == "lesson"
            ? byLesson(rows, in: modelContext)
            : byStudent(rows)
    }

    /// The three narrowing arguments, asked of one row.
    ///
    /// `area` reads the *next* lesson's area: the lesson being proposed is the
    /// one the guide means when she narrows the queue to Math.
    private static func keeps(_ row: ReadyRow, arguments: [String: JSONValue]) -> Bool {
        switch arguments["basis"]?.stringValue {
        case "confirmed" where row.item.basis != .confirmed: return false
        case "mastered" where row.item.basis != .mastered: return false
        default: break
        }
        if arguments["include_almost_ready"]?.boolValue == false, row.item.tier == .almostReady {
            return false
        }
        guard let area = nonEmpty(arguments["area"]?.stringValue) else { return true }
        return row.next.area.folded().contains(area.folded())
    }

    // MARK: - Output

    /// "Avital Beyderman:" then one line per lesson she is ready for.
    private static func byStudent(_ rows: [ReadyRow]) -> String {
        let groups = Dictionary(grouping: rows) { $0.student.fullName }
        var lines: [String] = []
        for name in groups.keys.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
            lines.append("\(name):")
            let entries = (groups[name] ?? []).sorted {
                $0.next.name.localizedCaseInsensitiveCompare($1.next.name) == .orderedAscending
            }
            lines.append(contentsOf: entries.map { "- " + studentLine($0) })
        }
        return lines.joined(separator: "\n")
    }

    /// "- [lesson id=…] Distributive Law — after Commutative Law (confirmed 2026-03-11)",
    /// with " — almost: <reason>" when a gate still holds her.
    private static func studentLine(_ row: ReadyRow) -> String {
        let nextID = row.next.id?.uuidString ?? "unknown"
        let mark = row.item.basis.rawValue
        let when = row.item.basisDate.map { " \(dayString($0))" } ?? ""
        var line = "[lesson id=\(nextID)] \(row.next.name) — after \(row.lesson.name) (\(mark)\(when))"
        if let reason = row.item.reasons.first {
            line += " — almost: \(reason)"
        }
        return line
    }

    /// "[lesson id=…] Distributive Law — Math › Laws — ready (2): …; almost ready (1): …",
    /// followed by the call that forms the group.
    private static func byLesson(_ rows: [ReadyRow], in modelContext: NSManagedObjectContext) -> String {
        let groups = Dictionary(grouping: rows) { $0.item.nextLessonID }
        let day = nextSchoolDay(in: modelContext)
        var lines: [String] = []
        for lessonID in groups.keys.sorted(by: { lhs, rhs in
            lessonName(groups[lhs]) .localizedCaseInsensitiveCompare(lessonName(groups[rhs])) == .orderedAscending
        }) {
            guard let group = groups[lessonID], let lesson = group.first?.next else { continue }
            let ready = sortedNames(group.filter { $0.item.tier == .ready })
            let almost = group.filter { $0.item.tier == .almostReady }
                .sorted { $0.student.fullName.localizedCaseInsensitiveCompare($1.student.fullName)
                    == .orderedAscending }
            var parts: [String] = [describeLesson(lesson)]
            parts.append("ready (\(ready.count)): " + (ready.isEmpty ? "none" : ready.joined(separator: ", ")))
            if !almost.isEmpty {
                let named = almost.map { "\($0.student.fullName) (\($0.item.reasons.joined(separator: "; ")))" }
                parts.append("almost ready (\(almost.count)): " + named.joined(separator: ", "))
            }
            lines.append(parts[0] + " — " + parts.dropFirst().joined(separator: "; "))
            if !ready.isEmpty {
                lines.append(scheduleCall(lessonID: lessonID, names: ready, day: day))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func lessonName(_ rows: [ReadyRow]?) -> String {
        rows?.first?.next.name ?? ""
    }

    private static func sortedNames(_ rows: [ReadyRow]) -> [String] {
        rows.map(\.student.fullName)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The call, built as JSON rather than spliced together, so a name with a
    /// quote or a backslash in it stays a call the model can paste back.
    private static func scheduleCall(lessonID: String, names: [String], day: Date) -> String {
        let call: JSONValue = .object([
            "name": .string("schedule_presentation"),
            "arguments": .object([
                "lesson": .string(lessonID),
                "student_names": .array(names.map { .string($0) }),
                "date": .string(dayString(day))
            ])
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(call),
              let json = String(bytes: data, encoding: .utf8) else { return "" }
        return "To schedule: " + json
    }

    /// The first school day from tomorrow forward, looking a fortnight ahead.
    /// A run of non-school days longer than that is a holiday, not a date to
    /// keep walking past, so the proposal falls back to tomorrow and lets
    /// `schedule_presentation` refuse it.
    private static func nextSchoolDay(in modelContext: NSManagedObjectContext) -> Date {
        let calendar = AppCalendar.shared
        let today = AppCalendar.startOfDay(Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        var day = tomorrow
        for _ in 0..<14 {
            if !SchoolCalendarService.shared.isNonSchoolDaySync(day, using: modelContext) { return day }
            guard let following = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = following
        }
        return tomorrow
    }
}
