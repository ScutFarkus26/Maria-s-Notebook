//
//  MCPNotebookTools+Presentations.swift
//  Maria's Notebook
//
//  Filing a presentation the guide describes in prose: the lesson they gave,
//  who was there, and what they noticed.
//
//  The write runs the same lifecycle as the in-app capture review
//  (LifecycleService.recordPresentation + PresentationOutcomePersistenceService),
//  so a presentation filed over MCP is indistinguishable from one recorded
//  in the command bar.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Tool

    static func recordPresentationTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "record_presentation",
            title: "Record Presentation",
            description: "Record a lesson the guide gave, with what they observed. Writes the "
                + "presentation into the students' histories exactly as the in-app capture "
                + "review would, and links each observation to it. If the lesson was already "
                + "planned or scheduled for those same students, that plan is completed rather "
                + "than duplicated. Use find_lessons first so the lesson is unambiguous. "
                + "Recording the same lesson, students, and day twice updates that presentation "
                + "instead of creating a second one.",
            inputSchema: recordPresentationSchema,
            annotations: .write,
            handler: { arguments in
                let modelContext = context()
                let filing = try makeFiling(arguments: arguments, in: modelContext)
                return try file(filing, in: modelContext)
            }
        )
    }

    private static let recordPresentationSchema: JSONValue = [
        "type": "object",
        "properties": [
            "lesson": [
                "type": "string",
                "description": "The lesson presented: a lesson id from find_lessons, or its exact name"
            ],
            "student_names": [
                "type": "array",
                "items": ["type": "string"],
                "minItems": 1,
                "description": "The students the lesson was given to: first names, full names, or nicknames"
            ],
            "date": [
                "type": "string",
                "description": "The day it was presented, YYYY-MM-DD (default today)"
            ],
            "group_observation": [
                "type": "string",
                "description": .string("What happened in the presentation as a whole — "
                    + "the part that is about the group, not one child")
            ],
            "student_observations": [
                "type": "array",
                "description": "What the guide noticed about individual children in this presentation",
                "items": [
                    "type": "object",
                    "properties": [
                        "student": [
                            "type": "string",
                            "description": "One of the students named in student_names"
                        ],
                        "observation": [
                            "type": "string",
                            "description": "The observation, as the guide phrased it"
                        ],
                        "needs_follow_up": [
                            "type": "boolean",
                            "description": "Flag this observation for the follow-up inbox (default false)"
                        ]
                    ],
                    "required": ["student", "observation"]
                ]
            ]
        ],
        "required": ["lesson", "student_names"]
    ]

    // MARK: - Filing

    /// One `record_presentation` call with every reference resolved to a
    /// record. Built before anything is written, so a bad name or date fails
    /// the call without leaving a half-filed presentation behind.
    private struct PresentationFiling {
        let lesson: CDLesson
        let lessonID: UUID
        let students: [CDStudent]
        let studentIDs: [UUID]
        let presentedAt: Date
        let groupObservation: String
        let observations: [UUID: String]
        /// Students whose observation the guide flagged for the follow-up inbox.
        let followUpIDs: Set<UUID>
    }

    private static func makeFiling(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> PresentationFiling {
        let lesson = try resolveLessonReference(requireString(arguments, "lesson"), in: modelContext)
        guard let lessonID = lesson.id else {
            throw MCPToolError("\"\(lesson.name)\" has no saved identifier and cannot be presented.")
        }

        let names = stringArrayArgument(arguments, "student_names")
        guard !names.isEmpty else {
            throw MCPToolError("At least one student name is required.")
        }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let studentIDs = students.compactMap(\.id)
        guard studentIDs.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }

        let observed = try studentObservations(arguments, presented: studentIDs, in: modelContext)
        return PresentationFiling(
            lesson: lesson,
            lessonID: lessonID,
            students: students,
            studentIDs: studentIDs,
            presentedAt: try dayArgument(arguments, "date") ?? Date(),
            groupObservation: arguments["group_observation"]?.stringValue?.trimmed() ?? "",
            observations: observed.bodies,
            followUpIDs: observed.followUpIDs
        )
    }

    /// Parses `student_observations`, refusing an observation about a child who
    /// is not in `student_names` — that is the model mis-reading the account,
    /// not a note to file quietly against the wrong presentation.
    private static func studentObservations(
        _ arguments: [String: JSONValue],
        presented studentIDs: [UUID],
        in modelContext: NSManagedObjectContext
    ) throws -> (bodies: [UUID: String], followUpIDs: Set<UUID>) {
        var bodies: [UUID: String] = [:]
        var followUpIDs: Set<UUID> = []

        for entry in arguments["student_observations"]?.arrayValue ?? [] {
            guard let fields = entry.objectValue else {
                throw MCPToolError("Each student_observations entry must be an object.")
            }
            let student = try resolveStudentReference(requireString(fields, "student"), in: modelContext)
            guard let studentID = student.id, studentIDs.contains(studentID) else {
                throw MCPToolError(
                    "\(student.fullName) has an observation but is not in student_names. List every "
                        + "child the lesson was given to, or file that note with create_observation."
                )
            }
            let body = try requireString(fields, "observation")
            bodies[studentID] = bodies[studentID].map { "\($0)\n\n\(body)" } ?? body
            if fields["needs_follow_up"]?.boolValue == true {
                followUpIDs.insert(studentID)
            }
        }
        return (bodies, followUpIDs)
    }

    private static func file(
        _ filing: PresentationFiling, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let resolved = resolveAssignment(for: filing, in: modelContext)
        let assignment: CDLessonAssignment
        let notes: [CDNote]
        do {
            assignment = try LifecycleService.recordPresentation(
                from: resolved.assignment,
                presentedAt: filing.presentedAt,
                modelContext: modelContext
            )
            notes = try PresentationOutcomePersistenceService.persistObservations(
                groupObservation: filing.groupObservation,
                studentObservations: filing.observations,
                studentIDs: filing.studentIDs,
                presentationID: assignment.id,
                context: modelContext
            )
        } catch {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be recorded: \(error.localizedDescription)")
        }

        // The in-app flow stamps notes as they are written; a presentation
        // filed for an earlier day should carry that day's date instead.
        for note in notes {
            note.createdAt = filing.presentedAt
            if case .student(let studentID) = note.scope, filing.followUpIDs.contains(studentID) {
                note.needsFollowUp = true
            }
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be saved.")
        }
        return receipt(for: assignment, filing: filing, origin: resolved.origin, noteCount: notes.count)
    }

    // MARK: - Presentation Resolution

    /// Where the recorded presentation came from, so the receipt can tell the
    /// guide whether a plan was completed or a new record created.
    private enum PresentationOrigin {
        case alreadyRecorded
        case plannedLesson
        case newRecord
    }

    /// Prefers a presentation already recorded for this lesson, these students
    /// and this day (so re-filing the same account edits it rather than
    /// duplicating it), then a plan waiting to be given, and finally a new
    /// record — mirroring the command bar's `resolvePresentation`.
    private static func resolveAssignment(
        for filing: PresentationFiling, in modelContext: NSManagedObjectContext
    ) -> (assignment: CDLessonAssignment, origin: PresentationOrigin) {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", filing.lessonID.uuidString)
        let expected = Set(filing.studentIDs)
        let candidates = modelContext.safeFetch(request).filter { Set($0.studentUUIDs) == expected }

        if let sameDay = candidates.first(where: { assignment in
            guard assignment.isPresented, let recordedAt = assignment.presentedAt else { return false }
            return AppCalendar.shared.isDate(recordedAt, inSameDayAs: filing.presentedAt)
        }) {
            return (sameDay, .alreadyRecorded)
        }

        let planned = candidates
            .filter { !$0.isPresented }
            .sorted {
                if $0.isScheduled != $1.isScheduled { return $0.isScheduled }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            .first
        if let planned {
            return (planned, .plannedLesson)
        }

        return (
            PresentationFactory.makeDraft(
                lesson: filing.lesson, students: filing.students, context: modelContext
            ),
            .newRecord
        )
    }

    // MARK: - Receipt

    private static func receipt(
        for assignment: CDLessonAssignment,
        filing: PresentationFiling,
        origin: PresentationOrigin,
        noteCount: Int
    ) -> String {
        let opening: String
        switch origin {
        case .alreadyRecorded:
            opening = "Updated the presentation already recorded"
        case .plannedLesson:
            opening = "Recorded the lesson planned for them"
        case .newRecord:
            opening = "Recorded"
        }
        let id = assignment.id?.uuidString ?? "unknown"
        let who = filing.students.map(\.fullName).joined(separator: ", ")
        let notes = noteCount == 0 ? "no observations linked" : "\(noteCount) observation(s) linked"
        return "\(opening) [presentation id=\(id)]: \(filing.lesson.name) "
            + "to \(who) on \(dayString(filing.presentedAt)) — \(notes)."
    }
}
