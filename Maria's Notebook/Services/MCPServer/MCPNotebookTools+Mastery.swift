// MCPNotebookTools+Mastery.swift
// The mastery write: `mark_mastered` flips a child's existing presentation
// record for a lesson to mastered, which is the only thing that advances a
// sequence-track step. Recording a presentation never does.

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Mark Mastered

    static func markMasteredTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "mark_mastered",
            title: "Mark Lesson Mastered",
            description: "Record that the guide assessed a lesson as mastered for one or more "
                + "children. Flips each child's existing presentation record for that lesson to "
                + "mastered in place — the same change the app's Mastered pill and checklist "
                + "make — which is what advances their sequence-track step; record_presentation "
                + "alone never does. Refuses, and writes nothing, if any named child has no "
                + "presentation of the lesson on record: file it with record_presentation first. "
                + "Only use this when the guide says they assessed mastery; never infer it.",
            inputSchema: markMasteredSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                let modelContext = context()
                let marking = try makeMarking(arguments: arguments, in: modelContext)
                return apply(marking, in: modelContext)
            }
        )
    }

    private static let markMasteredSchema: JSONValue = [
        "type": "object",
        "properties": [
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
        ],
        "required": ["lesson", "student_names"]
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

    private static func makeMarking(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> MasteryMarking {
        let lesson = try resolveLessonReference(requireString(arguments, "lesson"), in: modelContext)
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

    private static func apply(_ marking: MasteryMarking, in modelContext: NSManagedObjectContext) -> String {
        let lesson = marking.lesson
        let area = lesson.area.trimmed()
        let sequence = lesson.sequence.trimmed()

        var marked: [CDStudent] = []
        var alreadyMastered: [(CDStudent, Date?)] = []
        for (student, row) in marking.rows {
            if row.state == .proficient {
                alreadyMastered.append((student, row.masteredAt))
                continue
            }
            row.state = .proficient
            row.masteredAt = marking.assessedAt
            if (row.lastObservedAt ?? .distantPast) < marking.assessedAt {
                row.lastObservedAt = marking.assessedAt
            }
            marked.append(student)
        }

        if !area.isEmpty, !sequence.isEmpty {
            for student in marked {
                guard let studentID = student.id?.uuidString else { continue }
                SequenceTrackService.checkAndCompleteTrackIfNeeded(
                    lessonArea: area, lessonSequence: sequence, studentID: studentID, context: modelContext
                )
            }
        }
        _ = modelContext.safeSave()

        return describeMarking(
            lesson: lesson, assessedAt: marking.assessedAt, marked: marked,
            alreadyMastered: alreadyMastered, in: modelContext
        )
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
