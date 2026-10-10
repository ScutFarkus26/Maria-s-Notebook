//
//  MCPNotebookTools+DataChecks.swift
//  Cosmic Daybook
//
//  Records that look wrong and that nothing repairs on its own.
//
//  Two kinds of bad data were written by old code (the 2026-10-10 bug hunt),
//  and the guide chose to look at them rather than have every device rewrite
//  them: a child's history row left on the old lesson when Change Lesson
//  moved a given presentation to another one, and a birthday before 1900,
//  which a spreadsheet import stored when it read "3/5/15" as the year 3.
//  This tool only lists them, with citations, so they can be checked and
//  fixed by hand. It writes nothing.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func dataChecksTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "data_checks",
            title: "Data Checks",
            description: "Lists records that look wrong and that nothing repairs on its own, for the guide "
                + "to look at; changes nothing. history_lessons: a child's history row filed under a "
                + "different lesson than the given presentation it belongs to (left behind when Change "
                + "Lesson moved a presentation before 2026-10-10; opening the presentation in the app and "
                + "saving it moves its rows). early_birthdays: birthdays before 1900, which an old "
                + "spreadsheet import stored by reading a two-digit year as a year like 0015. Without "
                + "check, runs both.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "check": [
                        "type": "string",
                        "enum": [.string(DataChecks.historyLessons), .string(DataChecks.earlyBirthdays)],
                        "description": "Run only this check"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try describeDataChecks(arguments: arguments, in: context())
            }
        )
    }

    static func describeDataChecks(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let check = nonEmpty(arguments["check"]?.stringValue)
        let known = [DataChecks.historyLessons, DataChecks.earlyBirthdays]
        if let check, !known.contains(check) {
            throw MCPToolError(
                "Unknown check \"\(check)\". Use \(known.joined(separator: " or ")), or leave it out for both."
            )
        }
        var sections = ["Data checks (read-only; nothing was changed)."]
        if check != DataChecks.earlyBirthdays {
            sections.append(describeMisfiledHistoryRows(in: modelContext))
        }
        if check != DataChecks.historyLessons {
            sections.append(describeEarlyBirthdays(in: modelContext))
        }
        return sections.joined(separator: "\n\n")
    }

    private static let dataCheckLineLimit = 200

    private static func describeMisfiledHistoryRows(in modelContext: NSManagedObjectContext) -> String {
        let misfiled = DataChecks.misfiledHistoryRows(in: modelContext)
        guard !misfiled.isEmpty else {
            return "History rows on a different lesson than their presentation: none."
        }
        let lessonIDs = Set(misfiled.flatMap { [$0.row.lessonID, $0.presentation.lessonID] })
        let lessons = DataChecks.lessonNames(ids: lessonIDs, in: modelContext)
        let students = DataChecks.studentNames(ids: Set(misfiled.map(\.row.studentID)), in: modelContext)

        var lines = ["History rows on a different lesson than their presentation: \(misfiled.count)."]
        for item in misfiled.prefix(dataCheckLineLimit) {
            let studentID = item.row.studentID
            let student = students[DataChecks.normalized(studentID)].map { "[student id=\(studentID)] \($0)" }
                ?? "a student no longer on the roster (\(studentID))"
            lines.append(
                "- \(student): history row [historyRow id=\(citationID(item.row.id))] is on "
                    + "\(lessonLabel(item.row.lessonID, names: lessons)), but its presentation "
                    + "[presentation id=\(citationID(item.presentation.id))] "
                    + "(given \(dayString(item.presentation.presentedAt))) is "
                    + "\(lessonLabel(item.presentation.lessonID, names: lessons))"
            )
        }
        if misfiled.count > dataCheckLineLimit {
            lines.append("- and \(misfiled.count - dataCheckLineLimit) more")
        }
        lines.append(
            "Each still counts the child as having had the lesson it is filed under. Opening the presentation "
                + "in the app and saving it moves its rows to the presentation's lesson."
        )
        return lines.joined(separator: "\n")
    }

    private static func lessonLabel(_ lessonID: String, names: [String: String]) -> String {
        guard let name = names[DataChecks.normalized(lessonID)] else {
            return "a lesson no longer in the notebook (\(lessonID))"
        }
        return "[lesson id=\(lessonID)] \(name)"
    }

    private static func describeEarlyBirthdays(in modelContext: NSManagedObjectContext) -> String {
        let students = DataChecks.earlyBirthdays(in: modelContext)
        guard !students.isEmpty else { return "Birthdays before 1900: none." }
        var lines = ["Birthdays before 1900: \(students.count)."]
        for student in students.prefix(dataCheckLineLimit) {
            lines.append(
                "- [student id=\(citationID(student.id))] \(student.fullName): birthday \(dayString(student.birthday))"
            )
        }
        if students.count > dataCheckLineLimit {
            lines.append("- and \(students.count - dataCheckLineLimit) more")
        }
        lines.append("Fix each in the child's profile: Edit, then set the birthday.")
        return lines.joined(separator: "\n")
    }
}

