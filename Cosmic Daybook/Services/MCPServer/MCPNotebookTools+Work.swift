//
//  MCPNotebookTools+Work.swift
//  Cosmic Daybook
//
//  Reading the work children are carrying: what is open, what it grew out of,
//  how far along it is, and when it was finished.
//
//  Assigning and updating work lives in MCPNotebookTools+WorkWrites.swift.
//

import CoreData
import Foundation

extension MCPNotebookTools {

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
                        "description": "The work item's id, as returned by student_record (work) or search_notebook"
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

        lines.append("  Status: \(work.status.displayName)")
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
            // The title, not the stored spelling: see CheckInReason.displayName.
            let purpose = nonEmpty(checkIn.purpose)
                .map { " — \(CheckInReason.displayName(forStoredPurpose: $0))" } ?? ""
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
