//
//  MCPNotebookTools+PresentationHistory.swift
//  Cosmic Daybook
//
//  One child's presentations, dated and newest first — the answer to "when
//  did she have this" and, narrowed to one lesson, to "has she ever had it".
//
//  The rows are presented `CDLessonAssignment`s, the same records the
//  Presentations screen lists. A lesson filter also reads the child's
//  `CDLessonPresentation` record for it, because a checklist mark or a bulk
//  "previously presented" import can put a lesson on record without a dated
//  assignment, and "never had it" must not be said while the record disagrees.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Tool

    static func studentPresentationHistoryTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_presentation_history",
            title: "Student Presentation History",
            description: "Dated lesson presentations for one student, newest first. "
                + "Use this instead of inferring lesson history from work records. "
                + "Ten by default; raise limit (up to 200) or pass since to go further back. "
                + "Pass lesson to ask \"has she ever had X\" — the answer covers both dated "
                + "presentations and the lesson's presentation record, and says so when the record "
                + "marks a lesson no dated presentation shows. A lesson she has had more than once "
                + "carries its ordinal and, where the record says so, why — \"(2nd time; second pass)\".",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, nickname, or id"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum presentations to return, 1-200 (default 10)"
                    ],
                    "since": [
                        "type": "string",
                        "description": "YYYY-MM-DD. Only presentations given on or after this day."
                    ],
                    "lesson": [
                        "type": "string",
                        "description": "Only presentations of this lesson: a lesson id from find_lessons, or its name"
                    ]
                ],
                "required": ["student_name"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try fetchPresentationHistory(arguments: arguments, in: context())
            }
        )
    }

    // MARK: - Query

    private static func fetchPresentationHistory(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(requireString(arguments, "student_name"), in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        let limit = intArgument(arguments, "limit", default: 10, range: 1...200)
        let since: Date? = try dayArgument(arguments, "since").map(AppCalendar.startOfDay)
        let lesson: CDLesson? = try nonEmpty(arguments["lesson"]?.stringValue)
            .map { try resolveLessonReference($0, in: modelContext) }

        let request = CDFetchRequest(CDLessonAssignment.self)
        var clauses: [NSPredicate] = [
            NSPredicate(format: "stateRaw == %@", LessonAssignmentState.presented.rawValue)
        ]
        if let lessonID = lesson?.id?.uuidString {
            clauses.append(NSPredicate(format: "lessonID == %@", lessonID))
        }
        if let since {
            clauses.append(NSPredicate(format: "presentedAt >= %@", since as NSDate))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: clauses)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \CDLessonAssignment.presentedAt, ascending: false)
        ]
        let matching = modelContext.safeFetch(request).filter { $0.resolvedStudentIDs.contains(studentID) }
        let shown = matching.prefix(limit)

        var scope: [String] = []
        if let lesson { scope.append("of \(lesson.name)") }
        if let since { scope.append("since \(dayString(since))") }
        let scopeText = scope.isEmpty ? "" : " " + scope.joined(separator: ", ")
        let record = lesson.map { presentationRecordLine(for: studentID, lesson: $0, in: modelContext) } ?? ""

        guard !shown.isEmpty else {
            return "No presentations\(scopeText) are recorded for \(student.fullName).\(record)"
        }

        let ordinals = repeatOrdinals(matching)
        let lines = shown.compactMap { assignment -> String? in
            guard let id = assignment.id else { return nil }
            let snapshotTitle = assignment.lessonTitleSnapshot?.trimmed() ?? ""
            let title = snapshotTitle.isEmpty ? (assignment.lesson?.name ?? "Lesson") : snapshotTitle
            // Linked notes are counted for this child only: a note about
            // another child on the same group presentation is not hers.
            let notes = ((assignment.unifiedNotes?.allObjects as? [CDNote]) ?? [])
                .filter { $0.scope.applies(to: studentID) && !$0.body.trimmed().isEmpty }
            let noteText = notes.isEmpty
                ? "no linked observation"
                : "\(notes.count) linked observation(s)\(observationScopeNote(notes, for: studentID, in: modelContext))"
            return "- [presentation id=\(id.uuidString)] \(dayString(assignment.presentedAt)) — "
                + "\(title)\(repeatSuffix(assignment, ordinal: ordinals[id])) (\(noteText))"
        }
        let count = matching.count > shown.count
            ? " (showing \(shown.count) of \(matching.count); raise limit or pass since for the rest)"
            : " (\(shown.count))"
        return "Presentations\(scopeText) for \(student.fullName)\(count):\n"
            + lines.joined(separator: "\n") + record
    }

    // MARK: - Lessons Given More Than Once

    /// Presentation id → which giving of that lesson it was, oldest first, for
    /// the lessons this child has had more than once. A lesson with a single
    /// row is absent, so an ordinary presentation reads as it always has.
    ///
    /// Counted over the rows already fetched, so a narrow `since` window
    /// numbers the rows it returned rather than paying for a second read of
    /// the whole record.
    private static func repeatOrdinals(_ rows: [CDLessonAssignment]) -> [UUID: Int] {
        var ordinals: [UUID: Int] = [:]
        for (_, group) in Dictionary(grouping: rows, by: \.lessonID) where group.count > 1 {
            let oldestFirst = group.sorted {
                ($0.presentedAt ?? .distantPast) < ($1.presentedAt ?? .distantPast)
            }
            for (offset, assignment) in oldestFirst.enumerated() {
                if let id = assignment.id { ordinals[id] = offset + 1 }
            }
        }
        return ordinals
    }

    /// " (2nd time; second pass)" — the ordinal, and the reason if the record
    /// carries one. Empty for a lesson given once, and for the first giving of
    /// one given several times: only a repeat needs saying.
    private static func repeatSuffix(_ assignment: CDLessonAssignment, ordinal: Int?) -> String {
        guard let ordinal, ordinal > 1 else { return "" }
        let purpose = RepeatPurpose.parse(notes: assignment.notes)
            .map { "; \($0.displayName.lowercased())" } ?? ""
        return " (\(ordinalText(ordinal)) time\(purpose))"
    }

    // MARK: - Detail

    /// The child's `CDLessonPresentation` for the lesson, as a closing line —
    /// its state and the dates it carries. Empty when there is no record.
    private static func presentationRecordLine(
        for studentID: UUID, lesson: CDLesson, in modelContext: NSManagedObjectContext
    ) -> String {
        guard let lessonID = lesson.id?.uuidString else { return "" }
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND lessonID == %@", studentID.uuidString, lessonID
        )
        let records = modelContext.safeFetch(request)
            .sorted { ($0.presentedAt ?? .distantPast) > ($1.presentedAt ?? .distantPast) }
        guard let record = records.first else {
            return "\nNo presentation record of \(lesson.name) for this child either."
        }
        var parts: [String] = [record.state.rawValue]
        if let presented = record.presentedAt { parts.append("presented \(dayString(presented))") }
        if let mastered = record.masteredAt { parts.append("mastered \(dayString(mastered))") }
        return "\nPresentation record of \(lesson.name): " + parts.joined(separator: "; ") + "."
    }

    /// ", shared with Ora Pardo" when a linked note is about several children,
    /// or ", written for the whole class" — so a group note is not mistaken
    /// for one about this child alone.
    private static func observationScopeNote(
        _ notes: [CDNote], for studentID: UUID, in modelContext: NSManagedObjectContext
    ) -> String {
        if notes.contains(where: { $0.scope == .all }) {
            return ", written for the whole class"
        }
        let others = Set(notes.flatMap { $0.scope.studentIDs ?? [] }).subtracting([studentID])
        guard !others.isEmpty else { return "" }
        return ", shared with \(studentNames(for: Array(others), in: modelContext))"
    }
}
