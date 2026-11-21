// ReportNotes.swift
// Which notes go into a child's report, and what they say there (domain
// logic review 2026-11-20, R1). A note about two children is in both
// reports, so before a report is drafted or printed every other child's name
// in it becomes "a classmate" (plan "Domain logic fixes", Decision 3).

import CoreData
import Foundation

enum ReportNotes {

    /// The notes marked Include in Report that are about her, written within
    /// `range`: her own, the group notes naming her, and the class's notes
    /// (context notes aside, `NoteAudience.withClass`). Newest first. The one
    /// picker for the report PDF, the monthly draft and the rollover's count.
    static func flagged(
        for student: CDStudent, in range: ClosedRange<Date>, context: NSManagedObjectContext
    ) -> [CDNote] {
        guard let studentID = student.id else { return [] }
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(
                format: "includeInReport == YES AND createdAt >= %@ AND createdAt <= %@",
                range.lowerBound as NSDate, range.upperBound as NSDate
            ),
            CDNote.aboutPredicate(studentID, .withClass)
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return context.safeFetch(request).filter { $0.isAbout(studentID, .withClass) }
    }

    /// What stands in for another child's name in her report.
    static let classmate = "a classmate"

    /// Swaps every other child's name in `student`'s report text for "a
    /// classmate": the children who hadn't left by the start of `range`, as
    /// the report queue counts the class (`ParentReportsQueueView.studentsInClass`).
    /// Names are matched as `NameAnonymizer` matches them (whole words,
    /// written as a name), and never one of hers, so a classmate who shares
    /// her first name is left out by her full or short name only.
    static func classmateNames(
        for student: CDStudent, during range: ClosedRange<Date>, calendar: Calendar = AppCalendar.shared
    ) -> NameAnonymizer {
        guard let context = student.managedObjectContext else { return NameAnonymizer(students: []) }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.notLeftPredicate(by: range.lowerBound, calendar: calendar)
        let others = context.safeFetch(request).filter { $0.id != student.id && !$0.isDeleted }
        return NameAnonymizer.classmates(of: student, among: others, label: classmate)
    }
}
