//
//  MCPNotebookTools+WorkRemoval.swift
//  Cosmic Daybook
//
//  Taking one child off one work item. The only tool that deletes rows, and
//  it refuses until the guide has been shown exactly which rows and how.
//
//  The refusal is the confirmation dialog. A first call without `confirm`
//  reports the plan and changes nothing; a second call with `confirm: true`
//  runs that same plan through `WorkDeletionService`.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    static func removeStudentFromWorkTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "remove_student_from_work",
            title: "Remove Student From Work",
            description: "Take one child off one work item — for a child who withdrew, or who was "
                + "taken off the presentation the work came from. Called without confirm it only "
                + "reports what would change: which rows she is on, whether she owns each one, and "
                + "who would take over a row she owns. Nothing is written until it is called again "
                + "with confirm: true. Refuses if she is the only child left on the work.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "work_id": [
                        "type": "string",
                        "description": "The work item's id, as returned by student_work or work_detail"
                    ],
                    "student_name": [
                        "type": "string",
                        "description": "The child to remove: first name, full name, or nickname"
                    ],
                    "confirm": [
                        "type": "boolean",
                        "description": "Pass true, after reading the report, to make the change"
                    ]
                ],
                "required": ["work_id", "student_name"]
            ],
            annotations: .destructive,
            handler: { arguments in
                try removeStudentFromWork(arguments: arguments, in: context())
            }
        )
    }

    private static func removeStudentFromWork(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let work = try resolveWork(requireString(arguments, "work_id"), in: modelContext)
        let student = try resolveStudentReference(requireString(arguments, "student_name"), in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        let service = WorkDeletionService(context: modelContext)
        let plan: WorkRemovalPlan
        do {
            plan = try service.removalPlan(for: studentID, from: work)
        } catch let error as WorkDeletionService.ServiceError {
            throw MCPToolError(error.errorDescription ?? "The child could not be removed.")
        }

        let report = describeRemoval(plan, student: student, in: modelContext)
        guard arguments["confirm"]?.boolValue == true else {
            return "remove_student_from_work refused — nothing has been changed.\n"
                + "Re-call with confirm: true to proceed.\n\n" + report
        }

        do {
            try service.apply(plan)
        } catch {
            modelContext.rollback()
            throw MCPToolError("The change could not be saved: \(error.localizedDescription)")
        }
        return "Removed \(student.fullName).\n\n" + report
    }

    /// The plan, spelled out row by row, in the words the in-app dialog would use.
    static func describeRemoval(
        _ plan: WorkRemovalPlan, student: CDStudent, in modelContext: NSManagedObjectContext
    ) -> String {
        var lines: [String] = []
        let anchor = plan.group.anchor
        lines.append("Removing \(student.fullName) from [work id=\(anchor.id?.uuidString ?? "unknown")] "
            + title(of: anchor))
        lines.append("  Shape: \(shapeSummary(of: plan.group))")
        for step in plan.steps {
            let id = step.work.id?.uuidString ?? "unknown"
            let others = WorkGrouping.studentIDs(of: step.work).filter { $0 != plan.studentID }
            let remaining = others.isEmpty ? "nobody" : studentNames(for: others, in: modelContext)
            switch step.action {
            case .dropParticipant:
                lines.append("  - [work id=\(id)] she is a passenger; her participant row goes. "
                    + "Owner and the rest are untouched. After: \(remaining).")
            case .promote(let heir):
                lines.append("  - [work id=\(id)] she OWNS this shared row; her participant row goes and "
                    + "\(studentNames(for: [heir], in: modelContext)) becomes the owner. After: \(remaining).")
            case .clearOwner:
                lines.append("  - [work id=\(id)] she owns this offered project work and nobody else has "
                    + "claimed it; the owner field is cleared and the row stays open.")
            case .deleteRow:
                let cascade = WorkDeletionService(context: modelContext).cascade(for: step.work)
                lines.append("  - [work id=\(id)] this is her own linked copy; the row is deleted "
                    + "(\(cascade.observations) observations, \(cascade.checkIns) check-ins, "
                    + "\(cascade.steps) steps go with it) and her name is dropped from the other copies.")
            }
        }
        if plan.completionRecords.isEmpty {
            lines.append("  \(student.fullName) has no completion recorded on this work — "
                + "nothing is written to her history, and nothing is removed from it.")
        } else {
            let dates = plan.completionRecords.map { dayString($0.completedAt) }.joined(separator: ", ")
            lines.append("  WARNING: \(plan.completionRecords.count) completion record(s) for her "
                + "(\(dates)) will be deleted with her.")
        }
        return lines.joined(separator: "\n")
    }

    private static func shapeSummary(of group: WorkGroup) -> String {
        switch group.shape {
        case .single:
            return "one child on one row"
        case .shared(let count):
            return "one shared row carrying \(count) children — no linked copies"
        case .linkedCopies(let total):
            return "\(total) linked copies — each child has their own row"
        }
    }
}
