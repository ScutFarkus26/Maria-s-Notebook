//
//  MCPNotebookTools+StudentRecordWork.swift
//  Cosmic Daybook
//
//  The work one child is carrying: what is open, how far along, and what finished.
//  The section builders behind student_record (MCPNotebookTools+StudentRecord.swift):
//  each is the body of a tool that used to stand alone.
//

import CoreData
import Foundation

extension MCPNotebookTools {
    // MARK: - Work

    static func workSection(
        _ arguments: [String: JSONValue], for student: CDStudent, in modelContext: NSManagedObjectContext
    ) throws -> String {
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

    private static func describeStudentWork(
        student: CDStudent, studentID: UUID, includeCompleted: Bool, limit: Int,
        in modelContext: NSManagedObjectContext
    ) -> String {
        let all = allWork(for: studentID, in: modelContext)
        let open = all.filter { !$0.isClosed }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        let done = all.filter(\.isClosed)
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
                return "- [work id=\(id)] \(title(of: work)) — finished "
                    + "\(dayString(work.completedAt)) (\(work.status.displayName))"
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
}
