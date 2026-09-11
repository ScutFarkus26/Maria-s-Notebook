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
            description: "Record a lesson the guide gave, with what they observed and what they "
                + "decided for each child (practice, follow-up work, re-present, ready for the next "
                + "lesson, keep observing). Writes the presentation into the students' histories "
                + "exactly as the in-app capture review would, and links each observation to it. "
                + "If the lesson was already planned or scheduled for those same students, that plan "
                + "is completed rather than duplicated. Use find_lessons first so the lesson is "
                + "unambiguous. Recording the same lesson, students, and day twice updates that "
                + "presentation instead of creating a second one. To file a whole day at once pass "
                + "presentations, an array of these same fields; every name is checked before "
                + "anything is written, and one save covers them all.",
            inputSchema: recordPresentationSchema,
            handler: { arguments in
                let modelContext = context()
                let filings: [PresentationFiling]
                if let batch = arguments["presentations"]?.arrayValue {
                    guard !batch.isEmpty else {
                        throw MCPToolError("presentations is empty — list at least one presentation.")
                    }
                    filings = try batch.enumerated().map { index, item in
                        guard let fields = item.objectValue else {
                            throw MCPToolError("presentations[\(index)] must be an object.")
                        }
                        do {
                            return try makeFiling(arguments: fields, in: modelContext)
                        } catch let error as MCPToolError {
                            throw MCPToolError("presentations[\(index)]: \(error.message)")
                        }
                    }
                } else {
                    filings = [try makeFiling(arguments: arguments, in: modelContext)]
                }
                return try file(filings, in: modelContext)
            }
        )
    }

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
        /// The guide's decision per child, in `student_observations` order.
        let outcomes: [CaptureFollowUpPersistence.Entry]
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
            followUpIDs: observed.followUpIDs,
            outcomes: observed.outcomes
        )
    }

    /// What `student_observations` said: each child's note text, who was
    /// flagged for the inbox, and the guide's decisions.
    private struct ParsedObservations {
        let bodies: [UUID: String]
        let followUpIDs: Set<UUID>
        let outcomes: [CaptureFollowUpPersistence.Entry]
    }

    /// Parses `student_observations`, refusing an observation about a child who
    /// is not in `student_names` — that is the model mis-reading the account,
    /// not a note to file quietly against the wrong presentation.
    private static func studentObservations(
        _ arguments: [String: JSONValue],
        presented studentIDs: [UUID],
        in modelContext: NSManagedObjectContext
    ) throws -> ParsedObservations {
        var bodies: [UUID: String] = [:]
        var followUpIDs: Set<UUID> = []
        var outcomes: [CaptureFollowUpPersistence.Entry] = []

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
            if let raw = nonEmpty(fields["follow_up"]?.stringValue) {
                guard let argument = FollowUpArgument(rawValue: raw) else {
                    let allowed = FollowUpArgument.allCases.map(\.rawValue).joined(separator: ", ")
                    throw MCPToolError("follow_up must be one of \(allowed), not \"\(raw)\".")
                }
                outcomes.append(CaptureFollowUpPersistence.Entry(
                    studentID: studentID,
                    observation: body,
                    followUp: argument.outcome,
                    followUpDetail: fields["follow_up_detail"]?.stringValue ?? ""
                ))
            }
        }
        return ParsedObservations(bodies: bodies, followUpIDs: followUpIDs, outcomes: outcomes)
    }

    /// One presentation's written rows, before the save.
    private struct FiledPresentation {
        let filing: PresentationFiling
        let assignment: CDLessonAssignment
        let origin: PresentationOrigin
        let noteCount: Int
        let workCount: Int
    }

    private static func file(
        _ filings: [PresentationFiling], in modelContext: NSManagedObjectContext
    ) throws -> String {
        var filed: [FiledPresentation] = []
        do {
            for filing in filings {
                filed.append(try write(filing, in: modelContext))
            }
        } catch let error as MCPToolError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be recorded: \(error.localizedDescription)")
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The presentation could not be saved.")
        }

        let receipts = filed.map(receipt(for:))
        guard receipts.count > 1 else { return receipts[0] }
        return "Filed \(receipts.count) presentation(s):\n" + receipts.map { "- \($0)" }.joined(separator: "\n")
    }

    /// Writes one presentation, its notes, and the guide's decisions into the
    /// context without saving, so a batch lands or rolls back as a whole.
    private static func write(
        _ filing: PresentationFiling, in modelContext: NSManagedObjectContext
    ) throws -> FiledPresentation {
        let resolved = resolveAssignment(for: filing, in: modelContext)
        let assignment = try LifecycleService.recordPresentation(
            from: resolved.assignment,
            presentedAt: filing.presentedAt,
            modelContext: modelContext
        )
        let notes = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: filing.groupObservation,
            studentObservations: filing.observations,
            studentIDs: filing.studentIDs,
            presentationID: assignment.id,
            context: modelContext
        )

        // The in-app flow stamps notes as they are written; a presentation
        // filed for an earlier day should carry that day's date instead.
        for note in notes {
            note.createdAt = filing.presentedAt
            if case .student(let studentID) = note.scope, filing.followUpIDs.contains(studentID) {
                note.needsFollowUp = true
            }
        }

        var workCount = 0
        if !filing.outcomes.isEmpty, let presentationID = assignment.id {
            workCount = try CaptureFollowUpPersistence.persist(
                filing.outcomes,
                assignment: assignment,
                lesson: filing.lesson,
                persistence: CapturePersistenceContext(
                    lessonID: filing.lessonID,
                    lessonName: filing.lesson.name,
                    presentationID: presentationID,
                    context: modelContext
                )
            )
        }

        return FiledPresentation(
            filing: filing, assignment: assignment, origin: resolved.origin,
            noteCount: notes.count, workCount: workCount
        )
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

    private static func receipt(for filed: FiledPresentation) -> String {
        let filing = filed.filing
        let opening: String
        switch filed.origin {
        case .alreadyRecorded:
            opening = "Updated the presentation already recorded"
        case .plannedLesson:
            opening = "Recorded the lesson planned for them"
        case .newRecord:
            opening = "Recorded"
        }
        let id = filed.assignment.id?.uuidString ?? "unknown"
        let who = filing.students.map(\.fullName).joined(separator: ", ")
        let notes = filed.noteCount == 0 ? "no observations linked" : "\(filed.noteCount) observation(s) linked"
        var text = "\(opening) [presentation id=\(id)]: \(filing.lesson.name) "
            + "to \(who) on \(dayString(filing.presentedAt)) — \(notes)."

        if !filing.outcomes.isEmpty {
            let names = Dictionary(uniqueKeysWithValues: filing.students.compactMap { student in
                student.id.map { ($0, student.fullName) }
            })
            let decisions = filing.outcomes.map { entry in
                "\(names[entry.studentID] ?? "?") — \(entry.followUp.displayName.lowercased())"
            }
            text += " Decisions: \(decisions.joined(separator: "; "))."
            if filed.workCount > 0 {
                text += " \(filed.workCount) work item(s) created."
            }
        }
        return text
    }
}