/// The checks behind `data_checks`, apart from their wording.
enum DataChecks {
    static let historyLessons = "history_lessons"
    static let earlyBirthdays = "early_birthdays"

    /// A history row and the presentation it names, filed under different lessons.
    struct MisfiledHistoryRow {
        let row: CDLessonPresentation
        let presentation: CDLessonAssignment
    }

    /// History rows whose presentation (`presentationID`) is on another
    /// lesson, newest presentation first. Rows whose presentation is gone,
    /// or has no lesson, are not this check's business.
    static func misfiledHistoryRows(in context: NSManagedObjectContext) -> [MisfiledHistoryRow] {
        let rowRequest = CDFetchRequest(CDLessonPresentation.self)
        rowRequest.predicate = NSPredicate(format: "presentationID != nil AND presentationID != %@", "")
        let rows = context.safeFetch(rowRequest)
        let presentationIDs = Set(rows.compactMap { $0.presentationID.flatMap(UUID.init(uuidString:)) })
        guard !presentationIDs.isEmpty else { return [] }

        let presentationRequest = CDFetchRequest(CDLessonAssignment.self)
        presentationRequest.predicate = NSPredicate(format: "id IN %@", Array(presentationIDs))
        let presentations = Dictionary(
            context.safeFetch(presentationRequest).compactMap { assignment in
                assignment.id.map { ($0, assignment) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        let misfiled = rows.compactMap { row -> MisfiledHistoryRow? in
            guard let id = row.presentationID.flatMap(UUID.init(uuidString:)),
                  let presentation = presentations[id],
                  !presentation.lessonID.isEmpty,
                  normalized(row.lessonID) != normalized(presentation.lessonID) else { return nil }
            return MisfiledHistoryRow(row: row, presentation: presentation)
        }
        return misfiled.sorted { lhs, rhs in
            let lhsGiven = lhs.presentation.presentedAt ?? .distantPast
            let rhsGiven = rhs.presentation.presentedAt ?? .distantPast
            if lhsGiven != rhsGiven { return lhsGiven > rhsGiven }
            return (lhs.row.id?.uuidString ?? "") < (rhs.row.id?.uuidString ?? "")
        }
    }

    /// Children whose birthday falls before 1 January 1900, by name.
    static func earlyBirthdays(in context: NSManagedObjectContext) -> [CDStudent] {
        guard let cutoff = AppCalendar.shared.date(
            from: DateComponents(year: DateParser.earliestYear, month: 1, day: 1)
        ) else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "birthday != nil AND birthday < %@", cutoff as NSDate)
        return context.safeFetch(request).sorted {
            ($0.fullName, $0.id?.uuidString ?? "") < ($1.fullName, $1.id?.uuidString ?? "")
        }
    }

    /// Lesson names by normalized id.
    static func lessonNames(ids: Set<String>, in context: NSManagedObjectContext) -> [String: String] {
        let uuids = Array(Set(ids.compactMap(UUID.init(uuidString:))))
        guard !uuids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id IN %@", uuids)
        return Dictionary(
            context.safeFetch(request).compactMap { lesson in lesson.id.map { ($0.uuidString, lesson.name) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Student full names by normalized id.
    static func studentNames(ids: Set<String>, in context: NSManagedObjectContext) -> [String: String] {
        let uuids = Array(Set(ids.compactMap(UUID.init(uuidString:))))
        guard !uuids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", uuids)
        return Dictionary(
            context.safeFetch(request).compactMap { student in student.id.map { ($0.uuidString, student.fullName) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// An id string as `UUID.uuidString` writes it, so case can't hide a match.
    static func normalized(_ id: String) -> String {
        UUID(uuidString: id)?.uuidString ?? id
    }
}
