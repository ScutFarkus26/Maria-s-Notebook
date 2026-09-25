// MCPNotebookTools+Mastery.swift
// The mastery write: `mark_mastered` flips a child's existing presentation
// record for a lesson to mastered, which is the only thing that advances a
// sequence-track step. Recording a presentation never does.
//
// One lesson or a `marks` array of them: either way every child is resolved
// and her row found before anything is written, so one unrecorded name
// refuses the whole call rather than half-marking the rest.

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Mark Mastered

    static func markMasteredTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "mark_mastered",
            title: "Mark Lesson Mastered",
            description: "Record that the guide assessed a lesson as mastered for one or more children. Flips "
                + "each child's existing presentation record for that lesson to mastered in place, "
                + "which is what advances her sequence-track step; record_presentation alone never "
                + "does. Refuses, and writes nothing, if any named child has no presentation of the "
                + "lesson on record: file it with record_presentation first. Only use this when the "
                + "guide says they assessed mastery; never infer it. To confirm a whole list at once "
                + "pass marks, an array of these same fields: every child is checked before anything "
                + "is written and one save covers them all. mastery_candidates proposes that list, "
                + "with its evidence, and hands back the call to make.",
            inputSchema: markMasteredSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                let modelContext = context()
                let markings = try makeMarkings(arguments: arguments, in: modelContext)
                return apply(markings, in: modelContext)
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

    /// One `mark_mastered` call with every reference resolved to a record and
    /// every child's row found. Built before anything is written, so a child
    /// with no presentation on record fails the whole call rather than leaving
    /// the others half-marked.
    private struct MasteryMarking {
        let lesson: CDLesson
        let assessedAt: Date
        let rows: [(student: CDStudent, row: CDLessonPresentation)]
    }

    /// The call's marks, one per lesson: the single form, or every item of
    /// `marks`. All of them are resolved here, before `apply` writes anything,
    /// so an unrecorded child in the last item leaves the first unmarked too.
    private static func makeMarkings(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> [MasteryMarking] {
        // One lesson table for the whole call, however many marks name a lesson.
        let lessons = LessonReferences(in: modelContext)
        guard let batch = arguments["marks"]?.arrayValue else {
            return [try makeMarking(arguments: arguments, lessons: lessons, in: modelContext)]
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
                return try makeMarking(arguments: fields, lessons: lessons, in: modelContext)
            } catch let error as MCPToolError {
                throw MCPToolError("marks[\(index)]: \(error.message)")
            }
        }
    }

    private static func makeMarking(
        arguments: [String: JSONValue], lessons: LessonReferences, in modelContext: NSManagedObjectContext
    ) throws -> MasteryMarking {
        let lesson = try lessons.resolve(requireString(arguments, "lesson"))
        guard let lessonID = lesson.id?.uuidString else {
            throw MCPToolError("\"\(lesson.name)\" has no saved identifier and cannot be marked.")
        }

        let names = stringArrayArgument(arguments, "student_names")
        guard !names.isEmpty else {
            throw MCPToolError("At least one student name is required.")
        }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let assessedAt = try dayArgument(arguments, "date") ?? Date()

        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID)
        let lessonRows = modelContext.safeFetch(request)

        var rows: [(student: CDStudent, row: CDLessonPresentation)] = []
        var unrecorded: [String] = []
        for student in students {
            guard let studentID = student.id?.uuidString else {
                throw MCPToolError("A matched student record has no identifier.")
            }
            if let row = latestRow(among: lessonRows, for: studentID) {
                rows.append((student, row))
            } else {
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
        return MasteryMarking(lesson: lesson, assessedAt: assessedAt, rows: rows)
    }

    /// A child can hold several rows for one lesson (one per presentation, or
    /// legacy duplicates), so mark the most recent one: mastery is assessed
    /// against the latest presentation, not the first.
    private static func latestRow(
        among rows: [CDLessonPresentation], for studentID: String
    ) -> CDLessonPresentation? {
        rows.filter { $0.studentID == studentID }
            .sorted { ($0.presentedAt ?? .distantPast) > ($1.presentedAt ?? .distantPast) }
            .first
    }

    // MARK: - Writing

    /// Marks every resolved item, then saves once. The receipts read exactly
    /// as a run of single calls would, joined in the order they were given.
    private static func apply(
        _ markings: [MasteryMarking], in modelContext: NSManagedObjectContext
    ) -> String {
        let applied = markings.map { ($0, mark($0, in: modelContext)) }
        _ = modelContext.safeSave()
        return applied.map { marking, outcome in
            describeMarking(
                lesson: marking.lesson, assessedAt: marking.assessedAt, marked: outcome.marked,
                alreadyMastered: outcome.alreadyMastered, in: modelContext
            )
        }.joined(separator: "\n")
    }

    /// Who one mark changed, and who was already mastered before it.
    private struct MarkOutcome {
        var marked: [CDStudent] = []
        var alreadyMastered: [(CDStudent, Date?)] = []
    }

    /// Flips one lesson's rows in place without saving — the batch saves once.
    private static func mark(
        _ marking: MasteryMarking, in modelContext: NSManagedObjectContext
    ) -> MarkOutcome {
        var outcome = MarkOutcome()
        for (student, row) in marking.rows {
            if row.state == .proficient {
                outcome.alreadyMastered.append((student, row.masteredAt))
                continue
            }
            row.state = .proficient
            row.masteredAt = marking.assessedAt
            if (row.lastObservedAt ?? .distantPast) < marking.assessedAt {
                row.lastObservedAt = marking.assessedAt
            }
            outcome.marked.append(student)
        }

        let area = marking.lesson.area.trimmed()
        let sequence = marking.lesson.sequence.trimmed()
        guard !area.isEmpty, !sequence.isEmpty else { return outcome }
        for student in outcome.marked {
            guard let studentID = student.id?.uuidString else { continue }
            SequenceTrackService.checkAndCompleteTrackIfNeeded(
                lessonArea: area, lessonSequence: sequence, studentID: studentID, context: modelContext
            )
        }
        return outcome
    }

    private static func describeMarking(
        lesson: CDLesson, assessedAt: Date, marked: [CDStudent],
        alreadyMastered: [(CDStudent, Date?)], in modelContext: NSManagedObjectContext
    ) -> String {
        let track = try? SequenceTrackService.cdGetTrack(
            area: lesson.area, sequence: lesson.sequence, context: modelContext
        )
        var lines: [String] = []
        if !marked.isEmpty {
            lines.append("Marked mastered on \(dayString(assessedAt)): \(describeLesson(lesson))")
            for student in marked {
                lines.append("- \(student.fullName)\(trackProgressSuffix(track, for: student, in: modelContext))")
            }
        }
        if !alreadyMastered.isEmpty {
            lines.append("Already mastered, left as recorded:")
            for (student, masteredAt) in alreadyMastered {
                lines.append("- \(student.fullName) (mastered \(dayString(masteredAt)))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// The child's standing on the lesson's track after the mark, so the
    /// guide sees the step advance in the same reply.
    private static func trackProgressSuffix(
        _ track: CDTrackEntity?, for student: CDStudent, in modelContext: NSManagedObjectContext
    ) -> String {
        guard let track, let studentID = student.id?.uuidString else { return "" }
        let total = TrackProgressResolver.totalSteps(track: track)
        guard total > 0 else { return "" }
        let presentations = modelContext.safeFetch(CDFetchRequest(CDLessonPresentation.self))
            .filter { $0.studentID == studentID }
        let done = TrackProgressResolver.proficientCount(
            track: track, studentID: studentID, lessonPresentations: presentations
        )
        return " — \(track.title): \(done)/\(total) steps mastered"
    }
}
