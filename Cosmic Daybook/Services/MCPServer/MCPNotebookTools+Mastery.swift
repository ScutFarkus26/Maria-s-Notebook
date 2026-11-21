// MCPNotebookTools+Mastery.swift
// The mastery write: `mark_mastered` marks a child's presentation records for
// a lesson mastered, which is the only thing that counts the lesson mastered
// in her sequence standing. Recording a presentation never does. It writes
// through `MasteryMarking`, as the Checklist and the presentation sheet do:
// every record she has for the lesson is marked, and her open work on it
// closes as Mastered. `unmark: true` takes the mark back the same way.
//
// One lesson or a `marks` array of them: either way every child is resolved
// and her rows found before anything is written, so one unrecorded name
// refuses the whole call rather than half-marking the rest.

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Mark Mastered

    static func markMasteredTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "mark_mastered",
            title: "Mark Lesson Mastered",
            description: "Record that the guide assessed a lesson as mastered for one or more children. Marks "
                + "each child's existing presentation records for that lesson mastered, "
                + "which is what counts the lesson mastered in her sequence (student_record, tracks section); "
                + "record_presentation alone never does. It also closes her own open work on the lesson as "
                + "Mastered; on work she shares with classmates only her part is finished, and the shared "
                + "work closes, as Finished, when the last child's part is done. The reply says which, "
                + "child by child. Refuses, and writes nothing, if any named "
                + "child has no presentation of the lesson on record: file it with record_presentation "
                + "first. Only use this when the guide says they assessed mastery; never infer it. "
                + "To confirm a whole list at once pass marks, an array of these same fields: every "
                + "child is checked before anything is written and one save covers them all. "
                + "mastery_candidates proposes that list, with its evidence, and hands back the call to make. "
                + "Pass unmark: true to take a mark back instead, only when the guide says it was a "
                + "mistake: her records go back to presented, and her presentations and work stay as they are.",
            inputSchema: markMasteredSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try undoingOnFailure(context()) { modelContext in
                    let requests = try makeRequests(arguments: arguments, in: modelContext)
                    let unmark = arguments["unmark"]?.boolValue == true
                    return try apply(requests, unmark: unmark, in: modelContext)
                }
            }
        )
    }

    private static let markMasteredSchema: JSONValue = {
        var properties = masteryProperties
        properties["marks"] = [
            "type": "array",
            "description": .string("Several lessons in one call, each with the fields above "
                + "(lesson, student_names, date)"),
            "items": [
                "type": "object",
                "properties": JSONValue.object(masteryProperties).withoutDescriptions,
                "required": ["lesson", "student_names"]
            ]
        ]
        properties["unmark"] = [
            "type": "boolean",
            "description": .string("True takes the mastery mark back for every lesson and child named, "
                + "instead of marking it (default false)")
        ]
        return .object(["type": "object", "properties": .object(properties)])
    }()

    /// The fields one mark takes, shared by the single form and each item of
    /// the `marks` batch.
    private static let masteryProperties: [String: JSONValue] = [
        "lesson": [
            "type": "string",
            "description": "The lesson mastered: a lesson id from find_lessons, or its exact name"
        ],
        "student_names": [
            "type": "array",
            "items": ["type": "string"],
            "minItems": 1,
            "description": "The children assessed as having mastered it: first names, full names, or nicknames"
        ],
        "date": [
            "type": "string",
            "description": .string("The day the guide assessed mastery, YYYY-MM-DD "
                + "(default today). Use it when filing an assessment made on an earlier day.")
        ]
    ]

    // MARK: - Resolution

    /// One lesson of a `mark_mastered` call with every reference resolved and
    /// every child's records found. Built before anything is written, so a
    /// child with no presentation on record fails the whole call rather than
    /// leaving the others half-marked.
    private struct MasteryRequest {
        let lesson: CDLesson
        let lessonID: UUID
        let assessedAt: Date
        let students: [CDStudent]
    }

    /// The call's requests, one per lesson: the single form, or every item of
    /// `marks`. All of them are resolved here, before `apply` writes anything,
    /// so an unrecorded child in the last item leaves the first unmarked too.
    private static func makeRequests(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> [MasteryRequest] {
        // One lesson table for the whole call, however many marks name a lesson.
        let lessons = LessonReferences(in: modelContext)
        guard let batch = arguments["marks"]?.arrayValue else {
            return [try makeRequest(arguments: arguments, lessons: lessons, in: modelContext)]
        }
        guard arguments["lesson"] == nil, arguments["student_names"] == nil else {
            throw MCPToolError(
                "Pass either one lesson's fields or a marks array, not both. Put every lesson in marks."
            )
        }
        guard !batch.isEmpty else {
            throw MCPToolError("marks is empty — list at least one lesson.")
        }
        return try batch.enumerated().map { index, item in
            guard let fields = item.objectValue else {
                throw MCPToolError("marks[\(index)] must be an object.")
            }
            do {
                return try makeRequest(arguments: fields, lessons: lessons, in: modelContext)
            } catch let error as MCPToolError {
                throw MCPToolError("marks[\(index)]: \(error.message)")
            }
        }
    }

    private static func makeRequest(
        arguments: [String: JSONValue], lessons: LessonReferences, in modelContext: NSManagedObjectContext
    ) throws -> MasteryRequest {
        let lesson = try lessons.resolve(requireString(arguments, "lesson"))
        guard let lessonID = lesson.id else {
            throw MCPToolError("\"\(lesson.name)\" has no saved identifier and cannot be marked.")
        }

        let names = stringArrayArgument(arguments, "student_names")
        guard !names.isEmpty else {
            throw MCPToolError("At least one student name is required.")
        }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let assessedAt = try dayArgument(arguments, "date") ?? Date()

        var unrecorded: [String] = []
        for student in students {
            guard let studentID = student.id else {
                throw MCPToolError("A matched student record has no identifier.")
            }
            if MasteryMarking.rows(of: studentID, lessonID: lessonID, in: modelContext).isEmpty {
                unrecorded.append(student.fullName)
            }
        }

        guard unrecorded.isEmpty else {
            let list = unrecorded.joined(separator: ", ")
            throw MCPToolError(
                "No presentation of \"\(lesson.name)\" is on record for \(list), so nothing was "
                    + "marked. Record the presentation first with record_presentation, or check "
                    + "the lesson with find_lessons if the guide meant a different one."
            )
        }
        return MasteryRequest(lesson: lesson, lessonID: lessonID, assessedAt: assessedAt, students: students)
    }

    // MARK: - Writing

    /// Marks (or unmarks) every resolved request, then saves once. The
    /// receipts read exactly as a run of single calls would, joined in the
    /// order they were given.
    private static func apply(
        _ requests: [MasteryRequest], unmark: Bool, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let applied = requests.map { request in
            let ids = request.students.compactMap(\.id)
            let outcome = unmark
                ? MasteryMarking.unmark(ids, lessonID: request.lessonID, in: modelContext)
                : MasteryMarking.mark(ids, lessonID: request.lessonID, on: request.assessedAt, in: modelContext)
            return (request, outcome)
        }
        guard modelContext.safeSave() else {
            throw MCPToolError(unmark
                ? "The mastery marks could not be saved, so nothing was taken back."
                : "The mastery marks could not be saved, so nothing was marked.")
        }
        return applied.map { request, outcome in
            unmark
                ? describeUnmarking(request, outcome)
                : describeMarking(request, outcome, in: modelContext)
        }.joined(separator: "\n")
    }

    private static func students(_ ids: [UUID], of request: MasteryRequest) -> [CDStudent] {
        ids.compactMap { id in request.students.first { $0.id == id } }
    }

    private static func describeMarking(
        _ request: MasteryRequest, _ outcome: MasteryMarking.Outcome, in modelContext: NSManagedObjectContext
    ) -> String {
        var lines: [String] = []
        let marked = students(outcome.changed, of: request)
        if !marked.isEmpty {
            lines.append("Marked mastered on \(dayString(request.assessedAt)): \(describeLesson(request.lesson))")
            for student in marked {
                lines.append(
                    "- \(student.fullName)\(standingSuffix(on: request.lesson, for: student, in: modelContext))"
                )
            }
        }
        if !outcome.unchanged.isEmpty {
            lines.append("Already mastered, left as recorded:")
            for earlier in outcome.unchanged {
                guard let student = request.students.first(where: { $0.id == earlier.studentID }) else {
                    continue
                }
                lines.append("- \(student.fullName) (mastered \(dayString(earlier.masteredOn)))")
            }
        }
        let workLines = outcome.work.compactMap { closed -> String? in
            guard let student = request.students.first(where: { $0.id == closed.studentID }) else { return nil }
            let phrases = describeWork(closed)
            return phrases.isEmpty ? nil : "- \(student.fullName): " + phrases.joined(separator: "; ")
        }
        if !workLines.isEmpty {
            lines.append("Her open work on it:")
            lines += workLines
        }
        return lines.joined(separator: "\n")
    }

    /// What a mastery mark did to one child's open work, in plain words: her
    /// own rows close as Mastered, and on a row she shares only her part
    /// finishes, closing it as Finished when hers was the last part open.
    static func describeWork(_ closed: MasteryMarking.WorkClosed) -> [String] {
        func items(_ count: Int, _ noun: String) -> String {
            count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
        }
        var phrases: [String] = []
        if closed.asMastered > 0 {
            phrases.append("closed \(items(closed.asMastered, "work item")) as Mastered")
        }
        for stillOpen in closed.partsFinished {
            phrases.append(
                "finished her part of a shared work item; it stays open for \(items(stillOpen, "classmate"))"
            )
        }
        if closed.sharedClosedAsFinished > 0 {
            let rows = closed.sharedClosedAsFinished
            phrases.append(
                "closed \(rows == 1 ? "the shared work item" : "\(rows) shared work items") as Finished, "
                    + "since hers was the last part open"
            )
        }
        return phrases
    }

    private static func describeUnmarking(_ request: MasteryRequest, _ outcome: MasteryMarking.Outcome) -> String {
        var lines: [String] = []
        let unmarked = students(outcome.changed, of: request)
        if !unmarked.isEmpty {
            lines.append("No longer mastered: \(describeLesson(request.lesson))")
            lines += unmarked.map { "- \($0.fullName)" }
        }
        let notMastered = students(outcome.unchanged.map(\.studentID), of: request)
        if !notMastered.isEmpty {
            lines.append("Not marked mastered, so nothing to take back:")
            lines += notMastered.map { "- \($0.fullName)" }
        }
        return lines.joined(separator: "\n")
    }

    /// The child's standing on the lesson's sequence after the mark, so the
    /// guide sees her move along it in the same reply.
    private static func standingSuffix(
        on lesson: CDLesson, for student: CDStudent, in modelContext: NSManagedObjectContext
    ) -> String {
        let area = lesson.area.trimmed()
        let sequence = lesson.sequence.trimmed()
        guard !area.isEmpty, !sequence.isEmpty, let studentID = student.id?.uuidString else { return "" }
        let standing = SequenceStandingLoader.standing(
            forStudentID: studentID, area: area, sequence: sequence, in: modelContext
        )
        guard standing.total > 0 else { return "" }
        return " — \(standing.title): \(standing.masteredCount)/\(standing.total) lessons mastered"
    }
}
