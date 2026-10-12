//
//  MCPNotebookTools+WorkCompletion.swift
//  Cosmic Daybook
//
//  update_work's `completed_by`: one child finished, the item stays open.
//  Split out of +WorkWrites when the linked-copy refusal (bug hunt
//  2026-10-12, #15) took that file past SwiftLint's length limit.
//  `complete_check_in_on` moved in from +WorkCheckIns for the same reason
//  when its reply began naming the todos it closes.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// Records one child as finished without closing the item for everyone —
    /// group work is often finished at different times.
    ///
    /// That holds for a shared row: one row with several children on it. A
    /// linked copy belongs to its owner alone, though it names the whole
    /// group, so a classmate's finish is refused with their own copy's id,
    /// and the owner's own finish (or the only child's) is refused toward
    /// `status`, which closes the work. Beside a closing `status` it is
    /// refused too: the status records the finish itself.
    static func applyStudentCompletion(
        _ arguments: [String: JSONValue], to work: CDWorkModel, workID: UUID,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let reference = nonEmpty(arguments["completed_by"]?.stringValue) else { return [] }
        try refuseCompletionBesideClosingStatus(arguments)
        let student = try resolveStudentReference(reference, in: modelContext)
        guard let studentID = student.id, involves(studentID, in: work) else {
            throw MCPToolError("\(student.fullName) is not on this work item.")
        }
        try refuseFinishOnOwnRow(student, studentID: studentID, work: work, in: modelContext)
        try refuseClassmateOnLinkedCopy(student, studentID: studentID, work: work, in: modelContext)
        do {
            // Saved with the rest of the call, so a later argument's refusal
            // undoes this too.
            try WorkCompletionService.markCompleted(
                workID: workID, studentID: studentID,
                note: nonEmpty(arguments["note"]?.stringValue) ?? "",
                in: modelContext,
                saveImmediately: false
            )
        } catch {
            throw MCPToolError("That completion could not be recorded", underlying: error)
        }
        work.participant(for: studentID)?.completedAt = Date()
        return ["recorded \(student.fullName) as finished"]
    }

    /// A closing status writes the completion record and files the note for
    /// every row it logs, so completed_by beside it wrote both twice.
    private static func refuseCompletionBesideClosingStatus(_ arguments: [String: JSONValue]) throws {
        let outcome = try completionOutcomeArgument(arguments, "outcome")
        guard let raw = nonEmpty(arguments["status"]?.stringValue) ?? outcome.map({ _ in WorkStatus.done.rawValue }),
              WorkStatus(rawValue: raw) != nil else { return }
        let status = WorkStatusMigration.mergedStatus(statusRaw: raw, outcomeRaw: outcome?.rawValue)
        guard status.isClosed else { return }
        throw MCPToolError(
            "completed_by and status \(status.rawValue) both record a finish, so together they'd record it "
                + "twice. Nothing has been changed. Pass status alone to close the work, or completed_by alone "
                + "to record one child's finish on a row several children share."
        )
    }

    /// completed_by on the child's own linked copy, or on a row with only one
    /// child, recorded a finish and left the work open on her schedule.
    /// Closing it is what `status` does, so the call is pointed there.
    private static func refuseFinishOnOwnRow(
        _ student: CDStudent, studentID: UUID, work: CDWorkModel, in modelContext: NSManagedObjectContext
    ) throws {
        let onlyChild = WorkGrouping.studentIDs(of: work).count == 1
        let ownLinkedCopy = WorkGrouping.owner(of: work) == studentID
            && !WorkGrouping.group(containing: work, in: modelContext).siblings.isEmpty
        guard onlyChild || ownLinkedCopy else { return }
        let whose = onlyChild
            ? "\(student.fullName) is the only child on this work"
            : "This is \(student.fullName)'s own copy of the work"
        throw MCPToolError(
            "\(whose), so completed_by would record a finish and leave the work open. Nothing has been "
                + "changed. To log the finish, call update_work with status (mastered, keepPracticing, "
                + "incomplete or complete)."
        )
    }

    /// Throws when `work` is one of a set of linked copies and the named
    /// child has their own copy in that set. A row the child is only named on,
    /// with no copy of their own beside it, reads as shared and is let through.
    private static func refuseClassmateOnLinkedCopy(
        _ student: CDStudent, studentID: UUID, work: CDWorkModel, in modelContext: NSManagedObjectContext
    ) throws {
        guard let owner = WorkGrouping.owner(of: work), owner != studentID else { return }
        let group = WorkGrouping.group(containing: work, in: modelContext)
        guard let own = group.siblings.first(where: { WorkGrouping.owner(of: $0) == studentID }) else { return }
        throw MCPToolError(
            "This is \(studentNames(for: [owner], in: modelContext))'s own copy of the work, and "
                + "\(student.fullName) has their own copy [work id=\(own.id?.uuidString ?? "unknown")]. "
                + "Nothing has been changed. To log that finish, call update_work on that copy with status."
        )
    }

    // MARK: - Completing

    /// Through the app's service, so the work's linked todos close with it;
    /// the check-in keeps its day, which is how MCP names it. The service
    /// closes those todos without a word, so the reply names them.
    static func applyCheckInCompletion(
        _ arguments: [String: JSONValue], to work: CDWorkModel,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let day = try dayArgument(arguments, "complete_check_in_on") else { return [] }
        let checkIn = try scheduledCheckIn(of: work, on: day, in: modelContext)
        let closing = openTodos(linkedTo: checkIn.work?.id ?? UUID(uuidString: checkIn.workID), in: modelContext)
        do {
            try WorkCheckInService(context: modelContext).markCompleted(checkIn, at: checkIn.date ?? day)
        } catch {
            throw MCPToolError("That check-in could not be completed", underlying: error)
        }
        let line = "completed the check-in on \(dayString(day))"
        guard !closing.isEmpty else { return [line] }
        let named = closing
            .map { "\"\($0.title)\" [todo id=\(citationID($0.id))]" }
            .joined(separator: "; ")
        return [line + " and closed the work's linked todo\(closing.count == 1 ? "" : "s") \(named)"]
    }

    /// The open todos `TodoCompletionService.completeTodosLinked` will close
    /// for `workID`, read with the same predicate before it runs.
    private static func openTodos(linkedTo workID: UUID?, in modelContext: NSManagedObjectContext) -> [CDTodoItem] {
        guard let workID else { return [] }
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(
            format: "isCompleted == NO AND linkedWorkItemID ==[c] %@", workID.uuidString
        )
        return modelContext.safeFetch(request).sorted { $0.title < $1.title }
    }
}
