// WorkPrintView+Grouping.swift
// WorkPrintGroup type and grouping logic for WorkPrintView

import Foundation

struct WorkPrintGroup: Identifiable {
    let id: String
    let title: String
    let student: CDStudent?
    let works: [CDWorkModel]
}

extension WorkPrintView {

    var groupedWork: [WorkPrintGroup] {
        Self.computeGroups(workItems: workItems, students: students)
    }

    static func computeGroups(workItems: [CDWorkModel], students: [CDStudent]) -> [WorkPrintGroup] {
        // Group work by student for clearer organization
        let studentDict = Dictionary(grouping: workItems) { work in
            work.studentID
        }

        let groups: [WorkPrintGroup] = studentDict.map { (studentIDString, works) in
            let studentID = UUID(uuidString: studentIDString)
            let student = studentID.flatMap { id in students.first(where: { $0.id == id }) }
            let title: String
            if let student {
                title = student.fullName
            } else if studentIDString.trimmed().isEmpty {
                title = "Unassigned Student"
            } else {
                title = "Unknown Student"
            }

            let sorted = works.sorted { work1, work2 in
                // Sort by due date, then by assigned date
                if let due1 = work1.dueAt, let due2 = work2.dueAt {
                    return due1 < due2
                }
                if work1.dueAt != nil { return true }
                if work2.dueAt != nil { return false }
                return (work1.assignedAt ?? .distantPast) < (work2.assignedAt ?? .distantPast)
            }

            let groupID = studentIDString.trimmed().isEmpty ? "unassigned" : studentIDString
            return WorkPrintGroup(id: groupID, title: title, student: student, works: sorted)
        }

        return groups.sorted { lhs, rhs in
            if lhs.student != nil && rhs.student == nil { return true }
            if lhs.student == nil && rhs.student != nil { return false }
            return lhs.title < rhs.title
        }
    }
}
