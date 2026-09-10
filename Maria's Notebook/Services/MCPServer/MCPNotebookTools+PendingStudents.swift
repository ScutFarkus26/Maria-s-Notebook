//
//  MCPNotebookTools+PendingStudents.swift
//  Maria's Notebook
//
//  One lesson across the whole class, read from the plan rather than the
//  record: who still has it ahead of her, when each was meant to have it,
//  and whether it is already on the calendar. This is the question a guide
//  asks when forming a group — "who is due for the checkerboard" — and
//  before it existed the answer took one year_plan call per child.
//
//  Three sources make a child pending: a planned year-plan entry the record
//  has not answered, a promoted entry (already on the calendar), and an
//  unpresented assignment with no entry behind it (a plan made straight on
//  the calendar). Everyone else is either on record as given or has no plan
//  at all, and both groups are named at the end so the guide can see who
//  could join. Every fetch here is keyed on the lesson id, so the cost is a
//  handful of small queries however large the plan grows.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Tool

    static func studentsPendingTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "students_pending",
            title: "Students Pending a Lesson",
            description: "Every enrolled child who still has one lesson ahead of her, in one call: "
                + "her year-plan target date, whether she is behind pace, and whether the lesson is "
                + "already on a scheduled presentation for her (with its day, time and group), "
                + "soonest target first. Closes with who has already had it and who has no plan for "
                + "it, so a group can be formed and handed to schedule_presentation without a "
                + "year_plan call per child. Pass a lesson id from find_lessons or the lesson's name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "lesson": [
                        "type": "string",
                        "description": "The lesson: a lesson id from find_lessons, or its name"
                    ]
                ],
                "required": ["lesson"]
            ],
            handler: { arguments in
                try describeStudentsPending(arguments: arguments, in: context())
            }
        )
    }

    // MARK: - Query

    /// What one child's plan for the lesson looks like.
    private struct PendingRow {
        let student: CDStudent
        let entry: CDYearPlanEntry?
        let behindPace: Bool
        let assignment: CDLessonAssignment?
    }

    private static func describeStudentsPending(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let lesson = try resolveLessonReference(requireString(arguments, "lesson"), in: modelContext)
        guard let lessonID = lesson.id?.uuidString else {
            throw MCPToolError("\"\(lesson.name)\" has no saved identifier.")
        }
        let students = DataQueryService(context: modelContext)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: true)
            .filter { $0.id != nil }
            .sorted { ($0.lastName, $0.firstName) < ($1.lastName, $1.firstName) }
        guard !students.isEmpty else { return "No students are enrolled." }
        let enrolledIDs = Set(students.compactMap { $0.id?.uuidString })

        let plan = LessonPlan(lessonID: lessonID, enrolledIDs: enrolledIDs, in: modelContext)

        var pending: [PendingRow] = []
        var given: [CDStudent] = []
        var unplanned: [CDStudent] = []
        for student in students {
            switch plan.standing(of: student) {
            case .pending(let row): pending.append(row)
            case .given: given.append(student)
            case .unplanned: unplanned.append(student)
            }
        }
        pending.sort(by: soonestTargetFirst)

        var lines: [String] = [
            "\(describeLesson(lesson)) — pending for \(pending.count) of \(students.count) enrolled child(ren):"
        ]
        lines.append(contentsOf: pending.isEmpty
            ? ["  none"]
            : pending.map { "- " + pendingLine($0, in: modelContext) })
        lines.append("")
        lines.append("Already given (\(given.count)): " + nameList(given))
        lines.append("No plan for it (\(unplanned.count)): " + nameList(unplanned))
        return lines.joined(separator: "\n")
    }

    private enum Standing {
        case pending(PendingRow)
        case given
        case unplanned
    }

    /// Everything the notebook holds about one lesson's plan, read once —
    /// four fetches keyed on the lesson id — and then asked about each child.
    private struct LessonPlan {
        let entryByStudent: [String: CDYearPlanEntry]
        let assignments: [CDLessonAssignment]
        let openByStudent: [String: CDLessonAssignment]
        let givenIDs: Set<String>
        let satisfaction: YearPlanSatisfaction

        init(lessonID: String, enrolledIDs: Set<String>, in modelContext: NSManagedObjectContext) {
            let entries = yearPlanEntries(lessonID: lessonID, in: modelContext)
                .filter { enrolledIDs.contains($0.studentID) }
            satisfaction = YearPlanSatisfaction.index(for: entries, in: modelContext)
            entryByStudent = Dictionary(entries.map { ($0.studentID, $0) }, uniquingKeysWith: preferredEntry)
            assignments = lessonAssignments(lessonID: lessonID, in: modelContext)
            openByStudent = openAssignmentsByStudent(assignments)
            givenIDs = givenStudentIDs(lessonID: lessonID, assignments: assignments, in: modelContext)
        }

        /// Where one child stands with the lesson. The record wins over the
        /// plan: a promoted entry whose presentation has since been given, or
        /// any entry the presentation record answers, is *given* however the
        /// entry reads — `year_plan` hides exactly those from its planned list
        /// for the same reason. Only then does the plan speak: a promoted
        /// entry, a planned one, or a presentation made straight on the
        /// calendar with no entry behind it.
        func standing(of student: CDStudent) -> Standing {
            guard let key = student.id?.uuidString else { return .unplanned }
            let entry = entryByStudent[key]
            let open = openByStudent[key]
            let promoted: CDLessonAssignment? = entry?.promotedAssignmentID.flatMap { promotedID in
                assignments.first { $0.id?.uuidString == promotedID }
            }
            if givenIDs.contains(key) || promoted?.isPresented == true
                || (entry?.isSatisfied(by: satisfaction) ?? false) {
                return .given
            }
            if let entry, entry.isPromoted {
                return .pending(PendingRow(student: student, entry: entry, behindPace: false,
                                           assignment: promoted ?? open))
            }
            if let entry, entry.isPlanned {
                return .pending(PendingRow(student: student, entry: entry,
                                           behindPace: entry.isBehindPace(satisfiedBy: satisfaction),
                                           assignment: open))
            }
            if let open {
                return .pending(PendingRow(student: student, entry: nil, behindPace: false, assignment: open))
            }
            return .unplanned
        }
    }

    // MARK: - Fetches

    private static func yearPlanEntries(
        lessonID: String, in modelContext: NSManagedObjectContext
    ) -> [CDYearPlanEntry] {
        let request = CDFetchRequest(CDYearPlanEntry.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID)
        return modelContext.safeFetch(request).filter { $0.status != .skipped }
    }

    private static func lessonAssignments(
        lessonID: String, in modelContext: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID)
        return modelContext.safeFetch(request)
    }

    /// Each child's unpresented plan for the lesson — a dated one first, the
    /// soonest of those, then the newest draft.
    private static func openAssignmentsByStudent(
        _ assignments: [CDLessonAssignment]
    ) -> [String: CDLessonAssignment] {
        var open: [String: CDLessonAssignment] = [:]
        for assignment in assignments where !assignment.isPresented {
            for studentID in assignment.studentIDs {
                if let current = open[studentID], !prefers(assignment, over: current) { continue }
                open[studentID] = assignment
            }
        }
        return open
    }

    private static func prefers(_ candidate: CDLessonAssignment, over current: CDLessonAssignment) -> Bool {
        switch (candidate.scheduledFor, current.scheduledFor) {
        case let (new?, old?): return new < old
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return (candidate.createdAt ?? .distantPast) > (current.createdAt ?? .distantPast)
        }
    }

    /// Children the record says have had the lesson: a presentation record
    /// row, or a presented assignment naming them.
    private static func givenStudentIDs(
        lessonID: String, assignments: [CDLessonAssignment], in modelContext: NSManagedObjectContext
    ) -> Set<String> {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID)
        var ids = Set(modelContext.safeFetch(request).map(\.studentID))
        for assignment in assignments where assignment.isPresented {
            ids.formUnion(assignment.studentIDs)
        }
        return ids
    }

    /// A child should hold one entry per lesson; if a migration left two, the
    /// promoted one, then the earlier target, speaks for her.
    private static func preferredEntry(_ lhs: CDYearPlanEntry, _ rhs: CDYearPlanEntry) -> CDYearPlanEntry {
        if lhs.isPromoted != rhs.isPromoted { return lhs.isPromoted ? lhs : rhs }
        return (lhs.plannedDate ?? .distantFuture) <= (rhs.plannedDate ?? .distantFuture) ? lhs : rhs
    }

    // MARK: - Output

    private static func soonestTargetFirst(_ lhs: PendingRow, _ rhs: PendingRow) -> Bool {
        let left = lhs.entry?.plannedDate ?? lhs.assignment?.scheduledFor ?? .distantFuture
        let right = rhs.entry?.plannedDate ?? rhs.assignment?.scheduledFor ?? .distantFuture
        if left != right { return left < right }
        return lhs.student.fullName.localizedCaseInsensitiveCompare(rhs.student.fullName) == .orderedAscending
    }

    /// "[student id=…] Ora Levi — target 2026-09-12 (behind pace) — scheduled
    /// 2026-09-14 at 09:00 with Etty Klein [presentation id=…]".
    private static func pendingLine(_ row: PendingRow, in modelContext: NSManagedObjectContext) -> String {
        let id: String = row.student.id?.uuidString ?? "unknown"
        var parts: [String] = ["[student id=\(id)] \(row.student.fullName)"]
        if let entry = row.entry {
            var target = entry.plannedDate.map { "target \(dayString($0))" } ?? "in the year plan, no target date"
            if row.behindPace { target += " (behind pace)" }
            parts.append(target)
        } else {
            parts.append("no year-plan entry")
        }
        parts.append(calendarStatus(row, in: modelContext))
        return parts.joined(separator: " — ")
    }

    private static func calendarStatus(_ row: PendingRow, in modelContext: NSManagedObjectContext) -> String {
        guard let assignment = row.assignment else {
            return row.entry?.isPromoted == true
                ? "promoted, but its presentation is gone"
                : "not on the calendar"
        }
        let presentationID: String = assignment.id?.uuidString ?? "unknown"
        let others = assignment.studentUUIDs.filter { $0 != row.student.id }
        let group = others.isEmpty ? "" : " with \(studentNames(for: others, in: modelContext))"
        guard let when = assignment.scheduledFor else {
            return "in the planning list, undated\(group) [presentation id=\(presentationID)]"
        }
        return "scheduled \(dayString(when)) at \(timeString(when))\(group) [presentation id=\(presentationID)]"
    }

    private static func nameList(_ students: [CDStudent]) -> String {
        students.isEmpty ? "none" : students.map(\.fullName).joined(separator: ", ")
    }
}
