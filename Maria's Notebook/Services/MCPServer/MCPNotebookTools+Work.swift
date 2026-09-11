//
//  MCPNotebookTools+Work.swift
//  Maria's Notebook
//
//  Reading the work children are carrying: what is open, what it grew out of,
//  how far along it is, and when it was finished.
//
//  Assigning and updating work lives in MCPNotebookTools+WorkWrites.swift.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - A Student's Work

    static func studentWorkTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_work",
            title: "Student Work",
            description: "The work one student is carrying: open work with its due dates and "
                + "check-ins, and recently finished work with its outcome. Use this rather than "
                + "inferring what a child is working on from their presentation history.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "include_completed": [
                        "type": "boolean",
                        "description": "Also list recently completed work (default true)"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum completed items to list, 1-30 (default 10)"
                    ]
                ],
                "required": ["student_name"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let student = try resolveStudentReference(
                    requireString(arguments, "student_name"), in: modelContext
                )
                guard let studentID = student.id else {
                    throw MCPToolError("That student record has no identifier.")
                }
                let includeCompleted = arguments["include_completed"]?.boolValue ?? true
                let limit = intArgument(arguments, "limit", default: 10, range: 1...30)
                return describeStudentWork(
                    student: student, studentID: studentID,
                    includeCompleted: includeCompleted, limit: limit, in: modelContext
                )
            }
        )
    }

    private static func describeStudentWork(
        student: CDStudent, studentID: UUID, includeCompleted: Bool, limit: Int,
        in modelContext: NSManagedObjectContext
    ) -> String {
        let all = allWork(for: studentID, in: modelContext)
        let open = all.filter { !$0.isComplete }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let done = all.filter(\.isComplete)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(limit)

        var sections: [String] = []
        if open.isEmpty {
            sections.append("\(student.fullName) has no open work.")
        } else {
            let lines = open.map { work in
                summaryLine(for: work, studentID: studentID, in: modelContext)
            }
            sections.append("Open work for \(student.fullName):\n" + lines.joined(separator: "\n"))
        }

        if includeCompleted && !done.isEmpty {
            let lines = done.map { work -> String in
                let id = work.id?.uuidString ?? "unknown"
                let outcome = work.completionOutcome?.displayName ?? "no outcome recorded"
                return "- [work id=\(id)] \(title(of: work)) — finished "
                    + "\(dayString(work.completedAt)) (\(outcome))"
            }
            sections.append("Recently completed:\n" + lines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func summaryLine(
        for work: CDWorkModel, studentID: UUID?, in modelContext: NSManagedObjectContext
    ) -> String {
        let id = work.id?.uuidString ?? "unknown"
        var details: [String] = [work.status.displayName.lowercased()]
        if let kind = work.kind {
            details.append(kind.displayName.lowercased())
        }
        if let due = work.dueAt {
            details.append("due \(dayString(due))")
        }
        let progress = work.stepProgress
        if progress.total > 0 {
            details.append("\(progress.completed)/\(progress.total) steps")
        }
        if let next = nextCheckIn(for: work, in: modelContext) {
            details.append("check-in \(dayString(next.date))")
        }
        if let studentID, work.isStudentCompleted(studentID) {
            details.append("this student is done")
        }
        let others = workStudentIDs(for: work).filter { $0 != studentID }
        if !others.isEmpty {
            details.append("with \(studentNames(for: others, in: modelContext))")
        }
        return "- [work id=\(id)] \(title(of: work)) (\(details.joined(separator: ", ")))"
    }

    /// The soonest check-in still waiting to happen.
    private static func nextCheckIn(
        for work: CDWorkModel, in modelContext: NSManagedObjectContext
    ) -> CDWorkCheckIn? {
        var soonest: CDWorkCheckIn?
        var soonestDate: Date = .distantFuture
        for checkIn in checkIns(of: work, in: modelContext) where checkIn.status == .scheduled {
            let date: Date = checkIn.date ?? .distantFuture
            if date < soonestDate {
                soonestDate = date
                soonest = checkIn
            }
        }
        return soonest
    }

    /// Check-ins reached through the relationship and through the `workID`
    /// string both; the week-plan drop path writes only the string.
    static func checkIns(of work: CDWorkModel, in modelContext: NSManagedObjectContext) -> [CDWorkCheckIn] {
        WorkDeletionService.checkIns(of: work, in: modelContext)
    }

    static func title(of work: CDWorkModel) -> String {
        nonEmpty(work.title) ?? "Untitled work"
    }

    /// Work a student owns plus work they are a passenger on, so a child
    /// listed only as a collaborator still sees the group's project — but each
    /// assignment once. Linked copies all name the whole group, so the copy
    /// she owns stands in for the others; see `WorkGrouping.visibleWork`.
    static func allWork(
        for studentID: UUID, in modelContext: NSManagedObjectContext
    ) -> [CDWorkModel] {
        WorkGrouping.visibleWork(
            for: studentID,
            among: modelContext.safeFetch(CDFetchRequest(CDWorkModel.self)),
            in: modelContext
        )
    }

    // MARK: - One Work Item

    static func workDetailTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "work_detail",
            title: "Work Detail",
            description: "Everything about one work item by its id: who is on it, the lesson it "
                + "came from, its steps, its check-ins, linked observations, and who has finished it. "
                + "Also reports the record's shape — whether it is one of several linked copies "
                + "(one row per child, each listing the whole group) or a single row shared by "
                + "several children. The two read alike but are not the same record structure.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "work_id": [
                        "type": "string",
                        "description": "The work item's id, as returned by student_work or search_notebook"
                    ]
                ],
                "required": ["work_id"]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let work = try resolveWork(requireString(arguments, "work_id"), in: modelContext)
                return describeWorkDetail(work, in: modelContext)
            }
        )
    }

    static func resolveWork(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDWorkModel {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("work_id must be a uuid, got \"\(reference)\".")
        }
        guard let work = WorkRepository(context: modelContext).fetchWorkModel(id: id) else {
            throw MCPToolError("No work item with id \(reference) was found.")
        }
        return work
    }

    private static func describeWorkDetail(
        _ work: CDWorkModel, in modelContext: NSManagedObjectContext
    ) -> String {
        let id = work.id?.uuidString ?? "unknown"
        var lines = ["[work id=\(id)] \(title(of: work))"]

        lines.append("  Status: \(work.status.displayName)"
            + (work.completionOutcome.map { " — \($0.displayName)" } ?? ""))
        if let kind = work.kind {
            lines.append("  Kind: \(kind.displayName)")
        }
        lines.append("  Students: \(workStudentNames(for: work, in: modelContext))")
        lines.append("  Owner: \(ownerLine(of: work, in: modelContext))")
        lines += shapeLines(of: work, in: modelContext)

        if let lessonID = UUID(uuidString: work.lessonID),
           let lesson = modelContext.safeFetch(CDFetchRequest(CDLesson.self)).first(where: { $0.id == lessonID }) {
            lines.append("  From lesson: [lesson id=\(lessonID.uuidString)] \(lesson.name)")
        }
        if let presentationID = work.presentationID {
            lines.append("  Linked presentation: [presentation id=\(presentationID)]")
        }

        lines.append("  Assigned: \(dayString(work.assignedAt ?? work.createdAt))")
        if let due = work.dueAt {
            lines.append("  Due: \(dayString(due))")
        }
        if let completedAt = work.completedAt {
            lines.append("  Completed: \(dayString(completedAt))")
        }
        if let resting = work.restingUntil, work.isResting {
            lines.append("  Resting until \(dayString(resting))")
        }

        let finished = workStudentIDs(for: work).filter { work.isStudentCompleted($0) }
        if !finished.isEmpty {
            lines.append("  Finished by: \(studentNames(for: finished, in: modelContext))")
        }

        lines += stepLines(of: work)
        lines += checkInLines(of: work, in: modelContext)
        lines += noteLines(of: work)
        return lines.joined(separator: "\n")
    }

    /// States which of the two multi-student shapes this row is, because the
    /// rest of the output cannot distinguish them.
    ///
    /// A row listing three children is either one of three linked copies or a
    /// single shared row, and "remove a child" and "delete" mean different
    /// things in each case. Saying so here is what keeps a caller from reading
    /// a fan-out group as one item.
    private static func shapeLines(
        of work: CDWorkModel, in modelContext: NSManagedObjectContext
    ) -> [String] {
        let group = WorkGrouping.group(containing: work, in: modelContext)
        switch group.shape {
        case .single:
            return ["  Shape: one child on one row"]

        case .shared(let childCount):
            let designed: String
            switch work.sourceContextType {
            case .projectSession, .bookClubSession:
                designed = " (shared by design)"
            default:
                designed = ""
            }
            return ["  Shape: one shared row carrying \(childCount) children"
                + "\(designed) — no linked copies"]

        case .linkedCopies(let total):
            let position = (group.members.firstIndex { $0 === work }).map { $0 + 1 } ?? 1
            var lines = ["  Shape: \(position) of \(total) linked copies — "
                + "each child has their own row"]
            lines.append("  Linked copies:")
            for sibling in group.siblings {
                let id = sibling.id?.uuidString ?? "unknown"
                let who = WorkGrouping.owner(of: sibling)
                    .map { studentNames(for: [$0], in: modelContext) } ?? "no owner"
                lines.append("    - [work id=\(id)] \(who)")
            }
            return lines
        }
    }

    /// The child named in the row's own `studentID` field. Every other child
    /// on the row is a participant; the difference decides what "remove her"
    /// means, so it is stated rather than left to be inferred.
    private static func ownerLine(of work: CDWorkModel, in modelContext: NSManagedObjectContext) -> String {
        guard let owner = WorkGrouping.owner(of: work) else {
            return work.studentID.isEmpty
                ? "none — offered work, not yet claimed"
                : "unresolved (\(work.studentID))"
        }
        return "\(studentNames(for: [owner], in: modelContext)) (\(owner.uuidString))"
    }

    private static func stepLines(of work: CDWorkModel) -> [String] {
        let steps = work.orderedSteps
        guard !steps.isEmpty else { return [] }
        return ["  Steps:"] + steps.map { step in
            let mark = step.completedAt == nil ? "○" : "●"
            let note = nonEmpty(step.notes).map { " — \($0)" } ?? ""
            return "    \(mark) \(step.title)\(note)"
        }
    }

    private static func checkInLines(
        of work: CDWorkModel, in modelContext: NSManagedObjectContext
    ) -> [String] {
        let all = checkIns(of: work, in: modelContext)
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        guard !all.isEmpty else { return [] }
        return ["  Check-ins:"] + all.map { checkIn in
            let purpose = nonEmpty(checkIn.purpose).map { " — \($0)" } ?? ""
            let who = checkIn.studentInitiated ? " (student asked for it)" : ""
            let status = checkIn.status.rawValue.lowercased()
            return "    - \(dayString(checkIn.date)) \(status)\(purpose)\(who)"
        }
    }

    private static func noteLines(of work: CDWorkModel) -> [String] {
        let notes = ((work.unifiedNotes?.allObjects as? [CDNote]) ?? [])
            .filter { !$0.body.trimmed().isEmpty }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        guard !notes.isEmpty else { return [] }
        return ["  Observations:"] + notes.map { note in
            let id = note.id?.uuidString ?? "unknown"
            return "    - [note id=\(id)] \(dayString(note.createdAt)) — \(note.body.trimmed())"
        }
    }
}
